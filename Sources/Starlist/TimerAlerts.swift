import AppKit
import StarlistKit
import UserNotifications

/// Says when a focus session or a break has ended. The panel is usually
/// closed by then, so this is a notification, not something in the panel.
@MainActor
final class TimerAlerts: NSObject, UNUserNotificationCenterDelegate {
    /// Notifications need an app bundle. Run as a bare binary, there is none
    /// and asking for the notification center would crash.
    private let center: UNUserNotificationCenter? =
        Bundle.main.bundleIdentifier == nil ? nil : .current()

    override init() {
        super.init()
        center?.delegate = self
    }

    /// macOS asks the first time only; after that this changes nothing.
    func askPermission() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func announceEnd(of phase: FocusTimer.Phase) {
        let focus = Int(FocusTimer.focusLength / 60)
        let rest = Int(FocusTimer.breakLength / 60)
        let title: String
        let body: String
        switch phase {
        case .focus:
            title = "Time for a break"
            body = "\(focus) minutes of focus done. Your \(rest)-minute break has started."
        case .rest:
            title = "Break's over"
            body = "Start the timer when you're ready for the next \(focus) minutes."
        }

        guard let center else { return Self.chime() }
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                let center = UNUserNotificationCenter.current()
                // Only the latest change is worth keeping in Notification Center.
                center.removeAllDeliveredNotifications()
                center.add(UNNotificationRequest(
                    identifier: UUID().uuidString, content: content, trigger: nil
                ))
            default:
                // Notifications are turned off for Starlist. Still make a sound.
                Task { @MainActor in Self.chime() }
            }
        }
    }

    private static func chime() {
        NSSound(named: "Glass")?.play()
    }

    /// Show the notification even when Starlist happens to be the active app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
