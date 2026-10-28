//
//  PushNotifications.swift
//  outbound
//

import Observation
import UIKit
import UserNotifications

/// `PushDeviceCreate` / `PushDeviceRead` for `/notifications/devices`.
///
///     POST   /notifications/devices  PushDeviceCreate -> PushDeviceRead
///     DELETE /notifications/devices/{id}              -> 204
enum PushDevicesAPI {
    struct RegisterRequest: Encodable {
        var platform = "ios"
        /// The APNs device token as lowercase hex.
        let token: String
        let appVersion: String?
        let locale: String?
        let timezone: String?
    }

    struct Device: Decodable {
        let id: String
    }

    static func register(_ body: RegisterRequest) -> Endpoint {
        Endpoint(path: "/notifications/devices", method: .post, body: body)
    }

    static func unregister(id: String) -> Endpoint {
        Endpoint(path: "/notifications/devices/\(id)", method: .delete)
    }
}

/// Asks for permission to notify, registers this device's APNs token with the
/// server, and routes pushes the user taps to the screen they're about.
///
/// A push carries the inbox entry it mirrors alongside `aps`:
///
///     { "aps": { "alert": { "title": "…", "body": "…" }, "badge": 3 },
///       "notification_id": "…", "trip_id": "…", "trip_item_id": "…" }
///
/// All three ids are optional.
@Observable
final class PushNotifications {
    static let shared = PushNotifications()

    /// The trip a tapped push is about, waiting for the trips screen to open it.
    var pendingTripId: String?
    /// Bumped whenever a push arrives, so the inbox and badge can refresh.
    private(set) var receivedCount = 0

    private let api: APIClient
    private let deviceIdKey = "push.deviceId"

    init(api: APIClient = .shared) {
        self.api = api
    }

    /// Asks for permission the first time, then registers with APNs. Call on every
    /// launch once signed in: the token can change, and the server wants to hear
    /// from each device regularly. Does nothing if the user said no.
    func registerIfAllowed() async {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Sends a token from APNs to the server and remembers the device id it gets,
    /// for `unregister`. Best-effort: the next launch tries again.
    func didRegister(token: Data) async {
        guard api.token != nil else { return }
        let body = PushDevicesAPI.RegisterRequest(
            token: token.map { String(format: "%02x", $0) }.joined(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            locale: Locale.current.identifier,
            timezone: TimeZone.current.identifier
        )
        if let device = try? await api.send(PushDevicesAPI.register(body), as: PushDevicesAPI.Device.self) {
            UserDefaults.standard.set(device.id, forKey: deviceIdKey)
        }
    }

    /// Stops pushes to this device for the signed-in account, e.g. on sign-out.
    /// `client` must still carry that account's token.
    func unregister(using client: APIClient) async {
        guard let id = UserDefaults.standard.string(forKey: deviceIdKey) else { return }
        UserDefaults.standard.removeObject(forKey: deviceIdKey)
        UIApplication.shared.unregisterForRemoteNotifications()
        try? await client.send(PushDevicesAPI.unregister(id: id))
        try? await UNUserNotificationCenter.current().setBadgeCount(0)
    }

    /// A push arrived while the app was open.
    func didReceive() {
        receivedCount += 1
    }

    /// The user tapped a push: mark its inbox entry read and open its trip.
    func didOpen(_ userInfo: [AnyHashable: Any]) {
        receivedCount += 1
        if let id = userInfo["notification_id"] as? String {
            Task { try? await api.send(NotificationsAPI.markRead(id: id)) }
        }
        if let tripId = userInfo["trip_id"] as? String {
            pendingTripId = tripId
        }
    }
}

/// Receives the APNs token and push callbacks, which only come through an app
/// delegate, and hands them to `PushNotifications`.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await PushNotifications.shared.didRegister(token: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Usually a build without the push entitlement, or no network. The next launch tries again.
        print("Push registration failed: \(error.localizedDescription)")
    }

    /// Shows pushes as banners even while the app is open.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        PushNotifications.shared.didReceive()
        return [.banner, .list, .sound, .badge]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        PushNotifications.shared.didOpen(response.notification.request.content.userInfo)
    }
}
