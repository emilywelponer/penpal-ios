import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
import UserNotifications
import UIKit

final class PushNotificationManager {
    static let shared = PushNotificationManager()

    private let db = Firestore.firestore()
    private var lastSavedToken: String?

    private init() {}

    func requestRemotePermissionAndRegister() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                print("NOTIFICATION_PERMISSION_STATUS", "error", error.localizedDescription)
            } else {
                print("NOTIFICATION_PERMISSION_STATUS", granted ? "authorized" : "denied")
            }

            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func refreshAndSaveToken() {
        Messaging.messaging().token { token, error in
            if let error {
                print("FCM_TOKEN_RECEIVED", "error", error.localizedDescription)
                return
            }
            self.saveFCMToken(token)
        }
    }

    func saveFCMToken(_ token: String?) {
        guard let token, !token.isEmpty else {
            print("FCM_TOKEN_RECEIVED", "nil")
            return
        }

        print("FCM_TOKEN_RECEIVED", token)

        guard let uid = Auth.auth().currentUser?.uid else {
            lastSavedToken = token
            print("FCM_TOKEN_SAVE_SKIPPED", "no auth user")
            return
        }

        let data: [String: Any] = [
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "platform": "ios",
            "languageRaw": UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.english.rawValue
        ]

        db.collection("users")
            .document(uid)
            .collection("fcmTokens")
            .document(token)
            .setData(data, merge: true) { error in
                if let error {
                    print("FCM_TOKEN_SAVE_ERROR", error.localizedDescription)
                    return
                }

                self.lastSavedToken = token
                print("FCM_TOKEN_SAVED", uid, token.prefix(12))
            }
    }

    func deleteCurrentTokenForLogout() {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let tokenToDelete = lastSavedToken
        let deleteToken: (String) -> Void = { token in
            self.db.collection("users")
                .document(uid)
                .collection("fcmTokens")
                .document(token)
                .delete { error in
                    if let error {
                        print("FCM_TOKEN_DELETE_ERROR", error.localizedDescription)
                    }
                }
        }

        if let tokenToDelete {
            deleteToken(tokenToDelete)
            return
        }

        Messaging.messaging().token { token, _ in
            if let token {
                deleteToken(token)
            }
        }
    }
}
