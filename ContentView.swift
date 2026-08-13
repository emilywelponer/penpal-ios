import SwiftUI
import Combine
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import PhotosUI
import UIKit
import UserNotifications

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "English"
    case german = "Deutsch"
    case italian = "Italiano"
    case spanish = "Español"
    case french = "Français"
    
    var id: String { rawValue }
}

struct PenpalProfile: Identifiable, Hashable {
    var id: String
    var username: String
    var displayName: String
    var profileImageData: String?
    var bannerColorHex: String?
    var patternColorHex: String?
    var profilePattern: String?
    var nameFont: String?
    var nameColorHex: String?
    var founderSupporter: Bool = false
    var founderSupporterTier: String?
    var hasArchiveRetentionNotice: Bool = false
}

struct SavedMagazineIssue: Identifiable {
    let id = UUID()
    var title: String
    var date: Date
    var pages: [MagazinePage]
}

final class MagazineArchiveStore: ObservableObject {
    static let shared = MagazineArchiveStore()
    @Published var savedIssues: [SavedMagazineIssue] = []
    private init() {}
}

final class FriendsNewsStore: ObservableObject {
    static let shared = FriendsNewsStore()

    @Published private(set) var incomingRequestCount = 0
    @Published private(set) var acceptedFriendCount = 0

    private var incomingListener: ListenerRegistration?
    private var userListener: ListenerRegistration?
    private var currentFriendCount = 0
    private let lastSeenFriendCountKey = "friendsNewsLastSeenFriendCount"

    var unreadCount: Int {
        incomingRequestCount + acceptedFriendCount
    }

    private init() {}

    func start() {
        guard let uid = Auth.auth().currentUser?.uid else {
            clear()
            return
        }

        if incomingListener == nil {
            incomingListener = FirestoreManager.shared.listenToMyFriendRequests { [weak self] requests in
                DispatchQueue.main.async {
                    self?.incomingRequestCount = requests.count
                }
            }
        }

        if userListener == nil {
            userListener = Firestore.firestore()
                .collection("users")
                .document(uid)
                .addSnapshotListener { [weak self] snapshot, error in
                    if let error {
                        print("FRIENDS_NEWS_USER_LISTENER_ERROR", error.localizedDescription)
                        return
                    }

                    let friends = snapshot?.data()?["friends"] as? [String] ?? []
                    DispatchQueue.main.async {
                        self?.updateFriendCount(friends.count)
                    }
                }
        }
    }

    func markOpened() {
        UserDefaults.standard.set(currentFriendCount, forKey: lastSeenFriendCountKey)
        acceptedFriendCount = 0
    }

    func clear() {
        FirestoreManager.shared.removeListener(incomingListener, reason: "FriendsNewsStore.clear incoming")
        FirestoreManager.shared.removeListener(userListener, reason: "FriendsNewsStore.clear user")
        incomingListener = nil
        userListener = nil
        incomingRequestCount = 0
        acceptedFriendCount = 0
        currentFriendCount = 0
    }

    private func updateFriendCount(_ count: Int) {
        currentFriendCount = count
        let hasBaseline = UserDefaults.standard.object(forKey: lastSeenFriendCountKey) != nil
        guard hasBaseline else {
            UserDefaults.standard.set(count, forKey: lastSeenFriendCountKey)
            acceptedFriendCount = 0
            return
        }

        let lastSeen = UserDefaults.standard.integer(forKey: lastSeenFriendCountKey)
        acceptedFriendCount = max(0, count - lastSeen)
    }
}

final class PenpalGroupStore: ObservableObject {
    static let shared = PenpalGroupStore()
    @Published var groups: [GroupModel] = []
    private var groupListener: ListenerRegistration?
    
    private init() {}
    
    func loadGroups() {
        guard Auth.auth().currentUser?.uid != nil else {
            print("LISTENER_BLOCKED_NO_AUTH", "PenpalGroupStore.loadGroups")
            clear()
            return
        }

        guard groupListener == nil else { return }

        FirestoreManager.shared.removeListener(groupListener)
        groupListener = FirestoreManager.shared.listenToGroups { groups in
            DispatchQueue.main.async {
                self.groups = groups
            }
        }

        if groupListener == nil {
            groups.removeAll()
        }
    }

    func clear() {
        FirestoreManager.shared.removeListener(groupListener, reason: "PenpalGroupStore.clear")
        groupListener = nil
        groups.removeAll()
    }
}

enum GroupPublishingReminderScheduler {
    static func schedule(
        group: GroupModel,
        languageRaw: String,
        completion: ((String?) -> Void)? = nil
    ) {
        clear(groupID: group.id)
        guard group.reminderEnabled else {
            completion?(nil)
            return
        }
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            print("NOTIFICATION_PERMISSION_STATUS", granted ? "authorized" : "denied")
            guard granted else {
                completion?(localizedPermissionMessage(languageRaw))
                return
            }

            let content = UNMutableNotificationContent()
            content.title = localizedTitle(languageRaw)
            content.body = localizedBody(languageRaw)
            content.sound = .default

            let requests = nextReminderRequests(for: group, content: content)
            let center = UNUserNotificationCenter.current()
            let groupID = group.id

            for request in requests {
                center.add(request) { error in
                    if let error {
                        completion?(error.localizedDescription)
                    }
                }
            }

            if let firstRequest = requests.first,
               let trigger = firstRequest.trigger as? UNCalendarNotificationTrigger {
                print("LOCAL_REMINDER_SCHEDULED", groupID, trigger.dateComponents.day ?? 0, trigger.dateComponents.hour ?? 0, trigger.dateComponents.minute ?? 0)
            }

            completion?(nil)
        }
    }
    
    static func clear(groupID: String) {
        let legacyIdentifiers = (0..<6).flatMap { monthOffset in
            [-7, -2, 0, 1].map { "groupDue-\(groupID)-\(monthOffset)-\($0)" }
        }
        let rollingIdentifiers = (0..<18).map { "publishingReminder-\(groupID)-\($0)" }
        let identifiers = ["publishingReminder-\(groupID)"] + rollingIdentifiers + legacyIdentifiers
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private static func nextReminderRequests(
        for group: GroupModel,
        content: UNMutableNotificationContent
    ) -> [UNNotificationRequest] {
        let calendar = Calendar.current
        let now = Date()
        let desiredDay = min(max(group.reminderDay, 1), 31)
        let hour = min(max(group.reminderHour, 0), 23)
        let minute = min(max(group.reminderMinute, 0), 59)

        return (0..<18).compactMap { offset in
            guard let monthDate = calendar.date(byAdding: .month, value: offset, to: now) else { return nil }
            let components = calendar.dateComponents([.year, .month], from: monthDate)
            guard let year = components.year, let month = components.month else { return nil }
            let validDay = min(desiredDay, daysInMonth(month: month, year: year, calendar: calendar))
            var triggerComponents = DateComponents()
            triggerComponents.year = year
            triggerComponents.month = month
            triggerComponents.day = validDay
            triggerComponents.hour = hour
            triggerComponents.minute = minute

            guard let triggerDate = calendar.date(from: triggerComponents), triggerDate > now else { return nil }

            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
            return UNNotificationRequest(
                identifier: "publishingReminder-\(group.id)-\(offset)",
                content: content,
                trigger: trigger
            )
        }
    }

    private static func daysInMonth(month: Int, year: Int, calendar: Calendar) -> Int {
        var components = DateComponents()
        components.year = year
        components.month = month
        guard let date = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: date) else {
            return 28
        }
        return range.count
    }
    
    private static func localizedTitle(_ languageRaw: String) -> String {
        switch AppLanguage(rawValue: languageRaw) ?? .english {
        case .english: return "Time to publish your PenPal issue"
        case .german: return "Zeit, deine PenPal-Ausgabe zu veröffentlichen"
        case .italian: return "È il momento di pubblicare il tuo magazine PenPal"
        case .spanish: return "Hora de publicar tu revista PenPal"
        case .french: return "C’est le moment de publier ton magazine PenPal"
        }
    }
    
    private static func localizedBody(_ languageRaw: String) -> String {
        switch AppLanguage(rawValue: languageRaw) ?? .english {
        case .english: return "Your group’s monthly issue is due today."
        case .german: return "Die monatliche Ausgabe deiner Gruppe ist heute fällig."
        case .italian: return "Il magazine mensile del tuo gruppo è atteso oggi."
        case .spanish: return "La revista mensual de tu grupo vence hoy."
        case .french: return "Le magazine mensuel de ton groupe est attendu aujourd’hui."
        }
    }
    
    private static func localizedPermissionMessage(_ languageRaw: String) -> String {
        switch AppLanguage(rawValue: languageRaw) ?? .english {
        case .english: return "Notifications are off. You can enable them in iPhone Settings."
        case .german: return "Mitteilungen sind deaktiviert. Du kannst sie in den iPhone-Einstellungen aktivieren."
        case .italian: return "Le notifiche sono disattivate. Puoi attivarle nelle Impostazioni dell’iPhone."
        case .spanish: return "Las notificaciones están desactivadas. Puedes activarlas en Ajustes del iPhone."
        case .french: return "Les notifications sont désactivées. Tu peux les activer dans les réglages de l’iPhone."
        }
    }
}

// MARK: - Modern App Style

enum PenPalStyle {
    static let background = Color(hex: "#FAF7F1")
    static let card = Color(hex: "#FFFDF8")
    static let cardAlt = Color(hex: "#F4EFE7")
    static let ink = Color(hex: "#171717")
    static let muted = Color(hex: "#7A746B")
    static let border = Color(hex: "#E6E0D6")
    static let accent = Color(hex: "#2F4156")
    
    static let corner: CGFloat = 26
}

extension Color {
    init(hex: String) {
        let clean = hex.replacingOccurrences(of: "#", with: "")
        let scanner = Scanner(string: clean)
        var value: UInt64 = 0
        scanner.scanHexInt64(&value)
        
        let r = Double((value >> 16) & 0xff) / 255
        let g = Double((value >> 8) & 0xff) / 255
        let b = Double(value & 0xff) / 255
        
        self.init(red: r, green: g, blue: b)
    }
}

func colorFromHex(_ hex: String?) -> Color {
    guard let hex else { return PenPalStyle.card }
    return Color(hex: hex)
}

func hexFromColor(_ color: Color) -> String {
    let uiColor = UIColor(color)
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    
    uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
    
    return String(
        format: "#%02X%02X%02X",
        Int(r * 255),
        Int(g * 255),
        Int(b * 255)
    )
}

func nameFont(_ fontName: String?) -> Font {
    .system(size: 28, weight: .semibold, design: .serif)
}

func localizedMonths(for language: AppLanguage) -> [String] {
    switch language {
    case .english:
        return ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
    case .german:
        return ["JAN", "FEB", "MÄR", "APR", "MAI", "JUN", "JUL", "AUG", "SEP", "OKT", "NOV", "DEZ"]
    case .italian:
        return ["GEN", "FEB", "MAR", "APR", "MAG", "GIU", "LUG", "AGO", "SET", "OTT", "NOV", "DIC"]
    case .spanish:
        return ["ENE", "FEB", "MAR", "ABR", "MAY", "JUN", "JUL", "AGO", "SEP", "OCT", "NOV", "DIC"]
    case .french:
        return ["JAN", "FÉV", "MAR", "AVR", "MAI", "JUN", "JUL", "AOÛ", "SEP", "OCT", "NOV", "DÉC"]
    }
}

func fullMonthName(for month: Int) -> String {
    guard (1...12).contains(month) else { return "" }
    return Calendar.current.monthSymbols[month - 1]
}

func fullDisplayDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .long
    formatter.timeStyle = .none
    return formatter.string(from: date)
}

