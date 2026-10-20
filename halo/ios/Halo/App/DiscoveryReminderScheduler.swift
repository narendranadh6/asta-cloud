import Foundation
import UserNotifications

/// Optional weekly local reminder to explore new music. No push notifications, no
/// remote tokens, nothing leaves the device.
@MainActor
final class DiscoveryReminderScheduler {
    private let identifier = "halo.weekly-discovery"

    func enable() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return false }
        let content = UNMutableNotificationContent()
        content.title = "Time to discover"
        content.body = "Ask the AI DJ for something new this week."
        var components = DateComponents()
        components.weekday = 7  // Saturday
        components.hour = 11
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    func cancelAll() async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
