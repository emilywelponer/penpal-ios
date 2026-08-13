import SwiftUI
import Combine
import FirebaseCore
import FirebaseMessaging
import UserNotifications

// MARK: Margin Notes Feature

struct MarginNoteNotificationRoute: Identifiable, Equatable {
    let magazineID: String
    let marginNoteID: String
    let pageIndex: Int?

    var id: String {
        "\(magazineID)_\(marginNoteID)_\(pageIndex ?? -1)"
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard
            let type = userInfo["type"] as? String,
            type == "margin_note_published",
            let magazineID = userInfo["magazineID"] as? String,
            let marginNoteID = userInfo["marginNoteID"] as? String,
            !magazineID.isEmpty,
            !marginNoteID.isEmpty
        else {
            return nil
        }

        self.magazineID = magazineID
        self.marginNoteID = marginNoteID

        if let rawPageIndex = userInfo["pageIndex"] as? String {
            self.pageIndex = Int(rawPageIndex)
        } else if let pageIndex = userInfo["pageIndex"] as? Int {
            self.pageIndex = pageIndex
        } else {
            self.pageIndex = nil
        }
    }
}

extension Notification.Name {
    static let marginNoteNotificationTapped = Notification.Name("PenPalMarginNoteNotificationTapped")
}

@MainActor
final class MarginNoteNotificationRouter: ObservableObject {
    static let shared = MarginNoteNotificationRouter()

    @Published var pendingRoute: MarginNoteNotificationRoute?

    private init() {}

    func handle(_ route: MarginNoteNotificationRoute) {
        pendingRoute = route
        NotificationCenter.default.post(
            name: .marginNoteNotificationTapped,
            object: nil,
            userInfo: ["route": route]
        )
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        guard !ProcessInfo.processInfo.isRunningXCTest else {
            return true
        }
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        let marginNoteCategory = UNNotificationCategory(
            identifier: "MARGIN_NOTE_PUBLISHED",
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([marginNoteCategory])
        PushNotificationManager.shared.requestRemotePermissionAndRegister()
        Task { @MainActor in
            StoreKitPurchaseService.shared.startTransactionListener()
            await StoreKitPurchaseService.shared.refreshCurrentEntitlements()
        }
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        guard !ProcessInfo.processInfo.isRunningXCTest else {
            return
        }
        Task { @MainActor in
            await StoreKitPurchaseService.shared.refreshCurrentEntitlements()
        }
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("FCM_TOKEN_RECEIVED", "apns registration failed", error.localizedDescription)
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        PushNotificationManager.shared.saveFCMToken(fcmToken)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let route = MarginNoteNotificationRoute(userInfo: userInfo) {
            Task { @MainActor in
                MarginNoteNotificationRouter.shared.handle(route)
            }
        }
        completionHandler()
    }
}

private extension ProcessInfo {
    var isRunningXCTest: Bool {
        environment["XCTestConfigurationFilePath"] != nil
            || arguments.contains { $0.contains("xctest") }
    }
}

@main
struct TravelingFriendsApp: App {
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
                .onOpenURL { url in
                    FirestoreManager.shared.handleGroupInviteURL(url)
                }
        }
    }
}
