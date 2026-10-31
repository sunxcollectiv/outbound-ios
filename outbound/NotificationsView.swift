//
//  NotificationsView.swift
//  outbound
//

import SwiftUI

/// The notification inbox, pushed from the bell on the trips screen. Newest first,
/// loading older ones as the list nears its end. Tapping one marks it read and opens
/// its trip, if it's about one; swiping dismisses it or toggles read.
struct NotificationsView: View {
    @Bindable var store: NotificationStore
    /// Finds a trip by id for a notification to open, or nil if the user can't see it.
    let trip: (String) async -> Trip?

    /// The trip a tapped notification opened, pushed by id like on the trips screen.
    @State private var openedTripId: String?
    @State private var openedTrip: Trip?

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(LinearGradient.tripsBackground, for: .navigation)
            .overlay(alignment: .bottom) {
                // The offline pill in the trips list's spot, 8pt over the bottom safe
                // area. Notifications aren't saved for offline, so it just says
                // "Offline".
                Color.clear
                    .frame(height: 8)
                    .offlinePillAnchor()
                    .allowsHitTesting(false)
            }
            .foregroundStyle(Color.appForeground)
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                if store.unreadCount > 0 {
                    AppToolbarButton(placement: .topBarTrailing) {
                        store.markAllRead()
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .accessibilityLabel("Mark All as Read")
                    }
                }
            }
            .navigationDestination(item: $openedTripId) { _ in
                if let openedTrip {
                    TripDetailView(trip: openedTrip) { openedTripId = nil }
                }
            }
            .task { await store.load() }
            .alert(
                "Something went wrong",
                isPresented: Binding(get: { store.errorMessage != nil && !store.notifications.isEmpty },
                                     set: { if !$0 { store.errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading && store.notifications.isEmpty {
            ProgressView()
                .controlSize(.large)
                .tint(Color.appForeground)
        } else if store.notifications.isEmpty {
            emptyState
        } else {
            List {
                ForEach(store.notifications) { notification in
                    row(notification)
                }
                if store.hasMore {
                    ProgressView()
                        .tint(Color.appForeground)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .task { await store.loadMore() }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await store.load() }
        }
    }

    private func row(_ notification: AppNotification) -> some View {
        Button {
            open(notification)
        } label: {
            NotificationRow(notification: notification)
        }
        .listRowBackground(notification.isRead ? Color.clear : Color.white.opacity(0.05))
        .listRowSeparatorTint(Color.appForeground.opacity(0.12))
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.dismiss(notification)
            } label: {
                Label("Dismiss", systemImage: "xmark")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                store.setRead(notification, !notification.isRead)
            } label: {
                Label(notification.isRead ? "Unread" : "Read",
                      systemImage: notification.isRead ? "envelope.badge" : "envelope.open")
            }
            .tint(Color.tripHeader)
        }
    }

    private func open(_ notification: AppNotification) {
        store.setRead(notification, true)
        guard let tripId = notification.tripId else { return }
        Task {
            guard let found = await trip(tripId) else { return }
            openedTrip = found
            openedTripId = found.id
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bell")
                .font(.largeTitle)
                .foregroundStyle(Color.appForeground.opacity(0.5))
                .padding(.bottom, 4)
            Text("No notifications")
                .font(.title3.bold())
            Text(store.errorMessage ?? "Updates on your trips will show up here.")
                .font(.subheadline)
                .foregroundStyle(Color.appForeground.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(32)
        // Lets pull-to-refresh work on the empty screen too.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .refreshable { await store.load() }
    }
}

/// One inbox entry: who or what it's from, the text, when, and an unread dot.
struct NotificationRow: View {
    let notification: AppNotification

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(notification.title)
                        .font(.subheadline.weight(notification.isRead ? .regular : .semibold))
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text(notification.visibleAt, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                        .font(.caption)
                        .foregroundStyle(Color.appForeground.opacity(0.5))
                        .lineLimit(1)
                }
                if let body = notification.body, !body.isEmpty {
                    Text(body)
                        .font(.subheadline)
                        .foregroundStyle(Color.appForeground.opacity(0.7))
                        .lineLimit(3)
                }
            }
        }
        .padding(.vertical, 6)
        .overlay(alignment: .leading) {
            if !notification.isRead {
                Circle()
                    .fill(Color.appError)
                    .frame(width: 8, height: 8)
                    .offset(x: -14)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(Color.appForeground)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityValue(notification.isRead ? "" : "Unread")
    }

    /// The person behind it, or an icon for its category.
    @ViewBuilder
    private var leading: some View {
        if let actor = notification.actor {
            AvatarView(user: actor, size: 36)
        } else {
            Image(systemName: Self.symbol(for: notification.category))
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.1), in: .circle)
        }
    }

    static func symbol(for category: NotificationCategory) -> String {
        switch category {
        case .announcement: "megaphone"
        case .promotion: "tag"
        case .tripActivity: "person.2"
        case .travelAlert: "airplane"
        case .other: "bell"
        }
    }
}

/// The bell on the trips screen's bar, with a count of unread notifications.
struct NotificationBell: View {
    let unreadCount: Int

    var body: some View {
        Image(systemName: "bell")
            .overlay(alignment: .topTrailing) {
                if unreadCount > 0 {
                    Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Color.appError, in: .capsule)
                        .offset(x: 8, y: -6)
                }
            }
            .accessibilityLabel("Notifications")
            .accessibilityValue(unreadCount > 0 ? "\(unreadCount) unread" : "")
    }
}
