import Foundation
import AppKit
import UserNotifications

public final class NotificationService: @unchecked Sendable {
    public static let shared = NotificationService()

    private init() {}

    @MainActor
    public func requestPermission() async -> Bool {
        guard Bundle.main.bundlePath.hasSuffix(".app") || Bundle.main.bundleIdentifier != nil else {
            return false
        }
        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            return granted
        } catch {
            return false
        }
    }

    public func sendNotification(title: String, body: String, identifier: String? = nil) {
        guard Bundle.main.bundlePath.hasSuffix(".app") || Bundle.main.bundleIdentifier != nil else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let id = identifier ?? UUID().uuidString
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    public func updateBadgeCount(_ count: Int) {
        UserDefaults.standard.set(count, forKey: "realtodo_pending_count")
        guard Bundle.main.bundlePath.hasSuffix(".app") || Bundle.main.bundleIdentifier != nil else {
            return
        }
        DispatchQueue.main.async {
            NSApplication.shared.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
        }
    }

    public static var pendingCount: Int {
        UserDefaults.standard.integer(forKey: "realtodo_pending_count")
    }

    public func notifyMorningRoutine(count: Int) {
        sendNotification(
            title: "RealTodo",
            body: "오늘 추천 할일 \(count)개가 준비되었습니다. 확인해보세요."
        )
    }

    public func notifyPeriodicUpdate(count: Int) {
        sendNotification(
            title: "RealTodo",
            body: "새로운 제안 \(count)개가 있습니다."
        )
    }
}