func logAuthDiagnostics(_ context: String) {
    let app = FirebaseApp.app()
    let options = app?.options
    let authUser = Auth.auth().currentUser
    let storedUserID = UserDefaults.standard.string(forKey: "currentUserID") ?? ""
    let localIsLoggedIn = UserDefaults.standard.bool(forKey: "isLoggedIn")

    print("AUTH_DIAGNOSTIC_START", context)
    print("AUTH_DIAGNOSTIC firebaseAppName", app?.name ?? "nil")
    print("AUTH_DIAGNOSTIC firebaseProjectID", options?.projectID ?? "nil")
    print("AUTH_DIAGNOSTIC authUID", authUser?.uid ?? "nil")
    print("AUTH_DIAGNOSTIC authEmail", authUser?.email ?? "nil")
    print("AUTH_DIAGNOSTIC localCurrentUserID", storedUserID.isEmpty ? "nil" : storedUserID)
    print("AUTH_DIAGNOSTIC localIsLoggedIn", localIsLoggedIn)

    if let authUID = authUser?.uid, !storedUserID.isEmpty, authUID != storedUserID {
        print("AUTH_DIAGNOSTIC_MISMATCH authUID localCurrentUserID", authUID, storedUserID)
    }

    if authUser == nil, localIsLoggedIn {
        print("AUTH_DIAGNOSTIC_MISMATCH local isLoggedIn true but Auth.currentUser nil")
    }

    guard let uid = authUser?.uid else {
        print("AUTH_DIAGNOSTIC userProfileUID nil no auth user")
        print("AUTH_DIAGNOSTIC_END", context)
        return
    }

    Firestore.firestore().collection("users").document(uid).getDocument { document, error in
        if let error {
            print("AUTH_DIAGNOSTIC_PROFILE_ERROR", error.localizedDescription)
            print("AUTH_DIAGNOSTIC_END", context)
            return
        }

        let data = document?.data()
        let profileUID = data?["id"] as? String ?? document?.documentID ?? "nil"
        print("AUTH_DIAGNOSTIC userProfileUID", profileUID)
        print("AUTH_DIAGNOSTIC userProfileExists", document?.exists == true)

        if profileUID != uid {
            print("AUTH_DIAGNOSTIC_MISMATCH authUID profileUID", uid, profileUID)
        }

        print("AUTH_DIAGNOSTIC_END", context)
    }
}

@MainActor
func prepareForPublishedSnapshotExport() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

@MainActor
func thumbnailSnapshotMagazinePage(_ page: MagazinePage) -> String? {
    guard Auth.auth().currentUser?.uid != nil else {
        print("BLOCKED_QUERY_NO_AUTH", "thumbnailSnapshotMagazinePage")
        return nil
    }

    let renderer = ImageRenderer(
        content: SinglePageCanvas(page: .constant(page), editable: false)
            .frame(width: 340, height: 500)
    )
    renderer.scale = 2

    guard let image = renderer.uiImage else {
        return nil
    }

    guard let encoded = compressedBase64Image(from: image, maxSize: 1200, quality: 0.82) else {
        return nil
    }

    return encoded
}

@MainActor
func publishedSnapshotMagazinePage(_ page: MagazinePage) -> String? {
    guard Auth.auth().currentUser?.uid != nil else {
        print("BLOCKED_QUERY_NO_AUTH", "publishedSnapshotMagazinePage")
        return nil
    }

    let renderer = ImageRenderer(
        content: SinglePageCanvas(page: .constant(page), editable: false)
            .frame(width: 1700, height: 2500)
    )
    renderer.scale = 1

    guard let image = renderer.uiImage else {
        return nil
    }

    guard let data = image.jpegData(compressionQuality: 0.92) else {
        return nil
    }

    return data.base64EncodedString()
}

// MARK: - Profile UI

// MARK: - Profile UI

private final class Base64UIImageCache {
    static let shared = NSCache<NSString, UIImage>()
}

struct Base64CachedImageView<Content: View, Placeholder: View>: View {
    let imageData: String?
    let debugID: String
    let content: (UIImage) -> Content
    let placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var loadedKey: String?

    var body: some View {
        Group {
            if let image {
                content(image)
            } else {
                placeholder()
            }
        }
        .task(id: cacheKey) {
            await loadImageIfNeeded()
        }
    }

    private var cacheKey: String {
        guard let imageData, !imageData.isEmpty else { return "empty" }
        return "\(debugID)-\(imageData.count)-\(imageData.hashValue)"
    }

    private func loadImageIfNeeded() async {
        guard let imageData, !imageData.isEmpty else {
            image = nil
            loadedKey = nil
            return
        }

        let key = cacheKey
        if loadedKey == key, image != nil {
            return
        }

        if let cached = Base64UIImageCache.shared.object(forKey: key as NSString) {
            image = cached
            loadedKey = key
            return
        }

        guard Auth.auth().currentUser?.uid != nil else {
            print("BLOCKED_QUERY_NO_AUTH", "Base64CachedImageView", debugID)
            image = nil
            loadedKey = nil
            return
        }

        let decoded = await Task.detached(priority: .utility) { () -> UIImage? in
            guard let data = Data(base64Encoded: imageData) else {
                return nil
            }

            return UIImage(data: data)
        }.value

        guard Auth.auth().currentUser?.uid != nil else {
            print("BLOCKED_QUERY_NO_AUTH", "Base64CachedImageView assign", debugID)
            image = nil
            loadedKey = nil
            return
        }

        if let decoded {
            Base64UIImageCache.shared.setObject(decoded, forKey: key as NSString)
        }

        image = decoded
        loadedKey = key
    }
}

struct ProfileBannerView: View {
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    let name: String
    let username: String
    let imageData: String?
    let bannerColorHex: String?
    let patternColorHex: String?
    let pattern: String?
    let nameFontName: String?
    let nameColorHex: String?
    let showHint: Bool
    
    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(PenPalStyle.cardAlt)
                    .frame(width: 82, height: 82)
                
                Base64CachedImageView(
                    imageData: imageData,
                    debugID: "profile-banner-\(username)"
                ) { image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 76, height: 76)
                        .clipShape(Circle())
                } placeholder: {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 68, height: 68)
                        .foregroundStyle(PenPalStyle.muted.opacity(0.6))
                }
            }
            
            VStack(alignment: .leading, spacing: 5) {
                Text(name.isEmpty ? appText("PenPal user", languageRaw) : name)
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .foregroundStyle(PenPalStyle.ink)
                
                if !username.isEmpty {
                    Text("@\(username)")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(PenPalStyle.muted)
                }
                
                if showHint {
                    Text(appText("Edit profile", languageRaw))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(PenPalStyle.accent)
                        .padding(.top, 3)
                }
            }
            
            Spacer()
            
            if showHint {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PenPalStyle.muted)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PenPalStyle.corner)
                .fill(PenPalStyle.card)
                .overlay(
                    RoundedRectangle(cornerRadius: PenPalStyle.corner)
                        .stroke(PenPalStyle.border, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.04), radius: 12, x: 0, y: 6)
        )
    }
}

struct UserMiniBannerCard: View {
    let profile: PenpalProfile
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(PenPalStyle.cardAlt)
                    .frame(width: 54, height: 54)
                
                Base64CachedImageView(
                    imageData: profile.profileImageData,
                    debugID: "user-mini-\(profile.id)"
                ) { image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                } placeholder: {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                        .foregroundStyle(PenPalStyle.muted.opacity(0.7))
                }
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.displayName)
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(PenPalStyle.ink)
                
                Text("@\(profile.username)")
                    .font(.caption)
                    .foregroundStyle(PenPalStyle.muted)
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(PenPalStyle.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(PenPalStyle.border, lineWidth: 1)
                )
        )
    }
}

// MARK: - Vintage Magazine Rack

// MARK: - Modern Magazine Archive Card

struct MagazineHolderCard: View {
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    
    let month: String
    let style: Int
    let issueCount: Int
    let unreadCount: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(month)
                    .font(.system(size: 30, weight: .semibold, design: .serif))
                    .foregroundStyle(PenPalStyle.ink)
                
                Spacer()
                
                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.85))
                        .clipShape(Capsule())
                }
            }
            
            VStack(alignment: .leading, spacing: 7) {
                Rectangle()
                    .fill(PenPalStyle.border)
                    .frame(height: 1)
                
                Text(localizedIssueCount(issueCount, languageRaw: languageRaw))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PenPalStyle.muted)
                
                Text(appText("PenPal archive", languageRaw))
                    .font(.caption2)
                    .foregroundStyle(PenPalStyle.muted.opacity(0.8))
            }
            
            Spacer()
        }
        .padding(18)
        .frame(height: 150)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(PenPalStyle.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(PenPalStyle.border, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.035), radius: 10, x: 0, y: 5)
        )
    }
}

// MARK: - Root

struct ContentView: View {
    @AppStorage("homeResetID") private var homeResetID: String = UUID().uuidString
    @AppStorage("currentUserID") private var currentUserID: String = ""
    @State private var firebaseUser: User?
    @State private var authHandle: AuthStateDidChangeListenerHandle?
    
    var body: some View {
        Group {
            if firebaseUser != nil {
                HomeDashboardView()
                    .id(homeResetID)
            } else {
                LoginView()
            }
        }
        .onAppear {
            logAuthDiagnostics("app launch")
            let currentUser = Auth.auth().currentUser
            if currentUser == nil {
                forceLocalLogout(reason: "app appear no auth user")
            } else {
                FirestoreManager.shared.authStateChanged(user: nil)
                firebaseUser = nil
                validateAuthSession(currentUser)
            }
            guard authHandle == nil else { return }
            authHandle = Auth.auth().addStateDidChangeListener { _, user in
                print("AUTH_STATE_CHANGED", user?.uid ?? "nil")
                logAuthDiagnostics("auth state changed")
                if user == nil {
                    print("AUTH_STATE_CHANGED_RECENT_ACTION", AuthEventTracker.recentActionSummary())
                    forceLocalLogout(reason: "Firebase auth state nil")
                } else {
                    FirestoreManager.shared.authStateChanged(user: nil)
                    firebaseUser = nil
                    validateAuthSession(user)
                }
            }
        }
        .onDisappear {
            if let authHandle {
                Auth.auth().removeStateDidChangeListener(authHandle)
                self.authHandle = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .authForceLogout)) { notification in
            let reason = notification.userInfo?["reason"] as? String ?? "unknown"
            forceLocalLogout(reason: reason)
        }
    }

    private func forceLocalLogout(reason: String) {
        AuthEventTracker.record("AUTH_FORCE_LOGOUT \(reason)")
        print("AUTH_FORCE_LOGOUT", reason)
        PushNotificationManager.shared.deleteCurrentTokenForLogout()
        StoreKitPurchaseService.shared.resetForLogout()
        currentUserID = ""
        UserDefaults.standard.set(false, forKey: "isLoggedIn")
        UserDefaults.standard.removeObject(forKey: "currentUserID")
        FirestoreManager.shared.removeAllListeners(reason: reason)
        PenpalGroupStore.shared.clear()
        FriendsNewsStore.shared.clear()
        FriendsStore.shared.friends.removeAll()
        MagazineArchiveStore.shared.savedIssues.removeAll()
        IssueDraftStore.shared.pages.removeAll()
        firebaseUser = nil
        homeResetID = UUID().uuidString
    }

    private func validateAuthSession(_ user: User?) {
        logAuthDiagnostics("validate auth session start")
        guard let user else {
            forceLocalLogout(reason: "validate auth missing user")
            return
        }

        AuthEventTracker.logTokenResult(context: "validate auth session") { outcome in
            DispatchQueue.main.async {
                if case .invalidUser = outcome {
                    FirestoreManager.shared.forceLogout(reason: "token refresh failed")
                    return
                }

                guard Auth.auth().currentUser?.uid == user.uid else {
                    FirestoreManager.shared.forceLogout(reason: "token refresh returned stale user")
                    return
                }

                currentUserID = user.uid
                UserDefaults.standard.set(true, forKey: "isLoggedIn")
                FirestoreManager.shared.authStateChanged(user: user)
                firebaseUser = user
                PushNotificationManager.shared.refreshAndSaveToken()
                PenpalGroupStore.shared.loadGroups()
                if case .transientFailure = outcome {
                    print("TOKEN_REFRESH_TRANSIENT_FAILURE keeping authenticated session", user.uid)
                }
                logAuthDiagnostics("validate auth session success")
            }
        }
    }
}

// MARK: - Login

struct LoginView: View {
    @AppStorage("username") private var savedUsername: String = ""
    @AppStorage("displayName") private var savedDisplayName: String = ""
    @AppStorage("email") private var savedEmail: String = ""
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue

    @State private var isLoginMode = true
    @State private var username = ""
    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage = ""
    @State private var showPassword = false
    @State private var showConfirmPassword = false
    @State private var isLoading = false

