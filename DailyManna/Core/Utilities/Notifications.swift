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
    static func scheduleDueNotification(taskId: UUID, title: String, dueAt: Date, bucketKey: String) async {
        let enabled = UserDefaults.standard.bool(forKey: "dueNotificationsEnabled")
        guard enabled else { return }
        await requestAuthorizationIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = "Task Due"
        content.body = title
        content.sound = .default
        content.userInfo = ["taskId": taskId.uuidString, "bucket_key": bucketKey]
        let comps = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute,.second], from: dueAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: taskId.uuidString, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(req)
    }
    static func cancelDueNotification(taskId: UUID) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [taskId.uuidString])
    }
}

// MARK: - App routing for notification tap
#if canImport(UIKit)
import UIKit
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()
    func register() {
        UNUserNotificationCenter.current().delegate = self
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        // Expect identifier to be the task ID
        let id = response.notification.request.identifier
        let bucket = response.notification.request.content.userInfo["bucket_key"] as? String
        if let uuid = UUID(uuidString: id) {
            DispatchQueue.main.async {
                var info: [String: Any] = ["taskId": uuid]
                if let bucket { info["bucket_key"] = bucket }
                NotificationCenter.default.post(name: Notification.Name("dm.open.task"), object: nil, userInfo: info)
            }
        }
    }
}
#elseif canImport(AppKit)
import AppKit
// macOS notification handling could be implemented here if needed
// For now, notifications work but don't route to specific tasks
#endif


