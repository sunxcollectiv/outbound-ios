//
//  ServerContractTests.swift
//  outboundTests
//

import Foundation
import Testing
@testable import outbound

/// Every endpoint the app calls, sent with the app's own request bodies and decoded
/// into its own models, against the local dev server (`APIConfig.baseURL`). Catches a
/// server change that moves, locks down or reshapes something the app relies on.
///
/// Skipped when no server answers at the base URL. Each test registers throwaway
/// accounts (`contract-…@example.com`) and deletes the trips it creates.
@MainActor
@Suite(.serialized, .enabled(if: DevServer.isUp, "No dev server at \(APIConfig.baseURL)"))
struct ServerContractTests {
    private let cache = ResponseCache(directory: URL.temporaryDirectory.appending(path: "ServerContractTests-\(UUID().uuidString)"))

    private func client(token: String? = nil) -> APIClient {
        let client = APIClient(session: URLSession(configuration: .ephemeral), cache: cache)
        client.token = token
        return client
    }

    private struct Account {
        let api: APIClient
        let user: User
        let password: String
    }

    private func register(_ name: String = "Contract") async throws -> Account {
        let email = "contract-\(UUID().uuidString.lowercased())@example.com"
        let password = "contract-\(UUID().uuidString)"
        let session = try await client().send(
            AuthAPI.register(email: email, password: password, displayName: name), as: AuthAPI.Session.self
        )
        #expect(session.user.email == email)
        #expect(session.expiresAt > .now)
        return Account(api: client(token: session.token), user: session.user, password: password)
    }

    private func status(of error: Error) -> Int? {
        switch error as? APIError {
        case .unauthorized: 401
        case .server(let status, _): status
        default: nil
        }
    }

    /// A trip from Mar 1–4 next year in Tokyo time, with `others` on it as members.
    private func makeTrip(_ owner: Account, with others: [Account] = [], areaIds: [String]? = nil) async throws -> Trip {
        let year = Calendar.current.component(.year, from: .now) + 1
        let body = TripsAPI.CreateRequest(
            title: "Contract trip",
            description: "Made by ServerContractTests",
            startDate: "\(year)-03-01",
            endDate: "\(year)-03-04",
            timezone: "Asia/Tokyo",
            areaIds: areaIds,
            members: others.map { TripsAPI.MemberRequest(email: $0.user.email) }
        )
        return try await owner.api.send(TripsAPI.create(body), as: Trip.self)
    }

    private func wallClock(_ trip: Trip, day: Int, _ time: String) -> String {
        let parts = trip.startDate.split(separator: "-")
        return "\(parts[0])-\(parts[1])-\(String(format: "%02d", Int(parts[2])! + day))T\(time)"
    }

    // MARK: - Auth

    @Test func registerLoginMeAndLogout() async throws {
        let account = try await register("Contract Auth")

        let me = try await account.api.send(AuthAPI.me, as: User.self)
        #expect(me == account.user)

        let login = try await client().send(
            AuthAPI.login(email: account.user.email, password: account.password), as: AuthAPI.Session.self
        )
        #expect(login.user.id == account.user.id)

        // A wrong password is the server's message, not "session expired".
        await #expect {
            try await client().send(AuthAPI.login(email: account.user.email, password: "wrong"), as: AuthAPI.Session.self)
        } throws: { status(of: $0) == 401 && ($0 as? APIError).map { if case .server = $0 { true } else { false } } == true }

