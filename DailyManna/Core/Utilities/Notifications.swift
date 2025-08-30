import Foundation
import UserNotifications
import SwiftUI

enum NotificationsManager {
    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
        }
    }
    static func scheduleDueNotification(taskId: UUID, title: String, dueAt: Date) async {
        let enabled = UserDefaults.standard.bool(forKey: "dueNotificationsEnabled")
        guard enabled else { return }
        await requestAuthorizationIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = "Task Due"
        content.body = title
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute,.second], from: dueAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: taskId.uuidString, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(req)
    }
    static func cancelDueNotification(taskId: UUID) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [taskId.uuidString])
    }
}