    @State private var showForgotPassword = false
    @State private var resetEmail = ""
    @State private var resetMessage = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 60)

                Text("PenPal")
                    .font(.system(size: 48, weight: .light, design: .serif))

                Picker("", selection: $isLoginMode) {
                    Text(appText("Sign up", languageRaw)).tag(false)
                    Text(appText("Log in", languageRaw)).tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                VStack(spacing: 14) {
                    if !isLoginMode {
                        TextField(appText("Display name", languageRaw), text: $displayName)
                            .padding()
                            .background(Color.gray.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 14))

                        TextField(appText("Username", languageRaw), text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding()
                            .background(Color.gray.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    TextField(appText("Email", languageRaw), text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Color.gray.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                    PasswordInputField(title: appText("Password", languageRaw), text: $password, isVisible: $showPassword)

                    if isLoginMode {
                        Button {
                            resetEmail = email
                            resetMessage = ""
                            showForgotPassword = true
                        } label: {
                            Text(appText("Forgot password?", languageRaw))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }

                    if !isLoginMode {
                        PasswordInputField(title: appText("Confirm password", languageRaw), text: $confirmPassword, isVisible: $showConfirmPassword)
                    }
                }
                .padding(.horizontal)

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                Button {
                    isLoginMode ? logIn() : signUp()
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        }

                        Text(appText(isLoginMode ? "Log in" : "Create Profile", languageRaw))
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isLoading)
                .padding(.horizontal)
            }
        }
        .sheet(isPresented: $showForgotPassword) {
            VStack(spacing: 20) {
                Text(appText("Reset password", languageRaw))
                    .font(.title2.bold())

                Text(appText("Enter your email and we’ll send you a link to set a new password.", languageRaw))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                TextField(appText("Email", languageRaw), text: $resetEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding()
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                if !resetMessage.isEmpty {
                    Text(resetMessage)
                        .font(.caption)
                        .foregroundColor(resetMessage.contains("sent") ? Color.secondary : Color.red)
                }

                Button {
                    sendPasswordReset()
                } label: {
                    Text(appText("Send reset email", languageRaw))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Spacer()
            }
            .padding()
        }
    }

    private func signUp() {
        let cleanUsername = clean(username)
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !cleanUsername.isEmpty else {
            errorMessage = appText("Please enter a username.", languageRaw)
            return
        }

        guard password == confirmPassword else {
            errorMessage = appText("Passwords do not match.", languageRaw)
            return
        }

        guard cleanUsername.count >= 3 else {
            errorMessage = appText("Username must be at least 3 characters.", languageRaw)
            return
        }

        guard cleanUsername.count <= 20 else {
            errorMessage = appText("Username too long.", languageRaw)
            return
        }

        isLoading = true
        errorMessage = ""

        FirestoreManager.shared.usernameExists(username: cleanUsername) { exists in
            if exists {
                isLoading = false
                errorMessage = appText("This username is already taken.", languageRaw)
                return
            }

            Auth.auth().createUser(withEmail: cleanEmail, password: password) { result, error in
                isLoading = false

                if let error = error {
                    errorMessage = error.localizedDescription
                    return
                }

                guard let user = result?.user else { return }

                savedUsername = cleanUsername
                savedDisplayName = displayName.isEmpty ? cleanUsername.capitalized : displayName
                savedEmail = cleanEmail

                let changeRequest = user.createProfileChangeRequest()
                changeRequest.displayName = savedDisplayName
                changeRequest.commitChanges()

                FirestoreManager.shared.createUserProfile(
                    uid: user.uid,
                    username: cleanUsername,
                    displayName: savedDisplayName,
                    email: cleanEmail
                )
                AuthEventTracker.record("LOGIN_SUCCESS signup \(user.uid)")
                PushNotificationManager.shared.refreshAndSaveToken()
                logAuthDiagnostics("signup success")
            }
        }
    }

    private func logIn() {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        isLoading = true
        errorMessage = ""

        Auth.auth().signIn(withEmail: cleanEmail, password: password) { _, error in
            isLoading = false

            if let error = error {
                errorMessage = error.localizedDescription
                return
            }

            if let user = Auth.auth().currentUser {
                savedDisplayName = user.displayName ?? ""
                savedEmail = user.email ?? cleanEmail
                AuthEventTracker.record("LOGIN_SUCCESS \(user.uid)")
                PushNotificationManager.shared.refreshAndSaveToken()
                logAuthDiagnostics("login success")
            }
        }
    }

    private func sendPasswordReset() {
        let cleanEmail = resetEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !cleanEmail.isEmpty else {
            resetMessage = appText("Please enter your email.", languageRaw)
            return
        }

        Auth.auth().sendPasswordReset(withEmail: cleanEmail) { error in
            if let error = error {
                resetMessage = error.localizedDescription
            } else {
                resetMessage = appText("Password reset email sent.", languageRaw)
            }
        }
    }

    private func clean(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "@", with: "")
    }
}

struct PasswordInputField: View {
    let title: String
    @Binding var text: String
    @Binding var isVisible: Bool
    
    var body: some View {
        HStack {
            if isVisible {
                TextField(title, text: $text)
            } else {
                SecureField(title, text: $text)
            }
            
            Button {
                isVisible.toggle()
            } label: {
                Image(systemName: isVisible ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Home

struct HomeDashboardView: View {
    @StateObject private var archiveStore = MagazineArchiveStore.shared
    @StateObject private var groupStore = PenpalGroupStore.shared
    @StateObject private var friendsNewsStore = FriendsNewsStore.shared
    @StateObject private var marginNoteNotificationRouter = MarginNoteNotificationRouter.shared
    @StateObject private var entitlementRepository = BackendEntitlementRepository.shared
    @State private var groupIssueListeners: [String: ListenerRegistration] = [:]
    @State private var groupUnreadCounts: [String: Int] = [:]
    @State private var notificationIssue: PublishedIssueModel?
    @State private var pendingMarginNoteRoute: MarginNoteNotificationRoute?
    @State private var showArchiveRetentionNotice = false

    
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    @AppStorage("profileImageData") private var profileImageData: String = ""
    @AppStorage("bannerColorHex") private var bannerColorHex: String = "#F6D3DC"
    @AppStorage("patternColorHex") private var patternColorHex: String = "#000000"
    @AppStorage("profilePattern") private var profilePattern: String = "plain"
    @AppStorage("nameFont") private var nameFontValue: String = "serif"
    @AppStorage("nameColorHex") private var nameColorHex: String = "#000000"
    @AppStorage("displayName") private var displayName: String = ""
    @AppStorage("username") private var username: String = ""
    
    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .english
    }
    

    
    private func loadCurrentUserFromFirebase() {
        FirestoreManager.shared.fetchCurrentUserProfile { profile in
            guard let profile else { return }

            DispatchQueue.main.async {
                displayName = profile.displayName
                username = profile.username
                profileImageData = profile.profileImageData ?? ""
                bannerColorHex = profile.bannerColorHex ?? "#F6D3DC"
                patternColorHex = profile.patternColorHex ?? "#000000"
                profilePattern = profile.profilePattern ?? "plain"
                nameFontValue = profile.nameFont ?? "serif"
                nameColorHex = profile.nameColorHex ?? "#000000"
                showArchiveRetentionNotice = profile.hasArchiveRetentionNotice
            }
        }
    }
    
    
    private let sidePadding: CGFloat = 20
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    Spacer().frame(height: 20)
                    
                    PenPalHeaderMenu(
                        isFounderSupporter: entitlementRepository.isFounderSupporter,
                        plan: entitlementRepository.currentPlan
                    )
                    
                    Text(appText("Stay in each other's chapters.", languageRaw))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    NavigationLink {
                        ProfileSettingsView()
                    } label: {
                        ProfileBannerView(
                            name: displayName,
                            username: username,
                            imageData: profileImageData,
                            bannerColorHex: bannerColorHex,
                            patternColorHex: patternColorHex,
                            pattern: profilePattern,
                            nameFontName: nameFontValue,
                            nameColorHex: nameColorHex,
                            showHint: false
                        )
                        .padding(.horizontal, sidePadding)
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        IssueBuilderView()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "plus")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(Color.black)
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 4) {
                                Text(appText("New Issue", languageRaw))
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.primary)

                                Text(appText("Start creating", languageRaw))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .padding(18)
                        .background(Color.gray.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .padding(.horizontal, sidePadding)
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        FriendsHubView()
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            HomeCardButton(
                                icon: "person.badge.plus",
                                title: appText("Find Friends", languageRaw),
                                subtitle: appText("Search, requests and friends", languageRaw)
                            )
                            NotificationBadge(count: friendsNewsStore.unreadCount)
                                .offset(x: -10, y: 10)
                        }
                        .padding(.horizontal, sidePadding)
                    }
                    .buttonStyle(.plain)
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 14) {
                        NavigationLink {
                            SavedDraftsView()
                        } label: {
                            HomeCardButton(
                                icon: "tray.full",
                                title: appText("Drafts", languageRaw),
                                subtitle: appText("Continue your unfinished issues", languageRaw)
                            )
                        }
                        .buttonStyle(.plain)
                        
                    }
                    .padding(.horizontal, sidePadding)
                    
                    
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "person.3")
                            Text(t("Subscriptions", "Abos", "Abbonamenti", "Suscripciones", "Abonnements"))
                                .font(.headline)
                            Spacer()
                        }
                        
                        ForEach(groupStore.groups) { group in
                            NavigationLink {
                                GroupDetailView(group: binding(for: group))
                            } label: {
                        GroupHomeCard(
                            group: group,
                            subtitle: "\(group.memberIDs.count) \(t("members", "Mitglieder", "membri", "miembros", "membres"))",
                                    unreadCount: groupUnreadCounts[group.id] ?? 0
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        
                        NavigationLink {
                            CreateGroupView(groups: $groupStore.groups)
                        } label: {
                            HomeCardButton(
                                icon: "plus",
                                title: t("Create new group", "Neue Gruppe erstellen", "Crea nuovo gruppo", "Crear nuevo grupo", "Créer un groupe"),
                                subtitle: t("Add people you want to send issues to", "Füge Personen hinzu, denen du Ausgaben senden willst", "Aggiungi persone a cui vuoi inviare i tuoi magazine", "Añade personas a quienes enviar tus ediciones", "Ajoute les personnes à qui envoyer tes numéros")
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, sidePadding)
                }
            }
            .background(PenPalStyle.background.ignoresSafeArea())
            .onAppear {
                guard Auth.auth().currentUser != nil else {
                    print("BLOCKED_QUERY_NO_AUTH", "HomeDashboardView.onAppear")
                    return
                }
                loadCurrentUserFromFirebase()
                friendsNewsStore.start()
                groupStore.loadGroups()
                syncGroupIssueListeners()
                if let route = marginNoteNotificationRouter.pendingRoute {
                    openMagazine(from: route)
                }
            }
            .onChange(of: groupStore.groups.map(\.id)) { _, _ in
                syncGroupIssueListeners()
            }
            .onChange(of: totalUnreadGroupIssues) { _, newValue in
                updateAppIconBadge(newValue)
            }
            .onChange(of: marginNoteNotificationRouter.pendingRoute) { _, route in
                guard let route else { return }
                openMagazine(from: route)
            }
            .navigationDestination(item: $notificationIssue) { issue in
                PublishedIssueDetailView(issue: issue)
            }
            .alert(appText("Archive retention notice", languageRaw), isPresented: $showArchiveRetentionNotice) {
                Button(appText("OK", languageRaw), role: .cancel) {}
            } message: {
                Text(appText("As a Free member, issues older than two months are locked. After an additional one-month grace period, their media may be permanently deleted and cannot be recovered. Premium keeps the complete archive while active.", languageRaw))
            }
        }
    }
    
    private func binding(for group: GroupModel) -> Binding<GroupModel> {
        guard let index = groupStore.groups.firstIndex(where: { $0.id == group.id }) else {
            return .constant(group)
        }
        return Binding(
            get: {
                guard groupStore.groups.indices.contains(index) else { return group }
                return groupStore.groups[index]
            },
            set: { updatedGroup in
                guard groupStore.groups.indices.contains(index) else { return }
                groupStore.groups[index] = updatedGroup
            }
        )
    }
    
    private var totalUnreadGroupIssues: Int {
        groupUnreadCounts.values.reduce(0, +)
    }
    
    private func syncGroupIssueListeners() {
        guard Auth.auth().currentUser?.uid != nil else {
            removeGroupIssueListeners()
            return
        }
        
        let activeIDs = Set(groupStore.groups.map(\.id))
        for (groupID, listener) in groupIssueListeners where !activeIDs.contains(groupID) {
            FirestoreManager.shared.removeListener(listener)
            groupIssueListeners[groupID] = nil
            groupUnreadCounts[groupID] = nil
        }
        
        for group in groupStore.groups where groupIssueListeners[group.id] == nil {
            groupIssueListeners[group.id] = FirestoreManager.shared.listenToIssues(for: group.id) { issues in
                DispatchQueue.main.async {
                    guard let uid = Auth.auth().currentUser?.uid else {
                        groupUnreadCounts[group.id] = 0
                        return
                    }
                    groupUnreadCounts[group.id] = issues.filter { !$0.viewedBy.contains(uid) }.count
                }
            }
        }

        updateAppIconBadge(totalUnreadGroupIssues)
    }
    
    private func removeGroupIssueListeners() {
        for listener in groupIssueListeners.values {
            FirestoreManager.shared.removeListener(listener)
        }
        groupIssueListeners.removeAll()
        groupUnreadCounts.removeAll()
    }

    private func updateAppIconBadge(_ count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(max(0, count)) { error in
            if let error {
                print("APP_BADGE_UPDATE_ERROR", error.localizedDescription)
            }
        }
    }

    private func openMagazine(from route: MarginNoteNotificationRoute) {
        guard Auth.auth().currentUser?.uid != nil else {
            pendingMarginNoteRoute = route
            print("BLOCKED_QUERY_NO_AUTH", "marginNoteNotificationRoute", route.magazineID)
            return
        }

        pendingMarginNoteRoute = route
        FirestoreManager.shared.fetchPublishedIssue(id: route.magazineID) { issue in
            DispatchQueue.main.async {
                guard pendingMarginNoteRoute?.id == route.id else { return }
                if let issue {
                    notificationIssue = issue
                    marginNoteNotificationRouter.pendingRoute = nil
                } else {
                    print("MARGIN_NOTE_NOTIFICATION_ROUTE_ERROR", route.magazineID)
                }
            }
        }
    }
    
    private func t(_ en: String, _ de: String, _ it: String, _ es: String, _ fr: String) -> String {
        switch language {
        case .english: return en
        case .german: return de
        case .italian: return it
        case .spanish: return es
        case .french: return fr
        }
    }
}

