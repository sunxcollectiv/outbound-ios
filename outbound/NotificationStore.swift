//
//  NotificationStore.swift
//  outbound
//

import Foundation
import Observation

/// Loads and holds the signed-in user's notification inbox and the unread badge.
///
/// Changes to read state and dismissals show at once and are sent in the
/// background; one that fails is rolled back.
@Observable
final class NotificationStore {
    private(set) var notifications: [AppNotification] = []
    private(set) var unreadCount = 0
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    var errorMessage: String?

    /// The cursor for the next (older) page, or nil when the whole inbox is loaded.
    private var nextCursor: String?
    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    var hasMore: Bool { nextCursor != nil }

    /// Fetches the newest page, replacing what's loaded, and refreshes the badge.
    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await api.send(NotificationsAPI.list(), as: NotificationsAPI.Page.self)
            let unread = try await api.send(NotificationsAPI.unreadCount, as: NotificationsAPI.UnreadCount.self)
            notifications = loaded.items
            nextCursor = loaded.nextCursor
            unreadCount = unread.count
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Fetches the next older page, if there is one and one isn't already coming.
    func loadMore() async {
        guard let cursor = nextCursor, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await api.send(NotificationsAPI.list(before: cursor), as: NotificationsAPI.Page.self)
            // A refresh may have landed meanwhile; skip anything already shown.
            let shown = Set(notifications.map(\.id))
            notifications += page.items.filter { !shown.contains($0.id) }
            nextCursor = page.nextCursor
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Refreshes just the badge, e.g. when the trips screen appears. Best-effort.
    func refreshUnreadCount() async {
        if let unread = try? await api.send(NotificationsAPI.unreadCount, as: NotificationsAPI.UnreadCount.self) {
            unreadCount = unread.count
        }
    }

    func setRead(_ notification: AppNotification, _ read: Bool) {
        guard let index = notifications.firstIndex(where: { $0.id == notification.id }),
              notifications[index].isRead != read else { return }
        let previous = notifications[index]
        notifications[index].readAt = read ? .now : nil
        unreadCount = max(0, unreadCount + (read ? -1 : 1))

        Task {
            do {
                let endpoint = read ? NotificationsAPI.markRead(id: previous.id) : NotificationsAPI.markUnread(id: previous.id)
                let updated = try await api.send(endpoint, as: AppNotification.self)
                replace(updated)
            } catch {
                replace(previous)
                unreadCount = max(0, unreadCount + (read ? 1 : -1))
                errorMessage = error.localizedDescription
            }
        }
    }

    func markAllRead() {
        let previous = notifications
        let previousCount = unreadCount
        for index in notifications.indices where !notifications[index].isRead {
            notifications[index].readAt = .now
        }
        unreadCount = 0

        Task {
            do {
                unreadCount = try await api.send(NotificationsAPI.markAllRead, as: NotificationsAPI.UnreadCount.self).count
            } catch {
                notifications = previous
                unreadCount = previousCount
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Removes a notification from the inbox. The server keeps it out of sight, so a
    /// dismissed announcement doesn't come back.
    func dismiss(_ notification: AppNotification) {
        guard let index = notifications.firstIndex(where: { $0.id == notification.id }) else { return }
        notifications.remove(at: index)
        if !notification.isRead {
            unreadCount = max(0, unreadCount - 1)
        }

        Task {
            do {
                try await api.send(NotificationsAPI.dismiss(id: notification.id))
            } catch {
                notifications.insert(notification, at: min(index, notifications.count))
                if !notification.isRead {
                    unreadCount += 1
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func replace(_ notification: AppNotification) {
        guard let index = notifications.firstIndex(where: { $0.id == notification.id }) else { return }
        notifications[index] = notification
    }
}
