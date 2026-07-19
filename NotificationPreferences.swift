import Foundation

// MARK: Notification Preferences

struct NotificationPreferences: Equatable {
    var masterEnabled: Bool = false

    static var enabledDefaults: NotificationPreferences {
        var preferences = NotificationPreferences()
        preferences.masterEnabled = true
        return preferences
    }

    init(data: [String: Any] = [:]) {
        if let masterEnabled = data["notificationsMasterEnabled"] as? Bool {
            self.masterEnabled = masterEnabled
        } else if let marginNotesEnabled = data["marginNoteNotificationsEnabled"] as? Bool {
            self.masterEnabled = marginNotesEnabled
        } else {
            self.masterEnabled = false
        }
    }

    var firestoreData: [String: Any] {
        [
            "notificationsMasterEnabled": masterEnabled,
            "marginNoteNotificationsEnabled": masterEnabled
        ]
    }
}