// MARK: - Profile

struct ProfileSettingsView: View {
    @AppStorage("username") private var username: String = ""
    @AppStorage("displayName") private var displayName: String = ""
    @AppStorage("profileImageData") private var profileImageData: String = ""
    @AppStorage("bannerColorHex") private var bannerColorHex: String = "#F6D3DC"
    @AppStorage("patternColorHex") private var patternColorHex: String = "#000000"
    @AppStorage("profilePattern") private var profilePattern: String = "plain"
    @AppStorage("nameFont") private var nameFontValue: String = "serif"
    @AppStorage("nameColorHex") private var nameColorHex: String = "#000000"
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    @StateObject private var entitlementRepository = BackendEntitlementRepository.shared
    
    private var firebaseUser: User? {
        Auth.auth().currentUser
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(appText("Profile", languageRaw))
                    .font(.system(size: 38, weight: .light, design: .serif))

                if entitlementRepository.isFounderSupporter {
                    FounderSupporterBadge()
                }
                
                NavigationLink {
                    ProfileStyleEditorView()
                } label: {
                    ProfileBannerView(
                        name: firebaseUser?.displayName ?? (displayName.isEmpty ? username.capitalized : displayName),
                        username: username,
                        imageData: profileImageData,
                        bannerColorHex: bannerColorHex,
                        patternColorHex: patternColorHex,
                        pattern: profilePattern,
                        nameFontName: nameFontValue,
                        nameColorHex: nameColorHex,
                        showHint: true
                    )
                }
                .buttonStyle(.plain)
                
                ProfileAccountSettingsSection()
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle(appText("Profile", languageRaw))
        .navigationBarTitleDisplayMode(.inline)
        .background(PenPalStyle.background.ignoresSafeArea())
        .onAppear {
            guard Auth.auth().currentUser != nil else {
                print("BLOCKED_QUERY_NO_AUTH", "ProfileSettingsView.onAppear")
                return
            }
            entitlementRepository.startObservingCurrentUser()
        }
    }
}

struct ProfileAccountSettingsSection: View {
    @AppStorage("email") private var email: String = ""
    @AppStorage("username") private var username: String = ""
    @AppStorage("displayName") private var displayName: String = ""
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    @AppStorage("homeResetID") private var homeResetID: String = UUID().uuidString

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var notificationPermissionManager = NotificationPermissionManager.shared
    @State private var errorMessage = ""
    @State private var isDeletingAccount = false
    @State private var showReauthSheet = false
    @State private var confirmPassword = ""
    @State private var reauthErrorMessage = ""
    @State private var showConfirmPassword = false

    private var selectedLanguage: Binding<AppLanguage> {
        Binding(
            get: { AppLanguage(rawValue: languageRaw) ?? .english },
            set: {
                languageRaw = $0.rawValue
                PushNotificationManager.shared.refreshAndSaveToken()
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(appText("Account settings", languageRaw))
                .font(.headline)

            SettingsRow(
                icon: "envelope",
                    title: appText("Email", languageRaw),
                subtitle: Auth.auth().currentUser?.email ?? email
            )

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "globe")
                        .frame(width: 34, height: 34)
                        .background(Color.black.opacity(0.08))
                        .clipShape(Circle())

                    Text(appText("Language", languageRaw))
                        .font(.headline)

                    Spacer()
                }

                Picker(appText("Language", languageRaw), selection: selectedLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.rawValue).tag(language)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding()
            .background(Color.gray.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 22))

            NavigationLink {
                NotificationSettingsView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "bell")
                        .frame(width: 34, height: 34)
                        .background(Color.black.opacity(0.08))
                        .clipShape(Circle())

                    Text(appText("Notifications", languageRaw))
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()

