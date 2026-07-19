import Foundation
import Combine
import SwiftUI
import UIKit
import UserNotifications

enum NotificationPermissionStatus {
    case enabled
    case disabled
    case notDetermined

    init(settings: UNNotificationSettings) {
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            self = .enabled
        case .denied:
            self = .disabled
        case .notDetermined:
            self = .notDetermined
        @unknown default:
            self = .disabled
        }
    }

    var displayText: String {
        switch self {
        case .enabled:
            return "Enabled"
        case .disabled:
            return "Disabled"
        case .notDetermined:
            return "Not Determined"
        }
    }
}

@MainActor
final class NotificationPermissionManager: ObservableObject {
    static let shared = NotificationPermissionManager()

    @Published private(set) var status: NotificationPermissionStatus = .notDetermined

    private init() {}

    func refreshStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let updatedStatus = NotificationPermissionStatus(settings: settings)
            Task { @MainActor in
                self?.status = updatedStatus
            }
        }
    }

    func handleNotificationsRowTap() {
        switch status {
        case .notDetermined:
            requestPermission()
        case .enabled, .disabled:
            openSettings()
        }
    }

    func requestPermission(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                print("NOTIFICATION_PERMISSION_STATUS", "error", error.localizedDescription)
            } else {
                print("NOTIFICATION_PERMISSION_STATUS", granted ? "authorized" : "denied")
            }

            Task { @MainActor in
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                self.refreshStatus()
                completion?(granted)
            }
        }
    }

    func openSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsURL)
    }
}
