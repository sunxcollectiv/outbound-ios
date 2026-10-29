//
//  NotificationViewController.swift
//  NotificationContent
//

import SwiftUI
import UIKit
import UserNotifications
import UserNotificationsUI

/// The expanded view of a trip push (category `TRIP_ACTIVITY`): a very dark gray card
/// with a tag for what it's about, then the body. Mark as Read and Dismiss sit under it
/// as the category's actions, handled by the app.
final class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private var host: UIHostingController<NotificationCard>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = NotificationCard.background
    }

    func didReceive(_ notification: UNNotification) {
        let content = notification.request.content
        // The tag names the trip for now; fall back to the title, which the server
        // also sets to the trip's name.
        let tag = (content.userInfo["trip_title"] as? String) ?? content.title
        show(NotificationCard(tag: tag, title: content.subtitle, message: content.body))
    }

    private func show(_ card: NotificationCard) {
        if let host {
            host.rootView = card
        } else {
            let host = UIHostingController(rootView: card)
            host.view.backgroundColor = .clear
            host.sizingOptions = .preferredContentSize
            addChild(host)
            host.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(host.view)
            NSLayoutConstraint.activate([
                host.view.topAnchor.constraint(equalTo: view.topAnchor),
                host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
            host.didMove(toParent: self)
            self.host = host
        }
        // Grow or shrink the card to fit the text.
        let width = view.bounds.width > 0 ? view.bounds.width : (view.window?.windowScene?.screen.bounds.width ?? 375)
        let size = host?.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)) ?? .zero
        preferredContentSize = CGSize(width: width, height: size.height)
    }
}

/// The card's content: a tag naming what the update is about, an optional title line,
/// then the message.
struct NotificationCard: View {
    static let background = UIColor(white: 0.08, alpha: 1)

    let tag: String
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !tag.isEmpty {
                Text(tag)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.12), in: .capsule)
            }
            if !title.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: Self.background))
    }
}