                    Text(appText(notificationPermissionManager.status.displayText, languageRaw))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 22))
            }
            .buttonStyle(.plain)
            .onAppear {
                notificationPermissionManager.refreshStatus()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    notificationPermissionManager.refreshStatus()
                }
            }

            NavigationLink {
                PrivacyPolicyView()
            } label: {
                SettingsRow(
                    icon: "hand.raised.fill",
                    title: appText("Privacy Policy", languageRaw),
                    subtitle: appText("How your data is used", languageRaw)
                )
            }

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                signOut()
            } label: {
                Text(appText("Sign out", languageRaw))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .disabled(isDeletingAccount)

            Button {
                showReauthSheet = true
            } label: {
                HStack {
                    if isDeletingAccount {
                        ProgressView()
                            .tint(.white)
                    }

                    Text(appText(isDeletingAccount ? "Deleting account..." : "Delete profile permanently", languageRaw))
                        .font(.headline)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .disabled(isDeletingAccount)
        }
        .sheet(isPresented: $showReauthSheet) {
            VStack(spacing: 24) {
                Text(appText("Confirm Password", languageRaw))
                    .font(.title2.bold())

                HStack {
                    if showConfirmPassword {
                        TextField(appText("Password", languageRaw), text: $confirmPassword)
                    } else {
                        SecureField(appText("Password", languageRaw), text: $confirmPassword)
                    }

                    Button {
                        showConfirmPassword.toggle()
                    } label: {
                        Image(systemName: showConfirmPassword ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                if !reauthErrorMessage.isEmpty {
                    Text(reauthErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(role: .destructive) {
                    reauthenticateAndDelete()
                } label: {
                    Text(appText("Delete account permanently", languageRaw))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Spacer()
            }
            .padding()
            .background(PenPalStyle.background.ignoresSafeArea())
        }
    }

    private func signOut() {
        do {
            AuthEventTracker.record("SIGN_OUT_CALLED Profile")
            PushNotificationManager.shared.deleteCurrentTokenForLogout()
            UserDefaults.standard.set(false, forKey: "isLoggedIn")
            UserDefaults.standard.removeObject(forKey: "currentUserID")
            FirestoreManager.shared.removeAllListeners(reason: "Profile signOut")
            try Auth.auth().signOut()
            clearLocalStores()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reauthenticateAndDelete() {
        guard let user = Auth.auth().currentUser,
              let email = user.email else {
            return
        }

        isDeletingAccount = true
        reauthErrorMessage = ""

        let credential = EmailAuthProvider.credential(withEmail: email, password: confirmPassword)
        AuthEventTracker.record("REAUTH_CALLED Profile delete account")
        user.reauthenticate(with: credential) { _, error in
            if let nsError = error as NSError? {
                isDeletingAccount = false
                switch nsError.code {
                case AuthErrorCode.wrongPassword.rawValue,
                     AuthErrorCode.invalidCredential.rawValue,
                     AuthErrorCode.userMismatch.rawValue:
                    reauthErrorMessage = appText("Incorrect password.", languageRaw)
                default:
                    errorMessage = nsError.localizedDescription
                }
                return
            }

            AuthEventTracker.record("DELETE_ACCOUNT_CALLED Profile")
            PushNotificationManager.shared.deleteCurrentTokenForLogout()
            FirestoreManager.shared.deleteMyAccount { error in
                isDeletingAccount = false
                if let error {
                    errorMessage = error
                    return
                }

                UserDefaults.standard.set(false, forKey: "isLoggedIn")
                UserDefaults.standard.removeObject(forKey: "currentUserID")
                FirestoreManager.shared.removeAllListeners(reason: "Profile delete account")
                clearLocalStores()
            }
        }
    }

    private func clearLocalStores() {
        email = ""
        username = ""
        displayName = ""
        PenpalGroupStore.shared.clear()
        FriendsStore.shared.friends.removeAll()
        MagazineArchiveStore.shared.savedIssues.removeAll()
        IssueDraftStore.shared.pages.removeAll()
        homeResetID = UUID().uuidString
    }
}

struct GroupHomeCard: View {
    let group: GroupModel
    let subtitle: String
    var unreadCount: Int = 0
    
    var body: some View {
        HStack(spacing: 14) {
            Base64CachedImageView(
                imageData: group.imageData,
                debugID: "group-card-\(group.id)"
            ) { image in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 46, height: 46)
                    .clipShape(Circle())
            } placeholder: {
                ZStack {
                    Circle()
                        .fill(PenPalStyle.cardAlt)
                        .frame(width: 46, height: 46)
                    
                    Image(systemName: "person.3.fill")
                        .font(.title3)
                        .foregroundStyle(PenPalStyle.ink)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(PenPalStyle.ink)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(PenPalStyle.muted)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                NotificationBadge(count: unreadCount)
                
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PenPalStyle.muted)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(PenPalStyle.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(PenPalStyle.border, lineWidth: 1)
                )
        )
    }
}

struct HomeCardButton: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(PenPalStyle.ink)
                .frame(width: 44, height: 44)
                .background(PenPalStyle.cardAlt)
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(PenPalStyle.ink)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(PenPalStyle.muted)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(PenPalStyle.muted)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(PenPalStyle.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(PenPalStyle.border, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.035), radius: 10, x: 0, y: 5)
        )
    }
}

// MARK: - Friends

private enum FriendProfileState {
    case selfProfile
    case friends
    case requested
    case incoming
    case canRequest
}

struct FriendsHubView: View {
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    @StateObject private var friendsNewsStore = FriendsNewsStore.shared
    @State private var searchText = ""
    @State private var searchResults: [PenpalProfile] = []
    @State private var incomingRequests: [FriendRequestModel] = []
    @State private var sentRequests: [FriendRequestModel] = []
    @State private var friends: [PenpalProfile] = []
    @State private var requestListener: ListenerRegistration?
    @State private var sentRequestListener: ListenerRegistration?
    @State private var messageText = ""
    @State private var showRequests = false

    var body: some View {
        List {
            Section {
                TextField(appText("Search by username", languageRaw), text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: searchText) { _, value in
                        searchUsers(value)
                    }

                ForEach(searchResults) { profile in
                    NavigationLink {
                        UserProfilePreviewView(profile: profile)
                    } label: {
                        profileRow(profile)
                    }
                }
            } header: {
                Text(appText("Find friends", languageRaw))
            }

            Section(appText("Friends", languageRaw)) {
                if friends.isEmpty {
                    Text(appText("No friends yet.", languageRaw))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(friends) { friend in
                        NavigationLink {
                            UserProfilePreviewView(profile: friend)
                        } label: {
                            profileRow(friend)
                        }
                    }
                }
            }

            if !messageText.isEmpty {
                Text(messageText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(PenPalStyle.background.ignoresSafeArea())
        .navigationTitle(appText("Friends", languageRaw))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showRequests = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "heart")
                            .font(.headline)
                        NotificationBadge(count: incomingRequests.count)
                            .offset(x: 8, y: -8)
                    }
                }
                .accessibilityLabel(appText("Friend requests", languageRaw))
            }
        }
        .sheet(isPresented: $showRequests) {
            NavigationStack {
                friendRequestsSheet
                    .navigationTitle(appText("Friend requests", languageRaw))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(appText("Done", languageRaw)) {
                                showRequests = false
                            }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear {
            guard Auth.auth().currentUser != nil else {
                print("BLOCKED_QUERY_NO_AUTH", "FriendsHubView.onAppear")
                return
            }

            friendsNewsStore.markOpened()
            FirestoreManager.shared.removeListener(requestListener)
            requestListener = FirestoreManager.shared.listenToMyFriendRequests { requests in
                DispatchQueue.main.async {
                    incomingRequests = requests
                }
            }
            FirestoreManager.shared.removeListener(sentRequestListener)
            sentRequestListener = FirestoreManager.shared.listenToMySentFriendRequests { requests in
                DispatchQueue.main.async {
                    sentRequests = requests
                }
            }
            loadFriends()
        }
        .onDisappear {
            FirestoreManager.shared.removeListener(requestListener)
            FirestoreManager.shared.removeListener(sentRequestListener)
            requestListener = nil
            sentRequestListener = nil
        }
    }

    private var friendRequestsSheet: some View {
        List {
            Section(appText("Incoming requests", languageRaw)) {
                if incomingRequests.isEmpty {
                    Text(appText("No pending requests.", languageRaw))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(incomingRequests) { request in
                        incomingRequestRow(request)
                    }
                }
            }

            Section(appText("Pending sent requests", languageRaw)) {
                if sentRequests.isEmpty {
                    Text(appText("No sent requests pending.", languageRaw))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sentRequests) { request in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("@\(request.toUsername ?? request.toUserID)")
                                    .font(.headline)
                                Text(appText("Pending", languageRaw))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(PenPalStyle.background.ignoresSafeArea())
    }

    private func profileRow(_ profile: PenpalProfile) -> some View {
        HStack(spacing: 12) {
            Base64CachedImageView(
                imageData: profile.profileImageData,
                debugID: "friend-profile-\(profile.id)"
            ) { image in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 42, height: 42)
                    .clipShape(Circle())
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(.headline)
                Text("@\(profile.username)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func incomingRequestRow(_ request: FriendRequestModel) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(request.fromDisplayName)
                    .font(.headline)
                Text("@\(request.fromUsername)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(appText("Accept", languageRaw)) {
                FirestoreManager.shared.acceptFriendRequest(request)
                loadFriends()
            }
            .buttonStyle(.borderedProminent)

            Button(appText("Decline", languageRaw)) {
                FirestoreManager.shared.declineFriendRequest(request)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    private func searchUsers(_ value: String) {
        let clean = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "@", with: "")

        guard !clean.isEmpty else {
            searchResults = []
            return
        }

        FirestoreManager.shared.searchUsers(query: clean) { users in
            DispatchQueue.main.async {
                searchResults = users.filter { $0.id != Auth.auth().currentUser?.uid }
            }
        }
    }

    private func loadFriends() {
        FirestoreManager.shared.fetchMyFriends { profiles in
            DispatchQueue.main.async {
                friends = profiles
            }
        }
    }
}

struct UserProfilePreviewView: View {
    let profile: PenpalProfile
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    @State private var state: FriendProfileState = .canRequest
    @State private var incomingRequest: FriendRequestModel?
    @State private var messageText = ""

    var body: some View {
        VStack(spacing: 22) {
            ProfileBannerView(
                name: profile.displayName,
                username: profile.username,
                imageData: profile.profileImageData ?? "",
                bannerColorHex: profile.bannerColorHex ?? "#F6D3DC",
                patternColorHex: profile.patternColorHex ?? "#000000",
                pattern: profile.profilePattern ?? "plain",
                nameFontName: profile.nameFont ?? "serif",
                nameColorHex: profile.nameColorHex ?? "#000000",
                showHint: false
            )

            if state == .incoming, let incomingRequest {
                HStack(spacing: 10) {
                    Button(appText("Accept", languageRaw)) {
                        FirestoreManager.shared.acceptFriendRequest(incomingRequest)
                        state = .friends
                        self.incomingRequest = nil
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    Button(appText("Decline", languageRaw)) {
                        FirestoreManager.shared.declineFriendRequest(incomingRequest)
                        state = .canRequest
                        self.incomingRequest = nil
                    }
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            } else {
                Button {
                    addFriend()
                } label: {
                    Text(buttonTitle)
                        .font(.headline)
                        .foregroundStyle(state == .canRequest ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(state == .canRequest ? Color.black : Color.gray.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(state != .canRequest)
            }

            if !messageText.isEmpty {
                Text(messageText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(PenPalStyle.background.ignoresSafeArea())
        .navigationTitle("@\(profile.username)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadState()
        }
    }

    private var buttonTitle: String {
        switch state {
        case .selfProfile: return appText("This is you", languageRaw)
        case .friends: return appText("Friends", languageRaw)
        case .requested: return appText("Pending", languageRaw)
        case .incoming: return appText("Respond to request", languageRaw)
        case .canRequest: return appText("Add Friend", languageRaw)
        }
    }

    private func loadState() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        if profile.id == uid {
            state = .selfProfile
            return
        }

        FirestoreManager.shared.fetchMyFriends { friends in
            if friends.contains(where: { $0.id == profile.id }) {
                DispatchQueue.main.async { state = .friends }
                return
            }

            FirestoreManager.shared.pendingIncomingFriendRequest(fromUserID: profile.id) { request in
                if let request {
                    DispatchQueue.main.async {
                        incomingRequest = request
                        state = .incoming
                    }
                    return
                }

            FirestoreManager.shared.pendingOutgoingFriendRequest(toUserID: profile.id) { pending in
                DispatchQueue.main.async {
                    state = pending ? .requested : .canRequest
                }
            }
            }
        }
    }

    private func addFriend() {
        FirestoreManager.shared.sendFriendRequest(toUsername: profile.username) { error in
            DispatchQueue.main.async {
                if let error {
                    messageText = error
                } else {
                    state = .requested
                    messageText = appText("Friend request sent.", languageRaw)
                }
            }
        }
    }
}

// MARK: - Profile Style Editor

// MARK: - Profile Editor

struct ProfileStyleEditorView: View {
    @AppStorage("username") private var username: String = ""
    @AppStorage("displayName") private var displayName: String = ""
    @AppStorage("profileImageData") private var profileImageData: String = ""
    
    // Kept for compatibility with older profile data.
    @AppStorage("bannerColorHex") private var bannerColorHex: String = "#FFFDF8"
    @AppStorage("patternColorHex") private var patternColorHex: String = "#E6E0D6"
    @AppStorage("profilePattern") private var profilePattern: String = "plain"
    @AppStorage("nameFont") private var nameFontValue: String = "serif"
    @AppStorage("nameColorHex") private var nameColorHex: String = "#171717"
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var editedDisplayName = ""
    @State private var message = ""
    
    private var firebaseUser: User? {
        Auth.auth().currentUser
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text(appText("Edit profile", languageRaw))
                    .font(.system(size: 36, weight: .light, design: .serif))
                    .foregroundStyle(PenPalStyle.ink)
                
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    VStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(PenPalStyle.cardAlt)
                                .frame(width: 120, height: 120)
                            
                            Base64CachedImageView(
                                imageData: profileImageData,
                                debugID: "profile-editor-\(username)"
                            ) { image in
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 112, height: 112)
                                    .clipShape(Circle())
                            } placeholder: {
                                Image(systemName: "person.crop.circle.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 100, height: 100)
                                    .foregroundStyle(PenPalStyle.muted.opacity(0.65))
                            }
                        }
                        
                        Text(appText("Change profile photo", languageRaw))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(PenPalStyle.accent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: PenPalStyle.corner)
                            .fill(PenPalStyle.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: PenPalStyle.corner)
                                    .stroke(PenPalStyle.border, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                
                VStack(alignment: .leading, spacing: 14) {
                    Text(appText("Display name", languageRaw))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PenPalStyle.muted)
                    
                    TextField(appText("Your name", languageRaw), text: $editedDisplayName)
                        .padding()
                        .background(PenPalStyle.cardAlt)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    
                    Text("@\(username)")
                        .font(.caption)
                        .foregroundStyle(PenPalStyle.muted)
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(PenPalStyle.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22)
                                .stroke(PenPalStyle.border, lineWidth: 1)
                        )
                )
                
                Button {
                    saveProfile()
                } label: {
                    Text(appText("Save profile", languageRaw))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(PenPalStyle.ink)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                
                if !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(PenPalStyle.muted)
                }
            }
            .padding()
        }
        .background(PenPalStyle.background.ignoresSafeArea())
        .onAppear {
            editedDisplayName = displayName
            bannerColorHex = "#FFFDF8"
            patternColorHex = "#E6E0D6"
            profilePattern = "plain"
            nameFontValue = "serif"
            nameColorHex = "#171717"
        }
        .onChange(of: selectedPhoto) { _, newItem in
            saveProfileImage(from: newItem)
        }
    }
    
    private func saveProfileImage(from item: PhotosPickerItem?) {
        guard let item else { return }
        
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data),
               let compressed = compressedBase64Image(from: image, maxSize: 700, quality: 0.45) {
                await MainActor.run {
                    profileImageData = compressed
                    saveProfile()
                }
            }
        }
    }
    
    private func saveProfile() {
        let cleanName = editedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !cleanName.isEmpty {
            displayName = cleanName
            
            let changeRequest = firebaseUser?.createProfileChangeRequest()
            changeRequest?.displayName = cleanName
            changeRequest?.commitChanges()
        }
        
        FirestoreManager.shared.updateMyProfileStyle(
            profileImageData: profileImageData,
            bannerColorHex: "#FFFDF8",
            patternColorHex: "#E6E0D6",
            profilePattern: "plain",
            nameFont: "serif",
            nameColorHex: "#171717"
        )
        
        message = appText("Profile saved.", languageRaw)
    }
}

// MARK: - Preprint Review

struct PreprintReviewView: View {
    @StateObject private var issueStore = IssueDraftStore.shared
    @StateObject private var archiveStore = MagazineArchiveStore.shared
    @StateObject private var groupStore = PenpalGroupStore.shared
    
    @AppStorage("homeResetID") private var homeResetID: String = UUID().uuidString
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    @AppStorage("displayName") private var displayName: String = ""
    
    @State private var selectedGroupIDs: Set<String> = []
    @State private var showSentMessage = false
    @State private var isPublishing = false
    @State private var isSavingDraft = false
    @State private var messageText = ""
    
    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .english
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Text(t("Preprint Review", "Preprint prüfen", "Revisione preprint", "Revisión previa", "Relecture prépublication"))
                    .font(.system(size: 32, weight: .light, design: .serif))
                
                ForEach(groupStore.groups) { group in
                    Button {
                        toggleGroup(group.id)
                    } label: {
                        HStack {
                            Image(systemName: selectedGroupIDs.contains(group.id) ? "checkmark.circle.fill" : "circle")
                            Text(group.name)
                            Spacer()
                        }
                        .padding()
                        .background(Color.gray.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
                
                Button {
                    publishIssue()
                } label: {
                    HStack {
                        if isPublishing {
                            ProgressView()
                                .tint(.white)
                        }
                        
                        Text(isPublishing ? t("Publishing...", "Wird veröffentlicht...", "Pubblicazione…", "Publicando...", "Publication...") : t("Publish / Send", "Veröffentlichen / Senden", "Pubblica / Invia", "Publicar / Enviar", "Publier / Envoyer"))
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isPublishing || isSavingDraft)
                
                Button {
                    saveDraft()
                } label: {
                    HStack {
                        if isSavingDraft {
                            ProgressView()
                                .tint(.white)
                        }
                        
                        Text(isSavingDraft ? t("Saving...", "Wird gespeichert...", "Salvataggio…", "Guardando...", "Sauvegarde...") : t("Save draft", "Entwurf speichern", "Salva bozza", "Guardar borrador", "Sauvegarder le brouillon"))
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isPublishing || isSavingDraft)
                
                Button(role: .destructive) {
                    issueStore.pages.removeAll()
                    homeResetID = UUID().uuidString
                } label: {
                    Text(t("Delete draft", "Entwurf löschen", "Elimina bozza", "Eliminar borrador", "Supprimer le brouillon"))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                
                if showSentMessage {
                    Text(messageText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }
    
    private func toggleGroup(_ id: String) {
        if selectedGroupIDs.contains(id) {
            selectedGroupIDs.remove(id)
        } else {
            selectedGroupIDs.insert(id)
        }
    }
    
    private func saveDraft() {
        guard !issueStore.pages.isEmpty else {
            messageText = t("Create at least one page first.", "Erstelle zuerst mindestens eine Seite.", "Crea prima almeno una pagina.", "Crea al menos una página primero.", "Crée d’abord au moins une page.")
            showSentMessage = true
            return
        }
        
        isSavingDraft = true
        messageText = ""
        
        let title = localizedDraftTitle(owner: displayName, languageRaw: languageRaw)

        let draftID = issueStore.currentDraftID ?? UUID().uuidString
        let scheme = issueStore.currentColourScheme ?? PenPalColourScheme.inferred(from: issueStore.pages) ?? .clean
        let pagesSnapshot = issueStore.pages
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try LocalIssueDraftStore.save(pages: pagesSnapshot, title: title, draftID: draftID, colourScheme: scheme)
                DispatchQueue.main.async {
                    issueStore.currentDraftID = draftID
                    issueStore.currentDraftTitle = title
                    issueStore.currentColourScheme = scheme
                    isSavingDraft = false
                    messageText = t("Draft saved locally. Syncing backup...", "Entwurf lokal gespeichert. Backup wird synchronisiert...", "Bozza salvata sul dispositivo. Sincronizzazione…", "Borrador guardado en el dispositivo. Sincronizando...", "Brouillon enregistré sur l’appareil. Synchronisation...")
                    showSentMessage = true
                    syncDraftBackup(draftID: draftID, title: title, colourScheme: scheme)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                        issueStore.pages.removeAll()
                        homeResetID = UUID().uuidString
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    isSavingDraft = false
                    messageText = t("Draft could not be saved: ", "Entwurf konnte nicht gespeichert werden: ", "La bozza non può essere salvata: ", "No se pudo guardar el borrador: ", "Le brouillon n’a pas pu être sauvegardé: ") + error.localizedDescription
                    showSentMessage = true
                }
            }
        }
    }

    private func syncDraftBackup(draftID: String, title: String, colourScheme: PenPalColourScheme) {
        guard let localPages = try? LocalIssueDraftStore.loadPages(id: draftID) else { return }
        FirestoreManager.shared.uploadMagazineImages(
            in: localPages,
            basePath: "issueDrafts/\(Auth.auth().currentUser?.uid ?? "unknown")/\(draftID)/images"
        ) { result in
            guard case .success(let preparedPages) = result,
                  let pageDraftData = MagazineDraftCodec.encode(preparedPages) else {
                print("DRAFT_BACKUP_SYNC_FAILED", draftID)
                return
            }

            FirestoreManager.shared.saveIssueDraft(
                title: title,
                pageImageData: [],
                pageDraftData: pageDraftData,
                imageStoragePaths: preparedPages.flatMap(\.elements).compactMap(\.imageStoragePath),
                draftID: draftID,
                colourScheme: colourScheme
            ) { error in
                if let error {
                    print("DRAFT_BACKUP_SYNC_FAILED", draftID, error)
                } else {
                    _ = try? LocalIssueDraftStore.save(pages: preparedPages, title: title, draftID: draftID, colourScheme: colourScheme)
                    print("DRAFT_BACKUP_SYNC_SUCCESS", draftID)
                }
            }
        }
    }
    
    private func publishIssue() {
        guard !issueStore.pages.isEmpty else {
            messageText = t("Create at least one page first.", "Erstelle zuerst mindestens eine Seite.", "Crea prima almeno una pagina.", "Crea al menos una página primero.", "Crée d’abord au moins une page.")
            showSentMessage = true
            return
        }
        
        guard !selectedGroupIDs.isEmpty else {
            messageText = t("Select at least one group.", "Wähle mindestens eine Gruppe aus.", "Seleziona almeno un gruppo.", "Selecciona al menos un grupo.", "Sélectionne au moins un groupe.")
            showSentMessage = true
            return
        }
        
        guard issueStore.pages.count <= 30 else {
            messageText = appText("An issue can contain up to 30 pages.", languageRaw)
            showSentMessage = true
            return
        }

        let photoCount = issueStore.pages.reduce(0) { total, page in
            total + page.elements.filter { $0.type == .image }.count
        }

        guard photoCount <= 50 else {
            messageText = appText("Your issue has too many photos. Please keep it under 50 photos.", languageRaw)
            showSentMessage = true
            return
        }
        
        isPublishing = true
        messageText = ""
        
        let savedIssue = SavedMagazineIssue(
            title: localizedIssueTitle(owner: displayName, month: Calendar.current.component(.month, from: Date()), languageRaw: languageRaw),
            date: Date(),
            pages: issueStore.pages
        )
        
        archiveStore.savedIssues.append(savedIssue)
        
        let selectedGroups = groupStore.groups.filter {
            selectedGroupIDs.contains($0.id)
        }
        
        let issueID = UUID().uuidString
        FirestoreManager.shared.uploadMagazineImages(
            in: savedIssue.pages,
            basePath: "publishedIssues/\(issueID)/images"
        ) { result in
            switch result {
            case .failure(let error):
                isPublishing = false
                messageText = appText("Issue could not be published:", languageRaw) + " \(error.localizedDescription)"
                showSentMessage = true

            case .success(let preparedPages):
                guard let pageDraftData = MagazineDraftCodec.encode(preparedPages) else {
                    isPublishing = false
                    messageText = appText("Issue could not be prepared for publishing.", languageRaw)
                    showSentMessage = true
                    return
                }

                FirestoreManager.shared.publishIssueToGroups(
                    title: savedIssue.title,
                    groups: selectedGroups,
                    pageImageData: [],
                    pageDraftData: pageDraftData,
                    issueID: issueID,
                    colourScheme: issueStore.currentColourScheme ?? PenPalColourScheme.inferred(from: preparedPages) ?? .clean
                ) { error in
                    DispatchQueue.main.async {
                        isPublishing = false
                        if let error {
                            messageText = appText("Issue could not be published:", languageRaw) + " \(error)"
                            showSentMessage = true
                            return
                        }

                            messageText = t("Your issue is on its way 💌", "Deine Ausgabe ist unterwegs 💌", "Il tuo magazine è in arrivo 💌", "Tu edición está en camino 💌", "Ton numéro est en route 💌")
                        showSentMessage = true

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            issueStore.pages.removeAll()
                            homeResetID = UUID().uuidString
                        }
                    }
                }
            }
        }
    }
    
    private func t(_ en: String, _ de: String, _ it: String, _ es: String, _ fr: String) -> String {
        switch language {
        case .english: return en
        case .german: return de
        case .italian: return it
        case .spanish: return es
        case .french: return fr
        }
    }
}
// MARK: - Throwback / Final Review

struct ThrowbackView: View {
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    @State private var issues: [PublishedIssueModel] = []
    @State private var issueToDelete: PublishedIssueModel?
    @State private var issueToShare: PublishedIssueModel?
    @State private var selectedIssue: PublishedIssueModel?
    @State private var issueListener: ListenerRegistration?
    
    var body: some View {
        List {
            if issues.isEmpty {
                Text(appText("No throwbacks yet — published issues will appear here.", languageRaw))
                    .font(.system(size: 16, weight: .medium, design: .serif))
                    .foregroundStyle(PenPalStyle.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 22)
                            .fill(PenPalStyle.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: 22)
                                    .stroke(PenPalStyle.border, lineWidth: 1)
                            )
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(issues) { issue in
                    Button {
                        selectedIssue = issue
                    } label: {
                        PublishedIssueRow(issue: issue)
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .swipeActions {
                        if issue.ownerID == Auth.auth().currentUser?.uid {
                            Button {
                                issueToShare = issue
                            } label: {
                                Label(appText("Send to groups", languageRaw), systemImage: "paperplane")
                            }
                            .tint(.blue)
                        }

                        Button(role: .destructive) {
                            issueToDelete = issue
                        } label: {
                            Label(appText("Delete", languageRaw), systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(PenPalStyle.background.ignoresSafeArea())
        .navigationTitle(appText("Throwback", languageRaw))
        .toolbarBackground(PenPalStyle.background, for: .navigationBar)
        .navigationDestination(item: $selectedIssue) { issue in
            PublishedIssueDetailView(issue: issue)
        }
        .sheet(item: $issueToShare) { issue in
            AddPublishedIssueToGroupsSheet(issue: issue)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            guard Auth.auth().currentUser?.uid != nil else {
                print("BLOCKED_QUERY_NO_AUTH", "ThrowbackView.onAppear")
                issues = []
                return
            }

            FirestoreManager.shared.removeListener(issueListener)
            issueListener = FirestoreManager.shared.listenToMyPublishedIssues { issues in
                DispatchQueue.main.async {
                    self.issues = deduplicatedPublishedIssues(issues)
                }
            }
        }
        .onDisappear {
            FirestoreManager.shared.removeListener(issueListener)
            issueListener = nil
            issues = []
        }
        .alert(appText("Delete issue?", languageRaw), isPresented: Binding(
            get: { issueToDelete != nil },
            set: { if !$0 { issueToDelete = nil } }
        )) {
            Button(appText("Cancel", languageRaw), role: .cancel) {
                issueToDelete = nil
            }
            
            Button(appText("Delete", languageRaw), role: .destructive) {
                if let issue = issueToDelete {
                    FirestoreManager.shared.deletePublishedIssue(issue)
                    issues.removeAll { $0.id == issue.id }
                }
                issueToDelete = nil
            }
        } message: {
            Text(appText("This issue will be permanently removed.", languageRaw))
        }
    }
}

private func deduplicatedPublishedIssues(_ issues: [PublishedIssueModel]) -> [PublishedIssueModel] {
    var seenKeys: Set<String> = []
    var result: [PublishedIssueModel] = []

    for issue in issues.sorted(by: { $0.createdAt > $1.createdAt }) {
        let key = issue.pageDraftDataPath?.isEmpty == false
            ? "draftPath:\(issue.pageDraftDataPath!)"
            : "issue:\(issue.id)"

        if seenKeys.insert(key).inserted {
            result.append(issue)
        }
    }

    return result
}

struct PublishedIssueRow: View {
    let issue: PublishedIssueModel
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue

    private var title: String {
        issue.title.replacingOccurrences(of: "Draft ", with: "")
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "book.pages.fill")
                .font(.title3)
                .foregroundStyle(PenPalStyle.ink)
                .frame(width: 44, height: 44)
                .background(PenPalStyle.cardAlt)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(PenPalStyle.ink)

                Text(localizedDisplayDate(issue.createdAt, languageRaw: languageRaw))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(PenPalStyle.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(PenPalStyle.border, lineWidth: 1)
        )
        .padding(.vertical, 2)
    }
}

struct AddPublishedIssueToGroupsSheet: View {
    let issue: PublishedIssueModel
    var onDone: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var groupStore = PenpalGroupStore.shared
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    @State private var selectedGroupIDs: Set<String> = []
    @State private var isSaving = false
    @State private var messageText = ""

    private var availableGroups: [GroupModel] {
        groupStore.groups.filter { !issue.groupIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                if availableGroups.isEmpty {
                    Text(appText("This issue is already available in all your groups.", languageRaw))
                        .foregroundStyle(PenPalStyle.muted)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(availableGroups) { group in
                            Button {
                                toggle(group.id)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedGroupIDs.contains(group.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedGroupIDs.contains(group.id) ? PenPalStyle.ink : PenPalStyle.muted)

                                    Text(group.name)
                                        .foregroundStyle(PenPalStyle.ink)

                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } footer: {
                        Text(appText("This sends the same published issue to the selected groups without creating another throwback copy.", languageRaw))
                    }
                }

                if !messageText.isEmpty {
                    Text(messageText)
                        .font(.caption)
                        .foregroundStyle(PenPalStyle.muted)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(PenPalStyle.background)
            .navigationTitle(appText("Send to groups", languageRaw))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(appText("Cancel", languageRaw)) {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? appText("Sending...", languageRaw) : appText("Send", languageRaw)) {
                        sendIssue()
                    }
                    .fontWeight(.semibold)
                    .disabled(isSaving || selectedGroupIDs.isEmpty)
                }
            }
            .onAppear {
                groupStore.loadGroups()
            }
        }
    }

    private func toggle(_ id: String) {
        if selectedGroupIDs.contains(id) {
            selectedGroupIDs.remove(id)
        } else {
            selectedGroupIDs.insert(id)
        }
    }

    private func sendIssue() {
        let selectedGroups = availableGroups.filter { selectedGroupIDs.contains($0.id) }
        guard !selectedGroups.isEmpty else { return }

        isSaving = true
        messageText = ""

        FirestoreManager.shared.addPublishedIssue(issue, to: selectedGroups) { error in
            DispatchQueue.main.async {
                isSaving = false

                if let error {
                    messageText = error
                    return
                }

                messageText = appText("Issue sent to selected groups.", languageRaw)
                onDone?()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    dismiss()
                }
            }
        }
    }
}

struct FinalMagazineReviewView: View {
    let issue: SavedMagazineIssue
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(issue.title)
                    .font(.system(size: 32, weight: .light, design: .serif))
                
                ForEach(issue.pages.indices, id: \.self) { index in
                    FinalMagazinePagePreview(page: issue.pages[index])
                        .frame(width: 170, height: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(radius: 3)
                }
            }
            .padding()
        }
    }
}

struct FinalMagazinePagePreview: View {
    let page: MagazinePage
    
    var body: some View {
        ZStack {
            Color(uiColor: page.backgroundColor)
            
            ForEach(page.elements) { element in
                FinalMagazineElementPreview(element: element, page: page)
                    .frame(width: element.size.width, height: element.size.height)
                    .position(element.position)
            }
        }
    }
}

struct FinalMagazineElementPreview: View {
    let element: MagazineElement
    let page: MagazinePage
    
    var body: some View {
        switch element.type {
        case .title:
            Text(element.text)
                .font(.custom(element.fontName, size: element.fontSize))
                .foregroundStyle(Color(uiColor: page.titleColor))
                .multilineTextAlignment(.center)
            
        case .text:
            Text(element.text)
                .font(.custom(element.fontName, size: element.fontSize))
                .foregroundStyle(Color(uiColor: page.textColor))
            
        case .image:
            if let image = element.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(element.imageZoom)
                    .offset(element.imageOffset)
                    .frame(width: element.size.width, height: element.size.height)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.01))
            }
            
        case .line:
            Rectangle()
                .fill(Color(uiColor: page.textColor).opacity(0.35))
            
        case .box:
            Rectangle()
                .fill(Color.clear)
                .overlay(
                    Rectangle()
                        .stroke(Color(uiColor: page.textColor).opacity(0.35), lineWidth: 0.7)
                )
        }
    }
}

// MARK: - Group Detail
struct GroupDetailView: View {
    @Binding var group: GroupModel
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var memberProfiles: [PenpalProfile] = []
    @State private var publishedIssues: [PublishedIssueModel] = []
    @State private var selectedYear = Calendar.current.component(.year, from: Date())
    @State private var showLeaveAlert = false
    @State private var showDeleteAlert = false
    @State private var selectedGroupPhoto: PhotosPickerItem?
    @State private var issueListener: ListenerRegistration?
    @State private var selectedMonthNumber = 1
    @State private var selectedMonthName = ""
    @State private var selectedMonthYear = Calendar.current.component(.year, from: Date())
    @State private var showMonthIssues = false
    @State private var showProgressSheet = false
    @State private var showPeopleSheet = false
    @State private var showReminderSheet = false
    @State private var reminderEnabled = false
    @State private var reminderDay = 15
    @State private var reminderTime = Date()
    @State private var reminderMessage = ""
    @State private var showRenameSheet = false
    @State private var editedGroupName = ""
    @State private var renameMessage = ""
    @State private var isSavingGroupName = false
    
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    
    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .english
    }
    
    private var availableYears: [Int] {
        let years = Set(publishedIssues.map { $0.year })
        let currentYear = Calendar.current.component(.year, from: Date())
        return Array(years.union([currentYear])).sorted(by: >)
    }
    
    private var months: [String] {
        localizedMonths(for: language)
    }
    
    private var isOwner: Bool {
        Auth.auth().currentUser?.uid == group.ownerID
    }
    
    private var currentMonth: Int {
        Calendar.current.component(.month, from: Date())
    }
    
    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private var memberCountText: String {
        localizedMemberCount(group.memberIDs.count, languageRaw: languageRaw)
    }

    private var reminderStatusText: String {
        guard group.reminderEnabled else { return appText("Disabled", languageRaw) }
        let minute = String(format: "%02d", group.reminderMinute)
        if (AppLanguage(rawValue: languageRaw) ?? .english) == .spanish {
            return "Cada mes el día \(group.reminderDay) a las \(group.reminderHour):\(minute)"
        }
        return "Every month on the \(group.reminderDay)\(ordinalSuffix(for: group.reminderDay)) at \(group.reminderHour):\(minute)"
    }

    private var daysInReminderMonth: Int {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = currentYear
        components.month = currentMonth
        guard let date = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: date) else {
            return 28
        }
        return range.count
    }
    
    private var membersPostedThisMonth: Set<String> {
        Set(publishedIssues
            .filter { $0.month == currentMonth && $0.year == currentYear }
            .map(\.ownerID))
            .intersection(Set(group.memberIDs))
    }
    
    private var progressRatio: Double {
        guard !group.memberIDs.isEmpty else { return 0 }
        return Double(membersPostedThisMonth.count) / Double(group.memberIDs.count)
    }
    
    private var heartSystemName: String {
        progressRatio == 0 ? "heart" : "heart.fill"
    }
    
    private var heartColor: Color {
        if progressRatio >= 1 { return Color(red: 0.78, green: 0.58, blue: 0.18) }
        if progressRatio >= 0.75 { return PenPalStyle.ink.opacity(0.62) }
        if progressRatio >= 0.5 { return PenPalStyle.ink.opacity(0.42) }
        if progressRatio > 0 { return PenPalStyle.ink.opacity(0.24) }
        return PenPalStyle.border
    }
    
    private var postedProfilesThisMonth: [PenpalProfile] {
        memberProfiles.filter { membersPostedThisMonth.contains($0.id) }
    }
    
    private var missingProfilesThisMonth: [PenpalProfile] {
        memberProfiles.filter { !membersPostedThisMonth.contains($0.id) }
    }
    
    private var currentGroupStreak: Int {
        guard !group.memberIDs.isEmpty else { return 0 }
        let memberIDs = Set(group.memberIDs)
        let calendar = Calendar.current
        let now = Date()
        var streak = 0
        var monthOffset = 0
        
        while monthOffset < 60, let date = calendar.date(byAdding: .month, value: -monthOffset, to: now) {
            let month = calendar.component(.month, from: date)
            let year = calendar.component(.year, from: date)
            let posted = Set(publishedIssues.filter { $0.month == month && $0.year == year }.map(\.ownerID))
            
            if memberIDs.isSubset(of: posted) {
                streak += 1
                monthOffset += 1
            } else {
                break
            }
        }
        
        return streak
    }
    
    private var publishingReminderCard: some View {
        Button {
            showReminderSheet = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(appText("Publishing Reminder", languageRaw))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(PenPalStyle.ink)

                    Text(reminderStatusText)
                        .font(.caption)
                        .foregroundStyle(PenPalStyle.muted)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PenPalStyle.muted)
            }
            .padding(16)
            .background(PenPalStyle.card)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(PenPalStyle.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var publishingReminderEditor: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(appText("Publishing Reminder", languageRaw), isOn: $reminderEnabled)

                    if reminderEnabled {
                        Picker(appText("Day of month", languageRaw), selection: $reminderDay) {
                            ForEach(1...daysInReminderMonth, id: \.self) { day in
                                Text("\(day)").tag(day)
                            }
                        }
                        .pickerStyle(.menu)

                        DatePicker(
                            appText("Time", languageRaw),
                            selection: $reminderTime,
                            displayedComponents: .hourAndMinute
                        )
                    }
                }

                if !reminderMessage.isEmpty {
                    Section {
                        Text(reminderMessage)
                            .foregroundStyle(PenPalStyle.muted)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(PenPalStyle.background)
            .navigationTitle(appText("Publishing Reminder", languageRaw))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(appText("Cancel", languageRaw)) {
                        showReminderSheet = false
                        loadReminderSettings()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(appText("Save", languageRaw)) {
                        saveReminderSettings {
                            showReminderSheet = false
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var groupNameEditor: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(appText("Group name", languageRaw), text: $editedGroupName)
                        .textInputAutocapitalization(.words)
                }

                if !renameMessage.isEmpty {
                    Section {
                        Text(renameMessage)
                            .foregroundStyle(PenPalStyle.muted)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(PenPalStyle.background)
            .navigationTitle(appText("Rename group", languageRaw))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(appText("Cancel", languageRaw)) {
                        showRenameSheet = false
                        editedGroupName = group.name
                        renameMessage = ""
                    }
                    .disabled(isSavingGroupName)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSavingGroupName ? appText("Saving...", languageRaw) : appText("Save", languageRaw)) {
                        saveGroupName()
                    }
                    .fontWeight(.semibold)
                    .disabled(isSavingGroupName || editedGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                
                PhotosPicker(selection: $selectedGroupPhoto, matching: .images) {
                    Base64CachedImageView(
                        imageData: group.imageData,
                        debugID: "group-detail-\(group.id)"
                    ) { image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 28))
                    } placeholder: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 28)
                                .fill(Color.gray.opacity(0.08))
                                .frame(height: 180)
                            
                            VStack(spacing: 10) {
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                Text(appText("Add group picture", languageRaw))
                                    .font(.headline)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                
                HStack(alignment: .center, spacing: 10) {
                    Text(group.name)
                        .font(.system(size: 42, weight: .light, design: .serif))
                    
                    Button {
                        showProgressSheet = true
                    } label: {
                        Image(systemName: heartSystemName)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(heartColor)
                            .accessibilityLabel(appText("Group monthly progress", languageRaw))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    showPeopleSheet = true
                } label: {
                    Text(memberCountText)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(PenPalStyle.muted)
                        .underline()
                }
                .buttonStyle(.plain)
                
                Divider()
                
                HStack {
                    Text(appText("Group magazines", languageRaw))
                        .font(.headline)
                    
                    Spacer()
                    
                    Picker(appText("Year", languageRaw), selection: $selectedYear) {
                        ForEach(availableYears, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 18) {
                    ForEach(Array(months.enumerated()), id: \.offset) { index, month in
                        Button {
                            selectedMonthNumber = index + 1
                            selectedMonthName = month
                            selectedMonthYear = selectedYear
                            showMonthIssues = true
                        } label: {
                            MagazineHolderCard(
                                month: month,
                                style: index,
                                issueCount: countIssues(for: index + 1),
                                unreadCount: unreadCount(for: index + 1)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                publishingReminderCard
            }
            .padding()
        }
        .background(PenPalStyle.background.ignoresSafeArea())
        .navigationTitle(appText("Group", languageRaw))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showMonthIssues) {
            NavigationStack {
                GroupIssuesView(
                    group: group,
                    issues: publishedIssues,
                    month: selectedMonthNumber,
                    monthName: selectedMonthName,
                    year: selectedMonthYear
                )
            }
        }
        .sheet(isPresented: $showProgressSheet) {
            GroupProgressSheet(
                monthName: localizedFullMonthName(for: Calendar.current.component(.month, from: Date()), languageRaw: languageRaw),
                postedCount: membersPostedThisMonth.count,
                totalMembers: group.memberIDs.count,
                streak: currentGroupStreak,
                postedProfiles: postedProfilesThisMonth,
                missingProfiles: missingProfilesThisMonth
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPeopleSheet) {
            NavigationStack {
                GroupMembersView(group: $group, memberProfiles: memberProfiles)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showReminderSheet) {
            publishingReminderEditor
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showRenameSheet) {
            groupNameEditor
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if isOwner {
                        Button {
                            editedGroupName = group.name
                            renameMessage = ""
                            showRenameSheet = true
                        } label: {
                            Label(appText("Rename group", languageRaw), systemImage: "pencil")
                        }
                    }

                    Button(role: .destructive) {
                        showLeaveAlert = true
                    } label: {
                        Label(appText("Leave group", languageRaw), systemImage: "rectangle.portrait.and.arrow.right")
                    }

                    if isOwner {
                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            Label(appText("Delete group", languageRaw), systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert(appText("Leave group?", languageRaw), isPresented: $showLeaveAlert) {
            Button(appText("Cancel", languageRaw), role: .cancel) { }
            
            Button(appText("Leave", languageRaw), role: .destructive) {
                FirestoreManager.shared.leaveGroup(group)
                dismiss()
            }
        } message: {
            Text(appText("You will no longer receive magazines from this group.", languageRaw))
        }
        .alert(appText("Delete group?", languageRaw), isPresented: $showDeleteAlert) {
            Button(appText("Cancel", languageRaw), role: .cancel) { }
            
            Button(appText("Delete", languageRaw), role: .destructive) {
                FirestoreManager.shared.deleteGroup(group)
                dismiss()
            }
        } message: {
            Text(appText("This permanently deletes the group for all members.", languageRaw))
        }
        .onAppear {
            loadMemberProfiles()
            loadPublishedIssues()
            loadReminderSettings()
            GroupPublishingReminderScheduler.schedule(group: group, languageRaw: languageRaw)
        }
        .onChange(of: group.memberIDs) { _, _ in
            loadMemberProfiles()
        }
        .onChange(of: group.reminderEnabled) { _, _ in
            loadReminderSettings()
            GroupPublishingReminderScheduler.schedule(group: group, languageRaw: languageRaw)
        }
        .onChange(of: group.reminderDay) { _, _ in
            loadReminderSettings()
            GroupPublishingReminderScheduler.schedule(group: group, languageRaw: languageRaw)
        }
        .onChange(of: group.reminderHour) { _, _ in
            loadReminderSettings()
            GroupPublishingReminderScheduler.schedule(group: group, languageRaw: languageRaw)
        }
        .onChange(of: group.reminderMinute) { _, _ in
            loadReminderSettings()
            GroupPublishingReminderScheduler.schedule(group: group, languageRaw: languageRaw)
        }
        .onChange(of: selectedGroupPhoto) { _, newItem in
            saveGroupImage(from: newItem)
        }
        .onDisappear {
            FirestoreManager.shared.removeListener(issueListener)
            issueListener = nil
            publishedIssues = []
        }
    }
    
    private func loadMemberProfiles() {
        FirestoreManager.shared.fetchUserProfiles(userIDs: group.memberIDs) { profiles in
            self.memberProfiles = profiles
        }
    }
    
    private func loadReminderSettings() {
        reminderEnabled = group.reminderEnabled
        reminderDay = min(max(group.reminderDay, 1), daysInReminderMonth)
        
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = min(max(group.reminderHour, 0), 23)
        components.minute = min(max(group.reminderMinute, 0), 59)
        reminderTime = Calendar.current.date(from: components) ?? Date()
    }
    
    private func saveReminderSettings(completion: (() -> Void)? = nil) {
        let timeComponents = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        let hour = timeComponents.hour ?? 19
        let minute = timeComponents.minute ?? 0
        let day = min(max(reminderDay, 1), daysInReminderMonth)
        
        group.reminderEnabled = reminderEnabled
        group.reminderDay = day
        group.reminderHour = hour
        group.reminderMinute = minute
        
        FirestoreManager.shared.updateGroupPublishingReminder(
            groupID: group.id,
            enabled: reminderEnabled,
            day: day,
            hour: hour,
            minute: minute
        ) { error in
            DispatchQueue.main.async {
                if let error {
                    reminderMessage = error
                    return
                }
                
                GroupPublishingReminderScheduler.schedule(group: group, languageRaw: languageRaw) { message in
                    DispatchQueue.main.async {
                        reminderMessage = message ?? appText(reminderEnabled ? "Reminder saved." : "Reminder turned off.", languageRaw)
                        completion?()
                    }
                }
            }
        }
    }

    private func ordinalSuffix(for day: Int) -> String {
        let normalized = day % 100
        if normalized >= 11 && normalized <= 13 { return "th" }
        switch day % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }
    
    private func loadPublishedIssues() {
        guard Auth.auth().currentUser?.uid != nil else {
            print("BLOCKED_QUERY_NO_AUTH", "GroupDetailView.loadPublishedIssues")
            publishedIssues = []
            return
        }

        guard issueListener == nil else {
            return
        }

        issueListener = FirestoreManager.shared.listenToIssues(for: group.id) { issues in
            DispatchQueue.main.async {
                self.publishedIssues = issues
            }
        }
    }
    
    private func countIssues(for month: Int) -> Int {
        publishedIssues.filter {
            $0.month == month && $0.year == selectedYear
        }.count
    }
    
    private func unreadCount(for month: Int) -> Int {
        guard let uid = Auth.auth().currentUser?.uid else { return 0 }
        
        return publishedIssues.filter {
            $0.month == month &&
            $0.year == selectedYear &&
            !$0.viewedBy.contains(uid)
        }.count
    }
    
    private func saveGroupImage(from item: PhotosPickerItem?) {
        guard let item else { return }
        
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data),
               let compressed = compressedBase64Image(from: image) {
                
                await MainActor.run {
                    group.imageData = compressed
                    FirestoreManager.shared.updateGroupImage(
                        groupID: group.id,
                        imageData: compressed
                    )
                }
            }
        }
    }

    private func saveGroupName() {
        let cleanName = editedGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }

        isSavingGroupName = true
        renameMessage = ""

        FirestoreManager.shared.updateGroupName(groupID: group.id, name: cleanName) { error in
            DispatchQueue.main.async {
                isSavingGroupName = false

                if let error {
                    renameMessage = error
                    return
                }

                group.name = cleanName
                showRenameSheet = false
            }
        }
    }
}

struct NotificationBadge: View {
    let count: Int
    
    var body: some View {
        if count > 0 {
            Text("\(count)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.red)
                .clipShape(Circle())
        }
    }
}

private struct GroupProgressSheet: View {
    let monthName: String
    let postedCount: Int
    let totalMembers: Int
    let streak: Int
    let postedProfiles: [PenpalProfile]
    let missingProfiles: [PenpalProfile]

    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Capsule()
                .fill(PenPalStyle.border)
                .frame(width: 38, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            
            Text(monthName)
                .font(.system(size: 32, weight: .light, design: .serif))
                .foregroundStyle(PenPalStyle.ink)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(localizedPostedProgress(posted: postedCount, total: totalMembers, languageRaw: languageRaw))
                    .font(.headline)
                    .foregroundStyle(PenPalStyle.ink)
                
                Text("\(appText("Current streak", languageRaw)): \(localizedMonthCount(streak, languageRaw: languageRaw))")
                    .font(.subheadline)
                    .foregroundStyle(PenPalStyle.muted)
            }
            
            Divider()
            
            if !postedProfiles.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(appText(postedProfiles.count == 1 ? "Posted singular" : "Posted", languageRaw))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PenPalStyle.muted)
                    Text(postedProfiles.map(\.displayName).joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(PenPalStyle.ink)
                }
            }
            
            if !missingProfiles.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(appText(missingProfiles.count == 1 ? "Still missing singular" : "Still missing", languageRaw))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PenPalStyle.muted)
                    Text(missingProfiles.map(\.displayName).joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(PenPalStyle.ink)
                }
            }
            
            Spacer()
        }
        .padding(22)
        .background(PenPalStyle.background.ignoresSafeArea())
    }
}

private struct GroupMemberActionButton: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(PenPalStyle.ink)
                .frame(width: 40, height: 40)
                .background(PenPalStyle.cardAlt)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(PenPalStyle.ink)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(PenPalStyle.muted)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(PenPalStyle.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(PenPalStyle.border, lineWidth: 1)
                )
        )
    }
}

struct GroupMembersView: View {
    @Binding var group: GroupModel
    let memberProfiles: [PenpalProfile]
    
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    @State private var friendUsername = ""
    @State private var userSearchResults: [PenpalProfile] = []
    @ObservedObject private var friendsStore = FriendsStore.shared
    @State private var errorMessage = ""
    @State private var successMessage = ""
    
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 22) {
                    Text(appText("Group Members", languageRaw))
                        .font(.system(size: 38, weight: .light, design: .serif))
                    
                    VStack(spacing: 8) {
                        HStack {
                            TextField("@username", text: $friendUsername)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding()
                                .background(Color.gray.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .onChange(of: friendUsername) { _, newValue in
                                    searchUsers(newValue)
                                }
                            
                            Button {
                                addFriend()
                            } label: {
                                Image(systemName: "plus")
                                    .foregroundStyle(.white)
                                    .padding()
                                    .background(Color.black)
                                    .clipShape(Circle())
                            }
                        }
                        
                        if !userSearchResults.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(userSearchResults) { user in
                                    Button {
                                        friendUsername = user.username
                                        userSearchResults = []
                                    } label: {
                                        HStack {
                                            Text(user.displayName)
                                            Spacer()
                                            Text("@\(user.username)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding()
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Divider()
                                }
                            }
                            .background(Color.gray.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    
                    if !successMessage.isEmpty {
                        Text(successMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            Section {
                ShareLink(
                    item: inviteURL,
                    subject: Text(group.name),
                    message: Text("\(appText("Join my PenPal group", languageRaw)): \(group.name)")
                ) {
                    GroupMemberActionButton(
                        icon: "paperplane",
                        title: appText("Share group link", languageRaw),
                        subtitle: appText("Invite people to join this group", languageRaw)
                    )
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                Button {
                    UIPasteboard.general.url = inviteURL
                    successMessage = appText("Invite link copied.", languageRaw)
                } label: {
                    GroupMemberActionButton(
                        icon: "link",
                        title: appText("Copy invite link", languageRaw),
                        subtitle: appText("Save the invitation link to your clipboard", languageRaw)
                    )
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            
            if memberProfiles.isEmpty {
                Text(appText("No members yet", languageRaw))
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(memberProfiles) { member in
                    UserMiniBannerCard(profile: member)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if group.ownerID == Auth.auth().currentUser?.uid &&
                                member.id != Auth.auth().currentUser?.uid {
                                
                                Button(role: .destructive) {
                                    FirestoreManager.shared.removeMemberFromGroup(
                                        groupID: group.id,
                                        userID: member.id
                                    )
                                    
                                    group.memberIDs.removeAll { $0 == member.id }
                                } label: {
                                    Label(appText("Remove", languageRaw), systemImage: "person.badge.minus")
                                }
                            }
                        }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(PenPalStyle.background.ignoresSafeArea())
        .navigationTitle(appText("Group Members", languageRaw))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(appText("Done", languageRaw)) {
                    dismiss()
                }
            }
        }
        .onAppear {
            FirestoreManager.shared.fetchMyFriends { friends in
                DispatchQueue.main.async {
                    friendsStore.friends = friends
                }
            }
        }
    }

    private var inviteURL: URL {
        URL(string: "https://penpal-4bf42.web.app/join-group/\(group.id)")!
    }
    
    private func addFriend() {
        let clean = friendUsername
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "@", with: "")
        
        guard !clean.isEmpty else {
            errorMessage = appText("Please enter a username.", languageRaw)
            return
        }
        
        FirestoreManager.shared.findUserByUsername(username: clean) { _, userID in
            DispatchQueue.main.async {
                guard let userID = userID else {
                    errorMessage = appText("User not found.", languageRaw)
                    return
                }
                
                if group.memberIDs.contains(userID) {
                    errorMessage = appText("Already in group.", languageRaw)
                    return
                }
                
                group.memberIDs.append(userID)
                
                FirestoreManager.shared.addMemberToGroup(
                    groupID: group.id,
                    userID: userID
                )
                
                friendUsername = ""
                userSearchResults = []
                errorMessage = ""
                successMessage = appText("Member added.", languageRaw)
            }
        }
    }
    
    private func searchUsers(_ value: String) {
        let clean = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "@", with: "")
        
        guard !clean.isEmpty else {
            userSearchResults = []
            return
        }
        
        userSearchResults = friendsStore.friends.filter {
            $0.username.lowercased().hasPrefix(clean) &&
            !group.memberIDs.contains($0.id)
        }
    }
}

// MARK: - Create Group

struct CreateGroupView: View {
    @Binding var groups: [GroupModel]
    @Environment(\.dismiss) private var dismiss
    
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    @State private var groupName = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImageData: String = ""
    @State private var errorMessage: String = ""
    @State private var isCreating = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            
            Text(appText("Create group", languageRaw))
                .font(.system(size: 32, weight: .light, design: .serif))
            
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.gray.opacity(0.08))
                        .frame(height: 180)
                    
                    Base64CachedImageView(
                        imageData: selectedImageData,
                        debugID: "create-group-selected"
                    ) { image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                    } placeholder: {
                        VStack(spacing: 10) {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                            
                            Text(appText("Add group picture", languageRaw))
                                .font(.headline)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            
            TextField(appText("Group name", languageRaw), text: $groupName)
                .padding()
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            
            Button {
                createGroup()
            } label: {
                HStack {
                    if isCreating {
                        ProgressView()
                            .tint(.white)
                    }
                    
                    Text(appText(isCreating ? "Creating..." : "Create group", languageRaw))
                        .font(.headline)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isCreating)
            
            Spacer()
        }
        .padding()
        .onChange(of: selectedPhoto) { _, newItem in
            saveGroupImage(from: newItem)
        }
    }
    
    private func saveGroupImage(from item: PhotosPickerItem?) {
        guard let item else { return }
        
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data),
               let compressed = compressedBase64Image(from: image) {
                
                await MainActor.run {
                    selectedImageData = compressed
                }
            }
        }
    }
    
    private func createGroup() {
        let clean = groupName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !clean.isEmpty else {
            errorMessage = appText("Please enter a group name.", languageRaw)
            return
        }
        
        if groups.contains(where: { $0.name.lowercased() == clean.lowercased() }) {
            errorMessage = appText("You already have a group with this name.", languageRaw)
            return
        }
        
        isCreating = true
        errorMessage = ""
        
        FirestoreManager.shared.createGroup(
            name: clean,
            imageData: selectedImageData
        ) { error in
            DispatchQueue.main.async {
                isCreating = false
                
                if let error = error {
                    errorMessage = error
                } else {
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
