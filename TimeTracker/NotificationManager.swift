import Foundation
import UserNotifications

/// Schedules the daily check-in reminder and reports when the user taps it.
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    /// Set when the user opens the app from the reminder; the root view presents the check-in sheet.
    @Published var showCheckIn = false
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined

    private let requestID = "daily-checkin"

    override private init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    var isDenied: Bool { authorization == .denied }

    func refreshStatus() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        await MainActor.run { authorization = status }
    }

    /// Asks permission if needed. Returns true if notifications are allowed.
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        await refreshStatus()
        return granted
    }

    /// Makes the pending reminder match the settings: one repeating daily notification, or none.
    func sync(_ settings: CheckInSettings) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestID])
        await refreshStatus()
        guard settings.enabled else { return }

        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "How was your day?"
        content.body = "Take a moment to check in."
        content.sound = .default

        var when = DateComponents()
        when.hour = settings.hour
        when.minute = settings.minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: requestID, content: content, trigger: trigger))
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard response.notification.request.identifier == requestID else { return }
        await MainActor.run { showCheckIn = true }
    }
}