        let fresh = client(token: login.token)
        try await fresh.send(AuthAPI.logout)
        await #expect { try await fresh.send(AuthAPI.me, as: User.self) } throws: { status(of: $0) == 401 }
        // Logging out one device leaves the other signed in.
        _ = try await account.api.send(AuthAPI.me, as: User.self)
    }

    // MARK: - Trips, days, members

    @Test func tripLifecycle() async throws {
        let owner = try await register("Contract Owner")
        let friend = try await register("Contract Friend")

        let areas = try await owner.api.send(AreasAPI.search("Tokyo", limit: 5), as: [Area].self)
        let trip = try await makeTrip(owner, with: [friend], areaIds: areas.first.map { [$0.id] })
        defer { Task { try? await owner.api.send(TripsAPI.delete(id: trip.id)) } }

        #expect(trip.ownerId == owner.user.id)
        let members = try #require(trip.members)
        #expect(members.contains { $0.user?.id == owner.user.id && $0.role == .organizer })
        #expect(members.contains { $0.email == friend.user.email && $0.role == .member })
        if let area = areas.first {
            #expect(trip.areas?.map(\.id) == [area.id])
            let missing = trip.areasMissingPhotos ?? []
            if !missing.isEmpty {
                _ = try await owner.api.send(AreasAPI.refreshPhotos(areaIds: missing), as: AreasAPI.RefreshPhotosResponse.self)
            }
        }

        // Both see it in their list; the list is saved for offline.
        let ownerList = try await owner.api.send(TripsAPI.list, as: [Trip].self)
        #expect(ownerList.contains { $0.id == trip.id })
        #expect(owner.api.cached(TripsAPI.list, as: [Trip].self)?.contains { $0.id == trip.id } == true)
        let friendList = try await friend.api.send(TripsAPI.list, as: [Trip].self)
        #expect(friendList.contains { $0.id == trip.id })

        // Edit: rename, keep areas, and swap the roster for nobody else.
        var edit = TripsAPI.CreateRequest(
            title: "Contract trip (edited)", description: nil,
            startDate: trip.startDate, endDate: trip.endDate, members: [], notifyMembers: true
        )
        let edited = try await owner.api.send(TripsAPI.update(id: trip.id, edit), as: Trip.self)
        #expect(edited.title == "Contract trip (edited)")
        #expect(edited.description == nil)
        #expect(edited.areas?.map(\.id) == trip.areas?.map(\.id))
        #expect(edited.members?.map(\.user?.id) == [owner.user.id])

        // Add the friend back, then they can't delete the trip, only the owner can.
        edit.members = [TripsAPI.MemberRequest(email: friend.user.email, role: .member)]
        edit.notifyMembers = nil
        _ = try await owner.api.send(TripsAPI.update(id: trip.id, edit), as: Trip.self)
        await #expect { try await friend.api.send(TripsAPI.delete(id: trip.id)) } throws: { status(of: $0) == 403 || status(of: $0) == 404 }

        // Days come with the trip, seeded with its zone; organizers can edit one.
        let days = try await owner.api.send(TripDaysAPI.list(tripId: trip.id), as: [TripDay].self)
        #expect(days.map(\.dayNumber) == [1, 2, 3, 4])
        #expect(days.allSatisfy { $0.timezones == ["Asia/Tokyo"] })
        let day = try await owner.api.send(
            TripDaysAPI.update(tripId: trip.id, date: days[1].date, .init(name: "Day trip", timezones: ["Asia/Tokyo", "UTC"])),
            as: TripDay.self
        )
        #expect(day.name == "Day trip")
        #expect(day.timezones == ["Asia/Tokyo", "UTC"])

        try await owner.api.send(TripsAPI.delete(id: trip.id))
        let after = try await owner.api.send(TripsAPI.list, as: [Trip].self)
        #expect(!after.contains { $0.id == trip.id })
    }

    /// Segments: a member adds a trip of their own next to one they're on, and the two
    /// join one group, whatever their dates.
    @Test func tripSegments() async throws {
        let owner = try await register("Contract Owner")
        let friend = try await register("Contract Friend")
        let trip = try await makeTrip(owner, with: [friend])
        defer { Task { try? await owner.api.send(TripsAPI.delete(id: trip.id)) } }
        #expect(trip.groupId == nil)
        #expect(trip.extendsTripId == nil)
        let year = trip.startDate.prefix(4)

        // The friend adds the two days after the trip (Mar 5–6) as their own segment.
        let segment = try await friend.api.send(TripsAPI.create(.init(
            title: "Contract segment", description: nil,
            startDate: "\(year)-03-05", endDate: "\(year)-03-06",
            timezone: "Asia/Tokyo", extendsTripId: trip.id
        )), as: Trip.self)
        defer { Task { try? await friend.api.send(TripsAPI.delete(id: segment.id)) } }
        #expect(segment.ownerId == friend.user.id)
        #expect(segment.extendsTripId == trip.id)
        let groupId = try #require(segment.groupId)
        #expect(segment.members?.map(\.user?.id) == [friend.user.id])

        // The trip it was added to joins the same group.
        let ownerList = try await owner.api.send(TripsAPI.list, as: [Trip].self)
        #expect(ownerList.first { $0.id == trip.id }?.groupId == groupId)

        // A segment needn't touch the trip: one with days between them joins the group too.
        let gap = try await friend.api.send(TripsAPI.create(.init(
            title: "Contract gap", description: nil,
            startDate: "\(year)-03-08", endDate: "\(year)-03-09", extendsTripId: trip.id
        )), as: Trip.self)
        defer { Task { try? await friend.api.send(TripsAPI.delete(id: gap.id)) } }
        #expect(gap.groupId == groupId)

        // The friend's merged itinerary keeps the empty day between their two segments,
        // marked as a gap.
        let itinerary = try await friend.api.send(TripsAPI.itinerary(tripId: gap.id), as: Itinerary.self)
        #expect(itinerary.days.filter(\.isGap).map(\.date) == ["\(year)-03-07"])

        // Only people on the trip can add a segment to it.
        let stranger = try await register("Contract Stranger")
        await #expect {
            try await stranger.api.send(TripsAPI.create(.init(
                title: "Contract stranger", description: nil,
                startDate: "\(year)-02-27", endDate: "\(year)-02-28", extendsTripId: trip.id
            )), as: Trip.self)
        } throws: { status(of: $0) == 404 }
    }

    // MARK: - Items and itinerary

    @Test func itemsAndItinerary() async throws {
        let owner = try await register("Contract Owner")
        let friend = try await register("Contract Friend")
        let trip = try await makeTrip(owner, with: [friend])
        defer { Task { try? await owner.api.send(TripsAPI.delete(id: trip.id)) } }
        let me = try #require(trip.members?.first { $0.user?.id == owner.user.id })
        let them = try #require(trip.members?.first { $0.email == friend.user.email })

        // An activity for both, with a zone and an end.
        let activity = try await owner.api.send(TripItemsAPI.create(tripId: trip.id, .init(
            kind: .activity, title: "Sumo", notes: "Ryogoku",
            startsAt: wallClock(trip, day: 0, "10:00:00"), startTimezone: "Asia/Tokyo",
            endsAt: wallClock(trip, day: 0, "12:00:00"), endTimezone: "Asia/Tokyo",
            placeId: nil, endPlaceId: nil,
            participants: [.init(memberId: me.id, status: .going), .init(memberId: them.id)],
            notifyMembers: true
        )), as: TripItem.self)
        #expect(activity.displayTitle == "Sumo")
        #expect(activity.startTimezone?.identifier == "Asia/Tokyo")
        #expect(activity.startsAtUtc != nil)
        #expect(Set(activity.participants.map(\.member.id)) == [me.id, them.id])
        #expect(activity.createdBy?.id == owner.user.id)

        // A zoneless, closed lodging across two nights, just for the owner.
        let lodging = try await owner.api.send(TripItemsAPI.create(tripId: trip.id, .init(
            kind: .lodging, visibility: .closed, title: "Ryokan", notes: "Room 4",
            startsAt: wallClock(trip, day: 0, "15:00:00"), startTimezone: nil,
            endsAt: wallClock(trip, day: 2, "11:00:00"), endTimezone: nil,
            placeId: nil, endPlaceId: nil
        )), as: TripItem.self)
        #expect(lodging.visibility == .closed)
        #expect(lodging.startTimezone == nil)
        #expect(lodging.participants.map(\.member.id) == [me.id])

        // A private two-leg flight sent as segments; the server derives its span.
        let flight = try await owner.api.send(TripItemsAPI.create(tripId: trip.id, .init(
            kind: .transit, visibility: .private, title: "Home", notes: nil,
            startsAt: nil, startTimezone: nil, endsAt: nil, endTimezone: nil, placeId: nil, endPlaceId: nil,
            segments: [
                .init(startsAt: wallClock(trip, day: 3, "09:00:00"), startTimezone: "Asia/Tokyo",
                      endsAt: wallClock(trip, day: 3, "11:00:00"), endTimezone: "Asia/Seoul",
                      placeId: nil, endPlaceId: nil, transitMode: .flight, carrier: "Korean Air", flightNumber: "KE 704"),
                .init(startsAt: wallClock(trip, day: 3, "13:00:00"), startTimezone: "Asia/Seoul",
                      endsAt: wallClock(trip, day: 3, "18:00:00"), endTimezone: "Asia/Seoul",
                      placeId: nil, endPlaceId: nil, transitMode: .train, confirmationNumber: "KTX1"),
            ],
            participants: [.init(memberId: me.id)]
        )), as: TripItem.self)
        #expect(flight.segments.map(\.position) == [0, 1] || flight.segments.map(\.position) == [1, 2])
        #expect(flight.segments.first?.label == "Korean Air KE 704")
        #expect(flight.transitMode == .mixed)

        // The friend sees the closed lodging redacted, and the private flight (just
        // the owner) not at all.
        let theirItems = try await friend.api.send(TripItemsAPI.list(tripId: trip.id), as: [TripItem].self)
        #expect(theirItems.first { $0.id == lodging.id }?.redacted == true)
        #expect(theirItems.first { $0.id == lodging.id }?.notes == nil)
        #expect(theirItems.contains { $0.id == activity.id })
        #expect(!theirItems.contains { $0.id == flight.id })
        let myItems = try await owner.api.send(TripItemsAPI.list(tripId: trip.id), as: [TripItem].self)
        #expect(Set(myItems.map(\.id)) == [activity.id, lodging.id, flight.id])

        // Edits: drop the activity's end and title (it has no place, so keep a title),
        // retitle, and make it just for the owner.
        var update = TripItemsAPI.UpdateRequest(TripItemsAPI.CreateRequest(
            kind: .activity, title: "Sumo (morning)", notes: "Ryogoku",
            startsAt: wallClock(trip, day: 0, "09:30:00"), startTimezone: "Asia/Tokyo",
            endsAt: nil, endTimezone: nil, placeId: nil, endPlaceId: nil,
            participants: [.init(memberId: me.id)]
        ), nullsTitleAndPlace: true)
        let edited = try await owner.api.send(TripItemsAPI.update(tripId: trip.id, itemId: activity.id, update), as: TripItem.self)
        #expect(edited.title == "Sumo (morning)")
        #expect(edited.endsAtLocal == nil)
        #expect(edited.participants.map(\.member.id) == [me.id])

        // Swap the flight's legs for one.
        update = TripItemsAPI.UpdateRequest(TripItemsAPI.CreateRequest(
            kind: .transit, title: "Home", notes: nil,
            startsAt: nil, startTimezone: nil, endsAt: nil, endTimezone: nil, placeId: nil, endPlaceId: nil,
            segments: [.init(startsAt: wallClock(trip, day: 3, "08:00:00"), startTimezone: "Asia/Tokyo",
                             endsAt: wallClock(trip, day: 3, "12:00:00"), endTimezone: "UTC",
                             placeId: nil, endPlaceId: nil, transitMode: .flight)]
        ))
        let rerouted = try await owner.api.send(TripItemsAPI.update(tripId: trip.id, itemId: flight.id, update), as: TripItem.self)
        #expect(rerouted.segments.count == 1)
        #expect(rerouted.transitMode == .flight)

        // The itinerary lays it all out by day, and is saved for offline.
        let itinerary = try await owner.api.send(TripsAPI.itinerary(tripId: trip.id), as: Itinerary.self)
        #expect(itinerary.trip.id == trip.id)
        #expect(itinerary.days.map(\.dayNumber) == [1, 2, 3, 4])
        #expect(itinerary.days[0].entries.contains { $0.item.id == activity.id })
        #expect(itinerary.days[1].lodging.contains { $0.item.id == lodging.id && $0.phase == .staying })
        #expect(itinerary.days[3].entries.contains { $0.item.id == flight.id })
        #expect(owner.api.cached(TripsAPI.itinerary(tripId: trip.id), as: Itinerary.self)?.days.count == 4)
        let theirs = try await friend.api.send(TripsAPI.itinerary(tripId: trip.id), as: Itinerary.self)
        #expect(!theirs.days.flatMap(\.entries).contains { $0.item.id == flight.id })

        try await owner.api.send(TripItemsAPI.delete(tripId: trip.id, itemId: lodging.id))
        let remaining = try await owner.api.send(TripItemsAPI.list(tripId: trip.id), as: [TripItem].self)
        #expect(!remaining.contains { $0.id == lodging.id })

        // Someone not on the trip can't see it.
        let stranger = try await register("Contract Stranger")
        await #expect { try await stranger.api.send(TripItemsAPI.list(tripId: trip.id), as: [TripItem].self) } throws: {
            status(of: $0) == 403 || status(of: $0) == 404
        }
    }

    // MARK: - Places and areas

    @Test func placesAndAreas() async throws {
        let account = try await register()

        let areas = try await account.api.send(AreasAPI.search("a", limit: 3), as: [Area].self)
        #expect(areas.count <= 3)
        let cities = try await account.api.send(AreasAPI.search("a", kind: "city", limit: 3), as: [Area].self)
        #expect(cities.allSatisfy { $0.kind == "city" })

        // Unknown ids are left out rather than failing the batch.
        let places = try await account.api.send(
            PlacesAPI.refresh(placeIds: [UUID().uuidString.lowercased()]), as: PlacesAPI.RefreshResponse.self
        )
        #expect(places.places.isEmpty)
        let photos = try await account.api.send(
            AreasAPI.refreshPhotos(areaIds: [UUID().uuidString.lowercased()]), as: AreasAPI.RefreshPhotosResponse.self
        )
        #expect(photos.areas.isEmpty)

        // Registering a place reaches the endpoint (Google may be unconfigured on dev,
        // but a user token must not be turned away).
        do {
            let place = try await account.api.send(PlacesAPI.create(googlePlaceId: "ChIJ51cu8IcbXWARiRtXIothAS4"), as: Place.self)
            #expect(place.googlePlaceId == "ChIJ51cu8IcbXWARiRtXIothAS4")
        } catch {
            #expect(![401, 403, 404, 405].contains(status(of: error) ?? 0), "POST /places: \(error)")
        }
    }

    // MARK: - Notifications and push

    @Test func notificationsInbox() async throws {
        let owner = try await register("Contract Owner")
        let friend = try await register("Contract Friend")
        let trip = try await makeTrip(owner, with: [friend])
        defer { Task { try? await owner.api.send(TripsAPI.delete(id: trip.id)) } }
        let them = try #require(trip.members?.first { $0.email == friend.user.email })
        // Something the friend hears about.
        _ = try await owner.api.send(TripItemsAPI.create(tripId: trip.id, .init(
            kind: .activity, title: "Karaoke", notes: nil,
            startsAt: wallClock(trip, day: 1, "20:00:00"), startTimezone: "Asia/Tokyo",
            endsAt: nil, endTimezone: nil, placeId: nil, endPlaceId: nil,
            participants: [.init(memberId: them.id)], notifyMembers: true
        )), as: TripItem.self)

        let page = try await friend.api.send(NotificationsAPI.list(limit: 5), as: NotificationsAPI.Page.self)
        #expect(page.items.count <= 5)
        let count = try await friend.api.send(NotificationsAPI.unreadCount, as: NotificationsAPI.UnreadCount.self)
        #expect(count.count == page.items.filter { !$0.isRead }.count || page.nextCursor != nil)

        if let next = page.nextCursor {
            _ = try await friend.api.send(NotificationsAPI.list(before: next, limit: 5), as: NotificationsAPI.Page.self)
        }

        if let first = page.items.first {
            let read = try await friend.api.send(NotificationsAPI.markRead(id: first.id), as: AppNotification.self)
            #expect(read.isRead)
            let unread = try await friend.api.send(NotificationsAPI.markUnread(id: first.id), as: AppNotification.self)
            #expect(!unread.isRead)
            try await friend.api.send(NotificationsAPI.dismiss(id: first.id))
            let after = try await friend.api.send(NotificationsAPI.list(limit: 50), as: NotificationsAPI.Page.self)
            #expect(!after.items.contains { $0.id == first.id })
        } else {
            Issue.record("Expected the friend to be notified about the trip or its item")
        }

        let cleared = try await friend.api.send(NotificationsAPI.markAllRead, as: NotificationsAPI.UnreadCount.self)
        #expect(cleared.count == 0)
    }

    @Test func pushDeviceRegistration() async throws {
        let account = try await register()
        let device = try await account.api.send(PushDevicesAPI.register(.init(
            token: String(repeating: "ab", count: 32), appVersion: "1.0", locale: "en_US", timezone: "Asia/Tokyo"
        )), as: PushDevicesAPI.Device.self)
        #expect(!device.id.isEmpty)
        try await account.api.send(PushDevicesAPI.unregister(id: device.id))
    }

    // MARK: - Screenshot import

    /// Only checks the user-facing route is still there and open to a signed-in user
    /// (an empty upload is turned away before any extraction runs).
    @Test func screenshotProcessIsOpenToUsers() async throws {
        let account = try await register()
        let empty = MultipartFile(field: "file", filename: "empty.png", contentType: "image/png", data: Data())
        await #expect {
            try await account.api.send(ReceivedImagesAPI.process(empty), as: ImageImportResult.self)
        } throws: { status(of: $0) == 422 }
        await #expect {
            try await client().send(ReceivedImagesAPI.process(empty), as: ImageImportResult.self)
        } throws: { status(of: $0) == 401 }
    }
}

/// Whether the dev server answers at all, checked once before the suite runs.
private enum DevServer {
    static let isUp: Bool = {
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var up = false
        var request = URLRequest(url: APIConfig.baseURL.appending(path: "/health"))
        request.timeoutInterval = 2
        URLSession.shared.dataTask(with: request) { _, response, _ in
            up = (response as? HTTPURLResponse)?.statusCode == 200
            done.signal()
        }.resume()
        done.wait()
        return up
    }()
}
