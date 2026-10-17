import Foundation
import UserNotifications

/// Local reminders: 30 minutes before and at the due time.
enum Notifier {
    private static let offsets: [TimeInterval] = [-30 * 60, 0]

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func schedule(_ item: TodoItem) {
        cancel(item.id)
        guard item.remind, !item.done, let due = item.due else { return }
        let center = UNUserNotificationCenter.current()
        for (index, offset) in offsets.enumerated() {
            let fire = due.addingTimeInterval(offset)
            guard fire > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = offset == 0 ? "Due now" : "Due in 30 minutes · \(DueText.timeString(due))"
            content.sound = .default
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            center.add(UNNotificationRequest(identifier: "\(item.id)-\(index)", content: content, trigger: trigger))
        }
    }

    static func cancel(_ id: String) {
        let ids = offsets.indices.map { "\(id)-\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}
