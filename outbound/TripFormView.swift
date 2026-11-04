//
//  TripFormView.swift
//  outbound
//

import SwiftUI

/// Modal for manually creating or editing a trip. Collects a name, start/end dates,
/// and an optional description. Timezone and locations come later, derived from trip
/// items. Pass an existing `trip` to edit it; omit it to create a new one. Pass
/// `segmentOf` instead to create a segment: a trip of the user's own, grouped with
/// that one and just before or after it.
struct TripFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var auth

    /// The trip being edited, or `nil` when creating a new one.
    private let trip: Trip?
    /// The trip a new segment is grouped with, or `nil` for an ordinary trip.
    private let segmentOf: Trip?

    /// Called with the created or updated trip after a successful save.
    var onSaved: (Trip) -> Void
    /// Called after the trip being edited is deleted.
    var onDeleted: () -> Void

    @State private var title: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var description: String
    /// The areas the trip covers, shown as chips.
    @State private var areas: [Area]
    /// Ids of areas marked for removal. They stay as chips, faded, until the trip is
    /// saved without them, so a mistaken tap can be undone.
    @State private var areaIdsToRemove: Set<String> = []
    @State private var showingAreaPicker = false
    /// Emails of everyone on the trip besides the owner, as edited in the invite popup.
    @State private var memberEmails: [String]
    /// `memberEmails` as the trip had it when the form opened, so an edit only sends
    /// the roster when it changed.
    private let originalMemberEmails: [String]
    @State private var showingMemberInvite = false
    /// Whether saving an edit tells the trip's other members what changed.
    @State private var notifyMembers = false
    /// The sheet's bottom safe area (the home indicator's strip), measured so the
    /// bottom bar can sit partway into it.
    @State private var homeIndicatorInset: CGFloat = 0
    @State private var activeField: DateField?
    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    /// Whether an edited trip's own dates are still loading. A trip from the list that
    /// has extensions carries its whole group's span instead, which saving would write
    /// over the trip's real dates, so saving waits for them.
    @State private var isLoadingOwnDates: Bool
    /// A save that costs credits, waiting on the user: to confirm the charge, or to buy
    /// credits first when they're short.
    @State private var pendingCharge: PendingCharge?

    private enum DateField { case start, end }

    private let api = APIClient.shared

    private var isEditing: Bool { trip != nil }

    /// `segmentEdge` is the side of `segmentOf` the new trip goes on: `.leading` for
    /// days before it, `.trailing` for days after. Its dates start on the adjacent day.
    init(
        trip: Trip? = nil,
        segmentOf: Trip? = nil,
        segmentEdge: HorizontalEdge = .trailing,
        onSaved: @escaping (Trip) -> Void = { _ in },
        onDeleted: @escaping () -> Void = {}
    ) {
        self.trip = trip
        self.segmentOf = segmentOf
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        _title = State(initialValue: trip?.title ?? "")
        _description = State(initialValue: trip?.description ?? "")
        let defaultDate = segmentOf.flatMap { Self.adjacentDate(to: $0, on: segmentEdge) } ?? Date()
        _startDate = State(initialValue: trip.flatMap { Self.apiDateFormatter.date(from: $0.startDate) } ?? defaultDate)
        _endDate = State(initialValue: trip.flatMap { Self.apiDateFormatter.date(from: $0.endDate) } ?? defaultDate)
        _areas = State(initialValue: trip?.areas ?? [])
        // The owner is always kept by the server, so they aren't listed or sent.
        let others = (trip?.members ?? []).filter { $0.user?.id != trip?.ownerId }.map(\.email)
        originalMemberEmails = others
        _memberEmails = State(initialValue: others)
        _isLoadingOwnDates = State(initialValue: trip?.extensions?.isEmpty == false)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        if segmentOf != nil {
                            segmentHelp
                        }

                        TextField("Trip name", text: $title)
                            .textInputAutocapitalization(.words)
                            .appField()

                        areaChips

                        membersSection

                        VStack(alignment: .leading, spacing: 6) {
                            VStack(spacing: 8) {
                                dateRow(title: "Start", date: startDate, field: .start)
                                if activeField == .start {
                                    DatePicker("", selection: $startDate, displayedComponents: .date)
                                        .datePickerStyle(.graphical)
                                        .labelsHidden()
                                        .onChange(of: startDate) { _, newValue in
                                            if endDate < newValue { endDate = newValue }
                                            withAnimation { activeField = nil }
                                        }
                                }
                                Divider().overlay(Color.appForeground.opacity(0.2))
                                dateRow(title: "End", date: endDate, field: .end)
                                if activeField == .end {
                                    DatePicker("", selection: $endDate, in: startDate..., displayedComponents: .date)
                                        .datePickerStyle(.graphical)
                                        .labelsHidden()
                                        .onChange(of: endDate) { _, _ in
                                            withAnimation { activeField = nil }
                                        }
                                }
                            }
                            .padding(14)
                            .background(Color.appForeground.opacity(0.08), in: .rect(cornerRadius: appFieldCornerRadius))

                            Text("These should be based on your arrival and departure times at the expected location.")
                                .font(.caption)
                                .foregroundStyle(Color.appForeground.opacity(0.7))
                        }

                        TextField("Description (optional)", text: $description, axis: .vertical)
                            .lineLimit(3...6)
                            .appField()

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(24)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .foregroundStyle(Color.appForeground)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .accessibilityLabel("Close")
                    }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { homeIndicatorInset = $0 }
        .task { await loadOwnDates() }
        .overlay { memberInvitePopup }
        .overlay { chargePopup }
        .offlinePillNearBottom(isActive: showingMemberInvite || pendingCharge != nil)
        .appTheme()
    }

    private var navigationTitle: String {
        if isEditing { return "Edit Trip" }
        return segmentOf != nil ? "Add trip extension" : "New Trip"
    }

    /// Explains what saving a segment does, above the form.
    private var segmentHelp: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.subheadline.weight(.semibold))
            Text("Adding a trip extension creates a new segment with it's own members that you manage. Members of the original trip get limited visibility into its itinerary.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.appForeground.opacity(0.85))
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appForeground.opacity(0.08), in: .rect(cornerRadius: appFieldCornerRadius))
    }

    /// The day just before `trip` starts (`.leading`) or just after it ends (`.trailing`).
    private static func adjacentDate(to trip: Trip, on edge: HorizontalEdge) -> Date? {
        let isLeading = edge == .leading
        guard let date = apiDateFormatter.date(from: isLeading ? trip.startDate : trip.endDate) else { return nil }
        return Calendar(identifier: .gregorian).date(byAdding: .day, value: isLeading ? -1 : 1, to: date)
    }

    /// Only edits can notify (creating a trip can't), and only when someone else is on it.
    private var canNotifyMembers: Bool { isEditing && !memberEmails.isEmpty }

    /// Only the owner can delete a trip; organizers can edit it but not delete it.
    private var canDelete: Bool {
        guard let trip, let userId = auth.currentUser?.id else { return false }
        return trip.ownerId == userId
    }

    private var bottomBar: some View {
        FormBottomBar(
            notifyLabel: canNotifyMembers ? "Notify members of changes" : nil,
            notifyMembers: $notifyMembers,
            saveTitle: isEditing ? "Save" : segmentOf != nil ? "Add Segment" : "Add Trip",
            canSave: !title.trimmingCharacters(in: .whitespaces).isEmpty && !isLoadingOwnDates,
            isSaving: isSaving,
            onSave: save,
            delete: canDelete
                ? FormBottomBar.Delete(
                    title: "Delete Trip",
                    confirmation: "Delete this trip?",
                    message: "Everything on it is deleted for everyone on the trip. This can't be undone.",
                    action: delete
                )
                : nil,
            isDeleting: isDeleting,
            homeIndicatorInset: homeIndicatorInset,
            background: .appBackground
        )
    }

    /// Replaces the group-wide dates the list gave with the trip's own (see
    /// `isLoadingOwnDates`).
    private func loadOwnDates() async {
        guard isLoadingOwnDates, let trip else { return }
        do {
            let own = try await api.send(TripsAPI.read(id: trip.id), as: Trip.self)
            if let start = Self.apiDateFormatter.date(from: own.startDate),
               let end = Self.apiDateFormatter.date(from: own.endDate) {
                startDate = start
                endDate = end
            }
            isLoadingOwnDates = false
        } catch {
            // Saving stays off rather than risk writing the group's span over the trip.
            errorMessage = "Couldn't load this trip's dates. Close and try again."
        }
    }

    private func delete() {
        guard let trip else { return }
        errorMessage = nil
        isDeleting = true
        Task {
            defer { isDeleting = false }
            do {
                try await api.send(TripsAPI.delete(id: trip.id))
                onDeleted()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// The `area_ids` to send: the final selection, without any chips marked for
    /// removal. The server replaces the trip's areas with exactly this list.
    private var areaIdsToSave: [String] {
        areas.map(\.id).filter { !areaIdsToRemove.contains($0) }
    }

    /// The `members` to send, or nil to leave the roster alone when nothing changed.
    /// The server replaces the roster with this list, so people already on the trip
    /// keep their current role; new ones get the default.
    private var membersToSave: [TripsAPI.MemberRequest]? {
        guard memberEmails != originalMemberEmails else { return nil }
        let roles = Dictionary((trip?.members ?? []).map { ($0.email, $0.role) }, uniquingKeysWith: { first, _ in first })
        return memberEmails.map { TripsAPI.MemberRequest(email: $0, role: roles[$0]) }
    }

    /// An area's chip, with a button that toggles marking it for removal.
    private func areaChip(_ area: Area) -> some View {
        let isMarked = areaIdsToRemove.contains(area.id)
        return HStack(spacing: 6) {
            Text(area.name)
                .font(.subheadline.weight(.medium))
            Button {
                if isMarked {
                    areaIdsToRemove.remove(area.id)
                } else {
                    areaIdsToRemove.insert(area.id)
                }
            } label: {
                Image(systemName: isMarked ? "minus.circle.fill" : "xmark")
                    .font(.footnote.weight(.semibold))
                    // Same footprint for both icons so the chip doesn't change width.
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isMarked ? "Keep \(area.name)" : "Remove \(area.name)")
        }
        .foregroundStyle(Color.black.opacity(0.85))
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.9), in: .rect(cornerRadius: 8))
        .opacity(isMarked ? 0.8 : 1)
    }

    /// A chip per area, then a dashed chip for adding another.
    private var areaChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Areas")
                .font(.subheadline.weight(.semibold))
            FlowLayout(spacing: 8) {
                ForEach(areas) { area in
                    areaChip(area)
                }
                Button { showingAreaPicker = true } label: {
                    Label("Add area", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                .foregroundStyle(Color.appForeground.opacity(0.7))
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showingAreaPicker) {
            AreaPickerSheet(excludedIds: Set(areas.map(\.id))) { areas.append($0) }
        }
    }

    /// "Traveling Solo" until someone is invited, then a count of the others.
    private var membersSummary: String {
        switch memberEmails.count {
        case 0: "Traveling Solo"
        case 1: "You and 1 other"
        case let count: "You and \(count) others"
        }
    }

    /// A one-line row summarizing who's on the trip; tapping it opens the invite popup.
    private var membersSection: some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { showingMemberInvite = true }
        } label: {
            HStack {
                Text("Members")
                Spacer()
                Text(membersSummary)
                    .foregroundStyle(Color.appForeground.opacity(0.75))
            }
            .padding(14)
            .background(Color.appForeground.opacity(0.08), in: .rect(cornerRadius: appFieldCornerRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func closeMemberInvite() {
        withAnimation(.snappy(duration: 0.2)) { showingMemberInvite = false }
    }

    /// The open invite popup over a dimmed form; tapping outside closes it.
    @ViewBuilder
    private var memberInvitePopup: some View {
        if showingMemberInvite {
            DimmedPopup(onClose: closeMemberInvite) {
                MemberInvitePopup(emails: $memberEmails, onClose: closeMemberInvite)
            }
        }
    }

    private func closeCharge() {
        withAnimation(.snappy(duration: 0.2)) { pendingCharge = nil }
    }

    /// The charge confirmation, or the purchase popup when the user's credits fall
    /// short, over the dimmed form.
    @ViewBuilder
    private var chargePopup: some View {
        if let pendingCharge {
            DimmedPopup(onClose: closeCharge) {
                if pendingCharge.needsCredits {
                    PurchasePopup(onClose: closeCharge, shortfall: pendingCharge.quote, refundsGoTo: ownerNameIfNotPayer)
                } else {
                    ChargeConfirmationPopup(
                        tripTitle: pendingCharge.body.title,
                        quote: pendingCharge.quote,
                        refundsGoTo: ownerNameIfNotPayer,
                        onConfirm: { confirmCharge(pendingCharge) },
                        onClose: closeCharge
                    )
                }
            }
        }
    }

    /// The owner's name when an organizer other than the owner is editing, since any
    /// refund for the trip goes to the owner. Nil for the owner, and for a new trip
    /// (whoever creates it owns it).
    private var ownerNameIfNotPayer: String? {
        guard let trip, let ownerId = trip.ownerId, ownerId != auth.currentUser?.id else { return nil }
        let owner = trip.members?.first { $0.user?.id == ownerId }
        return owner?.user?.displayName ?? owner?.email ?? "the trip's owner"
    }

    private func confirmCharge(_ charge: PendingCharge) {
        closeCharge()
        isSaving = true
        Task {
            defer { isSaving = false }
            await commit(charge.body, quote: charge.quote)
        }
    }

    /// A tappable row showing a date; tapping toggles the inline picker below it.
    private func dateRow(title: String, date: Date, field: DateField) -> some View {
        Button {
            withAnimation { activeField = (activeField == field) ? nil : field }
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(date, style: .date)
                    .foregroundStyle(activeField == field ? Color.appAccent : Color.appForeground)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func save() {
        let name = title.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        guard endDate >= startDate else {
            errorMessage = "End date can't be before the start date."
            return
        }
        errorMessage = nil
        isSaving = true
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = TripsAPI.CreateRequest(
            title: name,
            description: trimmedDescription.isEmpty ? nil : trimmedDescription,
            startDate: Self.apiDateFormatter.string(from: startDate),
            endDate: Self.apiDateFormatter.string(from: endDate),
            // Seed the trip's days with the device's zone on create; PATCH doesn't take it.
            timezone: isEditing ? nil : TimeZone.current.identifier,
            areaIds: areaIdsToSave,
            members: membersToSave,
            notifyMembers: canNotifyMembers && notifyMembers ? true : nil,
            extendsTripId: isEditing ? nil : segmentOf?.id
        )
        Task {
            defer { isSaving = false }
            await quoteThenSave(body)
        }
    }

    /// Asks the server what the save would cost before making it. Free saves go
    /// straight through; otherwise the user confirms the charge, or buys credits first
    /// when they're short (see `chargePopup`).
    private func quoteThenSave(_ body: TripsAPI.CreateRequest, retrying: Bool = false) async {
        do {
            let endpoint = trip.map { TripsAPI.quote(id: $0.id, body) } ?? TripsAPI.quote(body)
            let quote = try await api.send(endpoint, as: TripQuote.self)
            if quote.priceCents == 0 {
                await commit(body, quote: quote, retrying: retrying)
            } else {
                withAnimation(.snappy(duration: 0.2)) { pendingCharge = PendingCharge(body: body, quote: quote) }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Saves the trip at the price `quote` showed. If the price or the user's credits
    /// changed since (409, 402), quotes again once to show the new numbers.
    private func commit(_ body: TripsAPI.CreateRequest, quote: TripQuote, retrying: Bool = false) async {
        var body = body
        body.expectedPriceCents = quote.priceCents
        do {
            let endpoint = trip.map { TripsAPI.update(id: $0.id, body) } ?? TripsAPI.create(body)
            let saved = try await api.send(endpoint, as: Trip.self)
            onSaved(saved)
            dismiss()
        } catch APIError.server(let status, _) where !retrying && (status == 402 || status == 409) {
            body.expectedPriceCents = nil
            await quoteThenSave(body, retrying: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Formats a picked date as the API's "yyyy-MM-dd" calendar date, in the user's timezone.
    private static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

#Preview {
    TripFormView()
        .environment(AuthStore())
}

/// A trip save that costs credits, with the quote shown for it.
private struct PendingCharge {
    let body: TripsAPI.CreateRequest
    let quote: TripQuote

    /// Whether the user has to buy credits before they can save.
    var needsCredits: Bool { quote.shortfallCents > 0 }
}
