import Foundation

// MARK: Notification Preferences

struct NotificationPreferences: Equatable {
    var masterEnabled: Bool = false
    var friendActivity: Bool = true
    var groupUpdates: Bool = true
    var newMagazines: Bool = true
    var magazineActivity: Bool = true
    var marginNotes: Bool = true
    var repliesAndReactions: Bool = true
    var penPalAnnouncements: Bool = true

    static var enabledDefaults: NotificationPreferences {
        var preferences = NotificationPreferences()
        preferences.masterEnabled = true
        return preferences
    }

    init(data: [String: Any] = [:]) {
        masterEnabled = data["notificationsMasterEnabled"] as? Bool ?? false
        friendActivity = data["notifyFriendActivity"] as? Bool ?? true
        groupUpdates = data["notifyGroupUpdates"] as? Bool ?? true
        newMagazines = data["notifyNewMagazines"] as? Bool ?? true
        magazineActivity = data["notifyMagazineActivity"] as? Bool ?? true
        marginNotes = data["marginNoteNotificationsEnabled"] as? Bool ?? true
        repliesAndReactions = data["notifyRepliesReactions"] as? Bool ?? true
        penPalAnnouncements = data["notifyPenPalAnnouncements"] as? Bool ?? true
    }

    var firestoreData: [String: Any] {
        [
            "notificationsMasterEnabled": masterEnabled,
            "notifyFriendActivity": friendActivity,
            "notifyGroupUpdates": groupUpdates,
            "notifyNewMagazines": newMagazines,
            "notifyMagazineActivity": magazineActivity,
            "marginNoteNotificationsEnabled": marginNotes,
            "notifyRepliesReactions": repliesAndReactions,
            "notifyPenPalAnnouncements": penPalAnnouncements
        ]
    }
}
