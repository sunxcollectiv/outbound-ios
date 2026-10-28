//
//  NotificationsAPI.swift
//  outbound
//

import Foundation

/// `NotificationCategory` — the coarse kind of a notification. Unknown values (a
/// category the app doesn't know yet) decode as `.other` so the inbox still loads.
enum NotificationCategory: String, Codable {
    /// Service notices from us.
    case announcement
    /// Marketing, opt-in.
    case promotion
    /// Something another member did on a shared trip.
    case tripActivity = "trip_activity"
    /// About the user's own travel: flight details, reminders.
    case travelAlert = "travel_alert"
    case other

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = NotificationCategory(rawValue: raw) ?? .other
    }
}

/// `NotificationRead` — one entry in the user's inbox. The title and body are
/// written by the server when it's sent; `tripId` and `tripItemId` go nil if what
/// it was about is deleted. `type` says exactly what happened (e.g.
/// "trip_item.updated"). The server's free-form `data` isn't decoded yet.
struct AppNotification: Codable, Identifiable, Equatable {
    let id: String
    let category: NotificationCategory
    let type: String
    let title: String
    let body: String?
    /// Who caused it, when it's someone's doing.
    let actor: User?
    let tripId: String?
    let tripItemId: String?
    /// When it arrived in the inbox; the inbox is ordered by this.
    let visibleAt: Date
    var readAt: Date?

    var isRead: Bool { readAt != nil }
}

/// Request shapes for the notifications endpoints.
///
///     GET    /notifications?limit&before   -> NotificationPage
///     GET    /notifications/unread-count   -> UnreadCount
///     POST   /notifications/read-all       -> UnreadCount
///     POST   /notifications/{id}/read      -> NotificationRead
///     DELETE /notifications/{id}/read      -> NotificationRead
///     DELETE /notifications/{id}           -> 204 (dismisses it)
enum NotificationsAPI {
    /// `NotificationPage` — newest first. Pass `nextCursor` as `before` for the next
    /// page; nil when there's no more.
    struct Page: Decodable {
        let items: [AppNotification]
        let nextCursor: String?
    }

    struct UnreadCount: Decodable {
        let count: Int
    }

    static func list(before: String? = nil, limit: Int = 25) -> Endpoint {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let before {
            query.append(URLQueryItem(name: "before", value: before))
        }
        return Endpoint(path: "/notifications", query: query)
    }

    static let unreadCount = Endpoint(path: "/notifications/unread-count")

    static let markAllRead = Endpoint(path: "/notifications/read-all", method: .post)

    static func markRead(id: String) -> Endpoint {
        Endpoint(path: "/notifications/\(id)/read", method: .post)
    }

    static func markUnread(id: String) -> Endpoint {
        Endpoint(path: "/notifications/\(id)/read", method: .delete)
    }

    static func dismiss(id: String) -> Endpoint {
        Endpoint(path: "/notifications/\(id)", method: .delete)
    }
}
