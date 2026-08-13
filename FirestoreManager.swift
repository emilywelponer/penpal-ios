import Foundation
import Combine
import UIKit
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage

extension Notification.Name {
    static let authForceLogout = Notification.Name("PenPalAuthForceLogout")
}

#if DEBUG
extension FirestoreManager {
    /// Creates schema-valid published issues for exercising retention behavior.
    /// This is compiled out of Release builds and refuses the production project.
    func createRetentionTestIssue(
        ownerID: String,
        createdAtISO8601: String,
        title: String = "Retention test issue",
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        do {
            let projectID = try validatedRetentionTestProjectID()
            guard let signedInUID = Auth.auth().currentUser?.uid else {
                throw RetentionTestHelperError.notAuthenticated
            }
            guard ownerID == signedInUID else {
                throw RetentionTestHelperError.ownerMustBeSignedInUser
            }
            guard let createdAt = Self.retentionTestDateFormatter.date(from: createdAtISO8601) else {
                throw RetentionTestHelperError.invalidDate
            }

            let issueID = "retention-test-\(UUID().uuidString.lowercased())"
            let calendar = Calendar(identifier: .gregorian)
            let data: [String: Any] = [
                "id": issueID,
                "title": title,
                "ownerID": ownerID,
                "createdAt": Timestamp(date: createdAt),
                "month": calendar.component(.month, from: createdAt),
                "year": calendar.component(.year, from: createdAt),
                "groupIDs": [],
                "groupNames": [],
                "authorizedReaderIDs": [ownerID],
                "pageImagePaths": [],
                "viewedBy": [ownerID],
                "colourScheme": "",
                "retentionState": "accessible",
                "isTestData": true,
                "testDataKind": "retention",
                "testDataProjectID": projectID,
                "testDataCreatedBy": ownerID,
                "testDataCreatedAt": FieldValue.serverTimestamp()
            ]

            db.collection("publishedIssues").document(issueID).setData(data) { error in
                DispatchQueue.main.async {
                    if let error {
                        completion(.failure(error))
                    } else {
                        completion(.success(issueID))
                    }
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    /// Deletes only a retention-test issue owned by the signed-in test user.
    /// The normal Firestore owner-delete rule and backend Storage cleanup still apply.
    func deleteRetentionTestIssue(
        issueID: String,
        completion: @escaping (Error?) -> Void
    ) {
        do {
            _ = try validatedRetentionTestProjectID()
            guard let signedInUID = Auth.auth().currentUser?.uid else {
                throw RetentionTestHelperError.notAuthenticated
            }

            let reference = db.collection("publishedIssues").document(issueID)
            reference.getDocument { snapshot, error in
                if let error {
                    completion(error)
                    return
                }
                guard
                    let data = snapshot?.data(),
                    data["isTestData"] as? Bool == true,
                    data["testDataKind"] as? String == "retention",
                    data["ownerID"] as? String == signedInUID
                else {
                    completion(RetentionTestHelperError.notOwnedRetentionTestData)
                    return
                }
                reference.delete(completion: completion)
            }
        } catch {
            completion(error)
        }
    }

    private func validatedRetentionTestProjectID() throws -> String {
        guard let projectID = FirebaseApp.app()?.options.projectID, !projectID.isEmpty else {
            throw RetentionTestHelperError.missingProjectID
        }

        // Never permit the checked-in production project, even if it is accidentally
        // added to the local allowlist.
        guard projectID != "penpal-4bf42" else {
            throw RetentionTestHelperError.productionProjectBlocked(projectID)
        }

        let normalized = projectID.lowercased()
        let conventionalTestProject = normalized.hasPrefix("demo-")
            || normalized.contains("-dev")
            || normalized.contains("-test")
            || normalized.contains("-staging")
            || normalized.contains("emulator")
        let configuredProjects = ProcessInfo.processInfo.environment["PENPAL_TEST_FIREBASE_PROJECT_IDS"]?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? []

        guard conventionalTestProject || configuredProjects.contains(projectID) else {
            throw RetentionTestHelperError.testProjectRequired(projectID)
        }
        return projectID
    }

    private static let retentionTestDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

private enum RetentionTestHelperError: LocalizedError {
    case missingProjectID
    case productionProjectBlocked(String)
    case testProjectRequired(String)
    case notAuthenticated
    case ownerMustBeSignedInUser
    case invalidDate
    case notOwnedRetentionTestData

    var errorDescription: String? {
        switch self {
        case .missingProjectID:
            return "Firebase project ID is unavailable."
        case .productionProjectBlocked(let projectID):
            return "Retention test data is blocked for production project \(projectID)."
        case .testProjectRequired(let projectID):
            return "Project \(projectID) is not recognized as test/dev. Add it to PENPAL_TEST_FIREBASE_PROJECT_IDS in the DEBUG scheme."
        case .notAuthenticated:
            return "Sign in as the test issue owner first."
        case .ownerMustBeSignedInUser:
            return "The selected owner must be the currently signed-in test user."
        case .invalidDate:
            return "Use an ISO-8601 calendar date such as 2026-06-13."
        case .notOwnedRetentionTestData:
            return "The document is not retention test data owned by the signed-in user."
        }
    }
}
#endif

final class FirestoreManager: ObservableObject {
    
    static let shared = FirestoreManager()
    
    @Published var groups: [GroupModel] = []
    
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private var activeListeners: [ListenerRegistration] = []
    private var activeListenerLabels: [ObjectIdentifier: String] = [:]
    private var authIsBlocked = Auth.auth().currentUser == nil

    func authStateChanged(user: User?) {
        print("AUTH_STATE_CHANGED", user?.uid ?? "nil")
        authIsBlocked = user == nil
        if user == nil {
            removeAllListeners(reason: "auth state nil")
        }
    }

    @discardableResult
    private func track(_ listener: ListenerRegistration, label: String) -> ListenerRegistration {
        activeListeners.append(listener)
        activeListenerLabels[ObjectIdentifier(listener as AnyObject)] = label
        return listener
    }

    func removeAllListeners(reason: String = "manual") {
        activeListenerLabels.values.forEach { label in
            print("LISTENER_STOP", label, reason)
        }
        activeListeners.forEach {
            $0.remove()
        }
        activeListeners.removeAll()
        activeListenerLabels.removeAll()
    }

    func removeListener(_ listener: ListenerRegistration?, reason: String = "manual") {
        guard let listener else { return }
        let listenerID = ObjectIdentifier(listener as AnyObject)
        listener.remove()
        activeListeners.removeAll { ObjectIdentifier($0 as AnyObject) == listenerID }
        activeListenerLabels.removeValue(forKey: listenerID)
    }

    private func handleListenerError(_ error: Error?, label: String) -> Bool {
        guard let error else { return false }
        let nsError = error as NSError
        print("FIRESTORE_LISTENER_ERROR", label, nsError.localizedDescription)
        if nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
            print("FIRESTORE_PERMISSION_DENIED", label)
        }

        if isAuthFailure(nsError) {
            forceLogout(reason: "\(label): \(nsError.localizedDescription)")
            return true
        }

        return true
    }

    private func handleQueryError(_ error: Error?, label: String) -> Bool {
        guard let error else { return false }
        let nsError = error as NSError
        print("FIRESTORE_QUERY_ERROR", label, nsError.localizedDescription)
        if nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
            print("FIRESTORE_PERMISSION_DENIED", label)
        }

        if isAuthFailure(nsError) {
            forceLogout(reason: "\(label): \(nsError.localizedDescription)")
            return true
        }

        return true
    }

    func forceLogout(reason: String) {
        authIsBlocked = true
        AuthEventTracker.record("AUTH_FORCE_LOGOUT \(reason)")
        print("AUTH_FORCE_LOGOUT", reason)
        PushNotificationManager.shared.deleteCurrentTokenForLogout()
        removeAllListeners(reason: reason)
        NotificationCenter.default.post(
            name: .authForceLogout,
            object: nil,
            userInfo: ["reason": reason]
        )

        if Auth.auth().currentUser != nil {
            try? Auth.auth().signOut()
        }
    }

    private func isAuthFailure(_ error: NSError) -> Bool {
        // Firestore permission errors are authorization failures, not proof
        // that the Firebase Auth session is invalid.
        return Auth.auth().currentUser == nil
    }

    private func authenticatedUIDForListener(_ name: String) -> String? {
        guard !authIsBlocked, let uid = Auth.auth().currentUser?.uid else {
            print("LISTENER_BLOCKED_NO_AUTH", name)
            return nil
        }

        return uid
    }

    private func authenticatedUIDForQuery(_ name: String) -> String? {
        guard !authIsBlocked, let uid = Auth.auth().currentUser?.uid else {
            print("BLOCKED_QUERY_NO_AUTH", name)
            return nil
        }

        return uid
    }
    
    // MARK: - User Profile
    
    func createUserProfile(
        uid: String,
        username: String,
        displayName: String,
        email: String
    ) {
        let data: [String: Any] = [
            "id": uid,
            "username": username,
            "displayName": displayName,
            "email": email,
            "appLanguage": UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.english.rawValue,
            "marginNoteNotificationsEnabled": true,
            "friends": [],
            "createdAt": Timestamp(date: Date())
        ]
        
        db.collection("users").document(uid).setData(data)
        db.collection("publicProfiles").document(uid).setData([
            "id": uid,
            "username": username,
            "displayName": displayName,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }
    
    func usernameExists(
        username: String,
        completion: @escaping (Bool) -> Void
    ) {
        db.collection("publicProfiles")
            .whereField("username", isEqualTo: username)
            .limit(to: 1)
            .getDocuments { snapshot, _ in
                completion(!(snapshot?.documents.isEmpty ?? true))
            }
    }
    
    func fetchCurrentUserProfile(
        completion: @escaping (PenpalProfile?) -> Void
    ) {
        guard let uid = authenticatedUIDForQuery("fetchCurrentUserProfile") else {
            completion(nil)
            return
        }
        
        db.collection("users").document(uid).getDocument { document, error in
            if self.handleQueryError(error, label: "fetchCurrentUserProfile") {
                completion(nil)
                return
            }

            guard Auth.auth().currentUser?.uid != nil else {
                print("BLOCKED_QUERY_NO_AUTH", "fetchCurrentUserProfile completion")
                completion(nil)
                return
            }

            guard
                let data = document?.data(),
                let username = data["username"] as? String,
                let displayName = data["displayName"] as? String
            else {
                completion(nil)
                return
            }

            self.syncPublicProfile(uid: uid, privateData: data)
            
            completion(
                PenpalProfile(
                    id: uid,
                    username: username,
                    displayName: displayName,
                    profileImageData: data["profileImageData"] as? String,
                    bannerColorHex: data["bannerColorHex"] as? String,
                    patternColorHex: data["patternColorHex"] as? String,
                    profilePattern: data["profilePattern"] as? String,
                    nameFont: data["nameFont"] as? String,
                    nameColorHex: data["nameColorHex"] as? String,
                    founderSupporter: data["founderSupporter"] as? Bool ?? false,
                    founderSupporterTier: data["founderSupporterTier"] as? String,
                    hasArchiveRetentionNotice: data["archiveRetentionNotice"] != nil
                )
            )
        }
    }

    private func syncPublicProfile(uid: String, privateData: [String: Any]) {
        let allowedKeys = [
            "username", "displayName", "profileImageData", "bannerColorHex", "patternColorHex",
            "profilePattern", "nameFont", "nameColorHex"
        ]
        var publicData: [String: Any] = ["id": uid, "updatedAt": FieldValue.serverTimestamp()]
        for key in allowedKeys where privateData[key] != nil {
            publicData[key] = privateData[key]
        }
        db.collection("publicProfiles").document(uid).setData(publicData, merge: true)
    }

    // MARK: Margin Notes Feature

    func fetchMarginNoteNotificationsEnabled(
        completion: @escaping (Bool) -> Void
    ) {
        guard let uid = authenticatedUIDForQuery("fetchMarginNoteNotificationsEnabled") else {
            DispatchQueue.main.async {
                completion(true)
            }
            return
        }

        db.collection("users").document(uid).getDocument { document, error in
            if self.handleQueryError(error, label: "fetchMarginNoteNotificationsEnabled") {
                DispatchQueue.main.async {
                    completion(true)
                }
                return
            }

            let enabled = document?.data()?["marginNoteNotificationsEnabled"] as? Bool ?? true
            DispatchQueue.main.async {
                completion(enabled)
            }
        }
    }

    func updateMarginNoteNotificationsEnabled(
        _ enabled: Bool,
        completion: ((String?) -> Void)? = nil
    ) {
        guard let uid = authenticatedUIDForQuery("updateMarginNoteNotificationsEnabled") else {
            DispatchQueue.main.async {
                completion?("You need to be logged in.")
            }
            return
        }

        db.collection("users").document(uid).updateData([
            "marginNoteNotificationsEnabled": enabled
        ]) { error in
            DispatchQueue.main.async {
                completion?(error.map { $0.localizedDescription })
            }
        }
    }

    // MARK: Notification Preferences

    func fetchNotificationPreferences(
        completion: @escaping (NotificationPreferences) -> Void
    ) {
        guard let uid = authenticatedUIDForQuery("fetchNotificationPreferences") else {
            DispatchQueue.main.async {
                completion(NotificationPreferences())
            }
            return
        }

        db.collection("users").document(uid).getDocument { document, error in
            if self.handleQueryError(error, label: "fetchNotificationPreferences") {
                DispatchQueue.main.async {
                    completion(NotificationPreferences())
                }
                return
            }

            let preferences = NotificationPreferences(data: document?.data() ?? [:])
            DispatchQueue.main.async {
                completion(preferences)
            }
        }
    }

    func updateNotificationPreferences(
        _ preferences: NotificationPreferences,
        completion: ((String?) -> Void)? = nil
    ) {
        guard let uid = authenticatedUIDForQuery("updateNotificationPreferences") else {
            DispatchQueue.main.async {
                completion?("You need to be logged in.")
            }
            return
        }

        db.collection("users").document(uid).updateData(preferences.firestoreData) { error in
            DispatchQueue.main.async {
                completion?(error.map { $0.localizedDescription })
            }
        }
    }
    
    func updateMyProfileStyle(
        profileImageData: String?,
        bannerColorHex: String,
        patternColorHex: String,
        profilePattern: String,
        nameFont: String,
        nameColorHex: String
    ) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        var data: [String: Any] = [
            "bannerColorHex": bannerColorHex,
            "patternColorHex": patternColorHex,
            "profilePattern": profilePattern,
            "nameFont": nameFont,
            "nameColorHex": nameColorHex
        ]
        
        if let profileImageData {
            data["profileImageData"] = profileImageData
        }
        
        db.collection("users").document(uid).updateData(data)
    }
    
    func findUserByUsername(
        username: String,
        completion: @escaping (PenpalProfile?, String?) -> Void
    ) {
        db.collection("publicProfiles")
            .whereField("username", isEqualTo: username)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                
                if let error = error {
                    completion(nil, error.localizedDescription)
                    return
                }
                
                guard let document = snapshot?.documents.first else {
                    completion(nil, "No user found.")
                    return
                }
                
                let data = document.data()
                
                guard
                    let username = data["username"] as? String,
                    let displayName = data["displayName"] as? String
                else {
                    completion(nil, "User data incomplete.")
                    return
                }
                
                let profile = PenpalProfile(
                    id: document.documentID,
                    username: username,
                    displayName: displayName,
                    profileImageData: data["profileImageData"] as? String,
                    bannerColorHex: data["bannerColorHex"] as? String,
                    patternColorHex: data["patternColorHex"] as? String,
                    profilePattern: data["profilePattern"] as? String,
                    nameFont: data["nameFont"] as? String,
                    nameColorHex: data["nameColorHex"] as? String
                )
                
                completion(profile, document.documentID)
            }
    }
    
    func searchUsers(
        query: String,
        completion: @escaping ([PenpalProfile]) -> Void
    ) {
        let clean = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "@", with: "")
        
        guard !clean.isEmpty else {
            completion([])
            return
        }
        
        db.collection("publicProfiles")
            .whereField("username", isGreaterThanOrEqualTo: clean)
            .whereField("username", isLessThan: clean + "\u{f8ff}")
            .limit(to: 8)
            .getDocuments { snapshot, error in
                
                guard let documents = snapshot?.documents else {
                    completion([])
                    return
                }
                
                let users: [PenpalProfile] = documents.compactMap { document in
                    let data = document.data()
                    
                    guard
                        let username = data["username"] as? String,
                        let displayName = data["displayName"] as? String
                    else {
                        return nil
                    }
                    
                    return PenpalProfile(
                        id: document.documentID,
                        username: username,
                        displayName: displayName,
                        profileImageData: data["profileImageData"] as? String,
                        bannerColorHex: data["bannerColorHex"] as? String,
                        patternColorHex: data["patternColorHex"] as? String,
                        profilePattern: data["profilePattern"] as? String,
                        nameFont: data["nameFont"] as? String,
                        nameColorHex: data["nameColorHex"] as? String
                    )
                }
                
                completion(users)
            }
    }
    
    func fetchUserProfiles(
        userIDs: [String],
        completion: @escaping ([PenpalProfile]) -> Void
    ) {
        guard authenticatedUIDForQuery("fetchUserProfiles") != nil else {
            completion([])
            return
        }

        guard !userIDs.isEmpty else {
            completion([])
            return
        }
        
        var profiles: [PenpalProfile] = []
        let group = DispatchGroup()
        
        for userID in userIDs {
            group.enter()
            
            db.collection("publicProfiles").document(userID).getDocument { document, error in
                defer { group.leave() }

                if self.handleQueryError(error, label: "fetchUserProfiles") {
                    return
                }

                guard Auth.auth().currentUser?.uid != nil else {
                    print("BLOCKED_QUERY_NO_AUTH", "fetchUserProfiles completion", userID)
                    return
                }
                
                guard
                    let data = document?.data(),
                    let username = data["username"] as? String,
                    let displayName = data["displayName"] as? String
                else {
                    return
                }
                
                profiles.append(
                    PenpalProfile(
                        id: userID,
                        username: username,
                        displayName: displayName,
                        profileImageData: data["profileImageData"] as? String,
                        bannerColorHex: data["bannerColorHex"] as? String,
                        patternColorHex: data["patternColorHex"] as? String,
                        profilePattern: data["profilePattern"] as? String,
                        nameFont: data["nameFont"] as? String,
                        nameColorHex: data["nameColorHex"] as? String
                    )
                )
            }
        }
        
        group.notify(queue: .main) {
            completion(profiles)
        }
    }
    
    // MARK: - Groups
    
    func createGroup(
        name: String,
        imageData: String? = nil,
        completion: @escaping (String?) -> Void
    ) {
        guard let currentUser = Auth.auth().currentUser else {
            completion("You must be signed in before creating a group.")
            return
        }
        
        let userID = currentUser.uid
        guard !userID.isEmpty else {
            completion("Could not create the group because the signed-in user has no Firebase uid.")
            return
        }
        
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            completion("Please enter a group name.")
            return
        }
        
        let groupID = UUID().uuidString
        
        let data: [String: Any] = [
            "id": groupID,
            "name": cleanName,
            "ownerID": userID,
            "memberIDs": [userID],
            "imageData": imageData ?? "",
            "publishingDay": NSNull(),
            "reminderEnabled": false,
            "reminderDay": 15,
            "reminderHour": 19,
            "reminderMinute": 0,
            "createdAt": Timestamp(date: Date())
        ]
        
        db.collection("groups").document(groupID).setData(data) { error in
            if let error {
                completion("Group could not be created: \(error.localizedDescription)")
            } else {
                completion(nil)
            }
        }
    }
    
    func updateGroupImage(
        groupID: String,
        imageData: String
    ) {
        db.collection("groups").document(groupID).updateData([
            "imageData": imageData
        ])
    }
    
    func updateGroupPublishingDay(
        groupID: String,
        publishingDay: Int?
    ) {
        let value: Any
        if let publishingDay {
            value = min(max(publishingDay, 1), 31)
        } else {
            value = FieldValue.delete()
        }
        
        db.collection("groups").document(groupID).updateData([
            "publishingDay": value
        ])
    }
    
    func updateGroupPublishingReminder(
        groupID: String,
        enabled: Bool,
        day: Int,
        hour: Int,
        minute: Int,
        completion: ((String?) -> Void)? = nil
    ) {
        db.collection("groups").document(groupID).updateData([
            "reminderEnabled": enabled,
            "reminderDay": min(max(day, 1), 31),
            "reminderHour": min(max(hour, 0), 23),
            "reminderMinute": min(max(minute, 0), 59)
        ]) { error in
            completion?(error.map { "Reminder could not be saved: \($0.localizedDescription)" })
        }
    }

    func updateGroupName(
        groupID: String,
        name: String,
        completion: ((String?) -> Void)? = nil
    ) {
        guard Auth.auth().currentUser?.uid != nil else {
            completion?("No logged-in user.")
            return
        }

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            completion?("Please enter a group name.")
            return
        }

        db.collection("groups").document(groupID).updateData([
            "name": cleanName
        ]) { error in
            completion?(error.map { "Group name could not be saved: \($0.localizedDescription)" })
        }
    }
    
    func addMemberToGroup(
        groupID: String,
        userID: String
    ) {
        db.collection("groups").document(groupID).updateData([
            "memberIDs": FieldValue.arrayUnion([userID])
        ])
    }

    func handleGroupInviteURL(_ url: URL) {
        let groupID: String?

        if url.scheme == "penpal" {
            if url.host == "join-group" {
                groupID = url.pathComponents.dropFirst().first
            } else if url.host == "group" {
                groupID = url.pathComponents.dropFirst().first
            } else {
                groupID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first(where: { $0.name == "groupID" })?
                    .value
            }
        } else if url.scheme == "https",
                  url.host == "penpal-4bf42.web.app",
                  url.pathComponents.dropFirst().first == "join-group" {
            groupID = url.pathComponents.dropFirst().dropFirst().first
        } else {
            return
        }

        guard let groupID, !groupID.isEmpty else { return }
        guard let uid = Auth.auth().currentUser?.uid else {
            print("BLOCKED_QUERY_NO_AUTH", "handleGroupInviteURL")
            return
        }

        db.collection("groups").document(groupID).updateData([
            "memberIDs": FieldValue.arrayUnion([uid])
        ]) { error in
            if let error {
                print("GROUP_INVITE_JOIN_ERROR", error.localizedDescription)
            } else {
                print("GROUP_INVITE_JOINED", groupID)
            }
        }
    }
    
    func removeMemberFromGroup(
        groupID: String,
        userID: String
    ) {
        db.collection("groups").document(groupID).updateData([
            "memberIDs": FieldValue.arrayRemove([userID])
        ])
    }
    
    @discardableResult
    func listenToGroups(
        completion: @escaping ([GroupModel]) -> Void
    ) -> ListenerRegistration? {
        guard let uid = authenticatedUIDForListener("groups") else {
            completion([])
            return nil
        }

        let listener = db.collection("groups")
            .whereField("memberIDs", arrayContains: uid)
            .addSnapshotListener { snapshot, error in
                if self.handleListenerError(error, label: "groups") {
                    completion([])
                    return
                }

                guard Auth.auth().currentUser?.uid != nil else {
                    print("BLOCKED_QUERY_NO_AUTH", "groups listener callback")
                    completion([])
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion([])
                    return
                }
                
                let groups = documents.compactMap { document in
                    self.makeGroupModel(from: document)
                }
                
                completion(groups.sorted { $0.createdAt > $1.createdAt })
            }

        return track(listener, label: "groups")
    }
    
    private func makeGroupModel(from document: QueryDocumentSnapshot) -> GroupModel? {
        let data = document.data()
        
        guard
            let id = data["id"] as? String,
            let name = data["name"] as? String,
            let ownerID = data["ownerID"] as? String,
            let memberIDs = data["memberIDs"] as? [String],
            let timestamp = data["createdAt"] as? Timestamp
        else {
            return nil
        }
        
        return GroupModel(
            id: id,
            name: name,
            ownerID: ownerID,
            memberIDs: memberIDs,
            createdAt: timestamp.dateValue(),
            imageData: data["imageData"] as? String,
            publishingDay: data["publishingDay"] as? Int,
            reminderEnabled: data["reminderEnabled"] as? Bool ?? false,
            reminderDay: data["reminderDay"] as? Int ?? data["publishingDay"] as? Int ?? 15,
            reminderHour: data["reminderHour"] as? Int ?? 19,
            reminderMinute: data["reminderMinute"] as? Int ?? 0
        )
    }
    
    func leaveGroup(_ group: GroupModel) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        db.collection("groups").document(group.id).updateData([
            "memberIDs": FieldValue.arrayRemove([uid])
        ])
    }
    
    func deleteGroup(_ group: GroupModel) {
        db.collection("groups").document(group.id).delete()
    }
    

    
    // MARK: - Friend Requests / Friends
    
    func sendFriendRequest(
        toUsername: String,
        completion: @escaping (String?) -> Void
    ) {
        guard let currentUser = Auth.auth().currentUser else {
            completion("No logged-in user.")
            return
        }
        
        let cleanUsername = toUsername
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "@", with: "")
        
        findUserByUsername(username: cleanUsername) { profile, toUserID in
            
            guard let profile = profile,
                  let toUserID = toUserID else {
                completion("User not found.")
                return
            }
            
            if toUserID == currentUser.uid {
                completion("You cannot add yourself.")
                return
            }
            
            self.db.collection("users").document(currentUser.uid).getDocument { document, _ in
                let myFriends = document?.data()?["friends"] as? [String] ?? []
                
                if myFriends.contains(toUserID) {
                    completion("This person is already your friend.")
                    return
                }
                
                self.db.collection("friendRequests")
                    .whereField("fromUserID", isEqualTo: currentUser.uid)
                    .whereField("toUserID", isEqualTo: toUserID)
                    .whereField("status", isEqualTo: "pending")
                    .getDocuments { snapshot, _ in
                        
                        if !(snapshot?.documents.isEmpty ?? true) {
                            completion("Friend request already sent.")
                            return
                        }
                        
                        let requestID = "\(currentUser.uid)_\(toUserID)"
                        
                        let data: [String: Any] = [
                            "id": requestID,
                            "fromUserID": currentUser.uid,
                            "fromUsername": UserDefaults.standard.string(forKey: "username") ?? "",
                            "fromDisplayName": currentUser.displayName ?? "Someone",
                            "toUserID": toUserID,
                            "toUsername": profile.username,
                            "status": "pending",
                            "createdAt": Timestamp(date: Date())
                        ]
                        
                        print("FRIEND_REQUEST_WRITE", requestID)
                        self.db.collection("friendRequests").document(requestID).setData(data) { error in
                            completion(error?.localizedDescription)
                        }
                    }
            }
        }
    }

    func pendingOutgoingFriendRequest(
        toUserID: String,
        completion: @escaping (Bool) -> Void
    ) {
        guard let currentUserID = authenticatedUIDForQuery("pendingOutgoingFriendRequest") else {
            completion(false)
            return
        }

        let requestID = "\(currentUserID)_\(toUserID)"
        db.collection("friendRequests").document(requestID).getDocument { document, error in
            if self.handleQueryError(error, label: "pendingOutgoingFriendRequest") {
                completion(false)
                return
            }

            completion((document?.data()?["status"] as? String) == "pending")
        }
    }
    
    @discardableResult
    func listenToMyFriendRequests(
        completion: @escaping ([FriendRequestModel]) -> Void
    ) -> ListenerRegistration? {
        guard let uid = authenticatedUIDForListener("friendRequests") else {
            completion([])
            return nil
        }

        var listener: ListenerRegistration?
        listener = db.collection("friendRequests")
            .whereField("toUserID", isEqualTo: uid)
            .whereField("status", isEqualTo: "pending")
            .addSnapshotListener { snapshot, error in
                if self.handleListenerError(error, label: "friendRequests") {
                    self.removeListener(listener, reason: "friendRequests listener error")
                    completion([])
                    return
                }

                guard Auth.auth().currentUser?.uid != nil else {
                    print("BLOCKED_QUERY_NO_AUTH", "friendRequests listener callback")
                    completion([])
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion([])
                    return
                }
                
                let requests = documents.compactMap { doc -> FriendRequestModel? in
                    let data = doc.data()
                    
                    guard
                        let id = data["id"] as? String,
                        let fromUserID = data["fromUserID"] as? String,
                        let fromUsername = data["fromUsername"] as? String,
                        let fromDisplayName = data["fromDisplayName"] as? String,
                        let toUserID = data["toUserID"] as? String,
                        let status = data["status"] as? String,
                        let timestamp = data["createdAt"] as? Timestamp
                    else {
                        return nil
                    }
                    
                    return FriendRequestModel(
                        id: id,
                        fromUserID: fromUserID,
                        fromUsername: fromUsername,
                        fromDisplayName: fromDisplayName,
                        toUserID: toUserID,
                        toUsername: data["toUsername"] as? String,
                        status: status,
                        createdAt: timestamp.dateValue()
                    )
                }
                
                completion(requests)
            }

        guard let listener else {
            completion([])
            return nil
        }
        return track(listener, label: "friendRequests")
    }

    @discardableResult
    func listenToMySentFriendRequests(
        completion: @escaping ([FriendRequestModel]) -> Void
    ) -> ListenerRegistration? {
        guard let uid = authenticatedUIDForListener("sentFriendRequests") else {
            completion([])
            return nil
        }

        var listener: ListenerRegistration?
        listener = db.collection("friendRequests")
            .whereField("fromUserID", isEqualTo: uid)
            .whereField("status", isEqualTo: "pending")
            .addSnapshotListener { snapshot, error in
                if self.handleListenerError(error, label: "sentFriendRequests") {
                    self.removeListener(listener, reason: "sentFriendRequests listener error")
                    completion([])
                    return
                }

                guard let documents = snapshot?.documents else {
                    completion([])
                    return
                }

                let requests = documents.compactMap { doc -> FriendRequestModel? in
                    let data = doc.data()
                    guard
                        let id = data["id"] as? String,
                        let fromUserID = data["fromUserID"] as? String,
                        let fromUsername = data["fromUsername"] as? String,
                        let fromDisplayName = data["fromDisplayName"] as? String,
                        let toUserID = data["toUserID"] as? String,
                        let status = data["status"] as? String,
                        let timestamp = data["createdAt"] as? Timestamp
                    else {
                        return nil
                    }

                    return FriendRequestModel(
                        id: id,
                        fromUserID: fromUserID,
                        fromUsername: fromUsername,
                        fromDisplayName: fromDisplayName,
                        toUserID: toUserID,
                        toUsername: data["toUsername"] as? String,
                        status: status,
                        createdAt: timestamp.dateValue()
                    )
                }

                completion(requests)
            }

        guard let listener else {
            completion([])
            return nil
        }
        return track(listener, label: "sentFriendRequests")
    }

    func pendingIncomingFriendRequest(
        fromUserID: String,
        completion: @escaping (FriendRequestModel?) -> Void
    ) {
        guard let currentUserID = authenticatedUIDForQuery("pendingIncomingFriendRequest") else {
            completion(nil)
            return
        }

        let requestID = "\(fromUserID)_\(currentUserID)"
        db.collection("friendRequests").document(requestID).getDocument { document, error in
            if self.handleQueryError(error, label: "pendingIncomingFriendRequest") {
                completion(nil)
                return
            }

            guard
                let data = document?.data(),
                (data["status"] as? String) == "pending",
                let id = data["id"] as? String,
                let fromUserID = data["fromUserID"] as? String,
                let fromUsername = data["fromUsername"] as? String,
                let fromDisplayName = data["fromDisplayName"] as? String,
                let toUserID = data["toUserID"] as? String,
                let status = data["status"] as? String,
                let timestamp = data["createdAt"] as? Timestamp
            else {
                completion(nil)
                return
            }

            completion(FriendRequestModel(
                id: id,
                fromUserID: fromUserID,
                fromUsername: fromUsername,
                fromDisplayName: fromDisplayName,
                toUserID: toUserID,
                toUsername: data["toUsername"] as? String,
                status: status,
                createdAt: timestamp.dateValue()
            ))
        }
    }
    
    func acceptFriendRequest(_ request: FriendRequestModel) {
        
        let currentUID = request.toUserID
        let senderUID = request.fromUserID
        
        // Add sender to my friends
        db.collection("users")
            .document(currentUID)
            .updateData([
                "friends": FieldValue.arrayUnion([senderUID])
            ])
        
        // Add me to sender friends
        db.collection("users")
            .document(senderUID)
            .updateData([
                "friends": FieldValue.arrayUnion([currentUID])
            ])
        
        // Delete request
        db.collection("friendRequests")
            .document(request.id)
            .delete()
    }
    
    func declineFriendRequest(_ request: FriendRequestModel) {
        db.collection("friendRequests").document(request.id).updateData([
            "status": "declined"
        ])
    }
    
    func fetchMyFriends(
        completion: @escaping ([PenpalProfile]) -> Void
    ) {
        guard let uid = authenticatedUIDForQuery("fetchMyFriends") else {
            completion([])
            return
        }
        
        db.collection("users").document(uid).getDocument { document, error in
            if self.handleQueryError(error, label: "fetchMyFriends") {
                completion([])
                return
            }

            guard Auth.auth().currentUser?.uid != nil else {
                print("BLOCKED_QUERY_NO_AUTH", "fetchMyFriends completion")
                completion([])
                return
            }

            guard
                let data = document?.data(),
                let friendIDs = data["friends"] as? [String]
            else {
                completion([])
                return
            }
            
            self.fetchUserProfiles(userIDs: friendIDs) { profiles in
                completion(profiles)
            }
        }
    }
    
    func removeFriend(userID: String) {
        guard let currentUserID = Auth.auth().currentUser?.uid else { return }
        
        db.collection("users").document(currentUserID).updateData([
            "friends": FieldValue.arrayRemove([userID])
        ])
        
        db.collection("users").document(userID).updateData([
            "friends": FieldValue.arrayRemove([currentUserID])
        ])
    }
    
    // MARK: - Published Issues
    
    func publishIssueToGroups(
        title: String,
        groups: [GroupModel],
        pageImageData: [String],
        pageDraftData: String? = nil,
        issueID: String? = nil,
        colourScheme: PenPalColourScheme? = nil,
        completion: ((String?) -> Void)? = nil
    ) {
        guard let userID = Auth.auth().currentUser?.uid else {
            completion?("No logged-in user.")
            return
        }
        
        let now = Date()
        let calendar = Calendar.current
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)
        let issueID = issueID ?? UUID().uuidString
        
        self.uploadDraftDataIfNeeded(
            pageDraftData,
            path: "publishedIssues/\(issueID)/draftData/pageDraftData.json"
        ) { draftDataResult in
            switch draftDataResult {
            case .failure(let error):
                self.rollbackPublishedUpload(issueID: issueID)
                completion?(error.localizedDescription)

            case .success(let pageDraftDataPath):
                self.uploadBase64Images(
                    pageImageData,
                    basePath: "publishedIssues/\(issueID)/pages",
                    filePrefix: "page"
                ) { result in
                    switch result {
                    case .failure(let error):
                        self.rollbackPublishedUpload(issueID: issueID)
                        completion?(error.localizedDescription)

                    case .success(let pageImagePaths):
                        let authorizedReaderIDs = Array(Set(groups.flatMap(\.memberIDs) + [userID]))
                        var data: [String: Any] = [
                            "id": issueID,
                            "title": title,
                            "ownerID": userID,
                            "createdAt": Timestamp(date: now),
                            "month": month,
                            "year": year,
                            "groupIDs": groups.map { $0.id },
                            "groupNames": groups.map { $0.name },
                            "authorizedReaderIDs": authorizedReaderIDs,
                            "pageImagePaths": pageImagePaths,
                            "viewedBy": [userID],
                            "colourScheme": colourScheme?.rawValue ?? ""
                        ]

                        if let pageDraftDataPath {
                            data["pageDraftDataPath"] = pageDraftDataPath
                        }

                        self.db.collection("publishedIssues").document(issueID).setData(data) { error in
                            if let error {
                                self.rollbackPublishedUpload(issueID: issueID)
                                completion?(error.localizedDescription)
                            } else {
                                self.closePublishedUploadSession(issueID: issueID)
                                completion?(nil)
                            }
                        }
                    }
                }
            }
        }
    }

    func addPublishedIssue(
        _ issue: PublishedIssueModel,
        to groups: [GroupModel],
        completion: ((String?) -> Void)? = nil
    ) {
        guard let currentUserID = Auth.auth().currentUser?.uid else {
            completion?("No logged-in user.")
            return
        }

        guard issue.ownerID == currentUserID else {
            completion?("Only the publisher can send this issue to more groups.")
            return
        }

        let newGroups = groups.filter { !issue.groupIDs.contains($0.id) }
        guard !newGroups.isEmpty else {
            completion?("Select at least one new group.")
            return
        }

        let mergedGroupIDs = issue.groupIDs + newGroups.map(\.id)
        let mergedGroupNames = issue.groupNames + newGroups.map(\.name)
        let mergedReaderIDs = Array(Set(newGroups.flatMap(\.memberIDs) + [currentUserID]))

        db.collection("publishedIssues").document(issue.id).updateData([
            "groupIDs": mergedGroupIDs,
            "groupNames": mergedGroupNames,
            "authorizedReaderIDs": FieldValue.arrayUnion(mergedReaderIDs)
        ]) { error in
            completion?(error.map { "Issue could not be sent to more groups: \($0.localizedDescription)" })
        }
    }
    
    @discardableResult
    func listenToIssues(
        for groupID: String,
        completion: @escaping ([PublishedIssueModel]) -> Void
    ) -> ListenerRegistration? {
        guard authenticatedUIDForListener("publishedIssues.group") != nil else {
            completion([])
            return nil
        }

        guard let uid = Auth.auth().currentUser?.uid else { completion([]); return nil }
        let listener = db.collection("publishedIssues")
            .whereField("authorizedReaderIDs", arrayContains: uid)
            .addSnapshotListener { snapshot, error in
                if self.handleListenerError(error, label: "publishedIssues.group") {
                    completion([])
                    return
                }

                guard Auth.auth().currentUser?.uid != nil else {
                    print("BLOCKED_QUERY_NO_AUTH", "publishedIssues.group listener callback")
                    completion([])
                    return
                }

                completion(self.makePublishedIssues(from: snapshot, includePayloads: false).filter { $0.groupIDs.contains(groupID) })
            }

        return track(listener, label: "publishedIssues.group")
    }
    
    @discardableResult
    func listenToMyPublishedIssues(
        completion: @escaping ([PublishedIssueModel]) -> Void
    ) -> ListenerRegistration? {
        guard let uid = authenticatedUIDForListener("publishedIssues.mine") else {
            completion([])
            return nil
        }

        let listener = db.collection("publishedIssues")
            .whereField("ownerID", isEqualTo: uid)
            .addSnapshotListener { snapshot, error in
                if self.handleListenerError(error, label: "publishedIssues.mine") {
                    completion([])
                    return
                }

                guard Auth.auth().currentUser?.uid != nil else {
                    print("BLOCKED_QUERY_NO_AUTH", "publishedIssues.mine listener callback")
                    completion([])
                    return
                }

                completion(self.makePublishedIssues(from: snapshot, includePayloads: false))
            }

        return track(listener, label: "publishedIssues.mine")
    }
    
    func fetchPublishedIssue(
        id: String,
        completion: @escaping (PublishedIssueModel?) -> Void
    ) {
        guard authenticatedUIDForQuery("fetchPublishedIssue") != nil else {
            completion(nil)
            return
        }

        db.collection("publishedIssues").document(id).getDocument { document, error in
            if self.handleQueryError(error, label: "fetchPublishedIssue") {
                completion(nil)
                return
            }

            guard Auth.auth().currentUser?.uid != nil else {
                print("BLOCKED_QUERY_NO_AUTH", "fetchPublishedIssue completion", id)
                completion(nil)
                return
            }

            guard let data = document?.data() else {
                completion(nil)
                return
            }

            completion(self.makePublishedIssue(id: id, data: data, includePayloads: true))
        }
    }

    private func makePublishedIssues(
        from snapshot: QuerySnapshot?,
        includePayloads: Bool
    ) -> [PublishedIssueModel] {
        guard let documents = snapshot?.documents else { return [] }
        
        return documents.compactMap { doc in
            if includePayloads {
                return makePublishedIssue(id: doc.documentID, data: doc.data(), includePayloads: true)
            }

            return makePublishedIssueMetadata(from: doc)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    private func makePublishedIssueMetadata(from document: QueryDocumentSnapshot) -> PublishedIssueModel? {
        guard
            let title = document.get("title") as? String,
            let ownerID = document.get("ownerID") as? String,
            let timestamp = document.get("createdAt") as? Timestamp,
            let month = document.get("month") as? Int,
            let year = document.get("year") as? Int
        else {
            return nil
        }

        return PublishedIssueModel(
            id: document.get("id") as? String ?? document.documentID,
            title: title,
            ownerID: ownerID,
            createdAt: timestamp.dateValue(),
            month: month,
            year: year,
            groupIDs: document.get("groupIDs") as? [String] ?? [],
            groupNames: document.get("groupNames") as? [String] ?? [],
            pageImageData: [],
            pageImagePaths: document.get("pageImagePaths") as? [String] ?? [],
            pageDraftData: nil,
            pageDraftDataPath: document.get("pageDraftDataPath") as? String,
            viewedBy: document.get("viewedBy") as? [String] ?? [],
            colourSchemeRaw: document.get("colourScheme") as? String,
            retentionState: document.get("retentionState") as? String
        )
    }

    private func makePublishedIssue(
        id documentID: String,
        data: [String: Any],
        includePayloads: Bool
    ) -> PublishedIssueModel? {
        guard
            let title = data["title"] as? String,
            let ownerID = data["ownerID"] as? String,
            let timestamp = data["createdAt"] as? Timestamp,
            let month = data["month"] as? Int,
            let year = data["year"] as? Int
        else {
            return nil
        }

        return PublishedIssueModel(
            id: data["id"] as? String ?? documentID,
            title: title,
            ownerID: ownerID,
            createdAt: timestamp.dateValue(),
            month: month,
            year: year,
            groupIDs: data["groupIDs"] as? [String] ?? [],
            groupNames: data["groupNames"] as? [String] ?? [],
            pageImageData: includePayloads ? data["pageImageData"] as? [String] ?? [] : [],
            pageImagePaths: data["pageImagePaths"] as? [String] ?? [],
            pageDraftData: includePayloads ? data["pageDraftData"] as? String : nil,
            pageDraftDataPath: data["pageDraftDataPath"] as? String,
            viewedBy: data["viewedBy"] as? [String] ?? [],
            colourSchemeRaw: data["colourScheme"] as? String,
            retentionState: data["retentionState"] as? String
        )
    }
    
    func markIssueAsRead(_ issue: PublishedIssueModel) {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("BLOCKED_QUERY_NO_AUTH", "markIssueAsRead", issue.id)
            return
        }
        
        db.collection("publishedIssues")
            .document(issue.id)
            .updateData([
                "viewedBy": FieldValue.arrayUnion([uid])
            ]) { error in
                if let error {
                    print("MARK_ISSUE_READ_ERROR", issue.id, error.localizedDescription)
                }
            }
    }
    
    func deletePublishedIssue(_ issue: PublishedIssueModel) {
        guard let currentUserID = Auth.auth().currentUser?.uid else { return }
        guard issue.ownerID == currentUserID else { return }
        
        db.collection("publishedIssues").document(issue.id).delete()
    }
    
    // MARK: - Drafts
    
    func saveIssueDraft(
        title: String,
        pageImageData: [String],
        pageDraftData: String? = nil,
        imageStoragePaths: [String] = [],
        draftID: String? = nil,
        colourScheme: PenPalColourScheme? = nil,
        completion: ((String?) -> Void)? = nil
    ) {
        guard let userID = Auth.auth().currentUser?.uid else {
            completion?("No logged-in user.")
            return
        }
        
        let draftID = draftID ?? UUID().uuidString
        let now = Date()
        
        uploadBase64Images(
            pageImageData,
            basePath: "issueDrafts/\(userID)/\(draftID)/previews",
            filePrefix: "preview"
        ) { imageResult in
            switch imageResult {
            case .failure(let error):
                completion?(error.localizedDescription)
                
            case .success(let previewImagePaths):
                self.uploadDraftDataIfNeeded(
                    pageDraftData,
                    path: "issueDrafts/\(userID)/\(draftID)/draftData/pageDraftData.json"
                ) { draftDataResult in
                    switch draftDataResult {
                    case .failure(let error):
                        completion?(error.localizedDescription)
                        
                    case .success(let pageDraftDataPath):
                        var data: [String: Any] = [
                            "id": draftID,
                            "title": title,
                            "ownerID": userID,
                            "createdAt": Timestamp(date: now),
                            "updatedAt": Timestamp(date: now),
                            "previewImagePaths": previewImagePaths,
                            "imageStoragePaths": imageStoragePaths,
                            "colourScheme": colourScheme?.rawValue ?? ""
                        ]
                        
                        if let pageDraftDataPath {
                            data["pageDraftDataPath"] = pageDraftDataPath
                        }
                        
                        self.db.collection("issueDrafts").document(draftID).setData(data) { error in
                            if let error {
                                completion?(error.localizedDescription)
                            } else {
                                completion?(nil)
                            }
                        }
                    }
                }
            }
        }
    }
    
    @discardableResult
    func listenToMyIssueDrafts(
        completion: @escaping ([SavedIssueDraftModel]) -> Void
    ) -> ListenerRegistration? {
        guard let uid = authenticatedUIDForListener("issueDrafts") else {
            completion([])
            return nil
        }

        let listener = db.collection("issueDrafts")
            .whereField("ownerID", isEqualTo: uid)
            .addSnapshotListener { snapshot, error in
                if self.handleListenerError(error, label: "issueDrafts") {
                    completion([])
                    return
                }

                guard Auth.auth().currentUser?.uid != nil else {
                    print("BLOCKED_QUERY_NO_AUTH", "issueDrafts listener callback")
                    completion([])
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion([])
                    return
                }
                
                let drafts = documents.compactMap { doc -> SavedIssueDraftModel? in
                    let data = doc.data()
                    
                    guard
                        let id = data["id"] as? String,
                        let title = data["title"] as? String,
                        let ownerID = data["ownerID"] as? String,
                        let timestamp = data["createdAt"] as? Timestamp
                    else {
                        return nil
                    }
                    
                    return SavedIssueDraftModel(
                        id: id,
                        title: title,
                        ownerID: ownerID,
                        createdAt: timestamp.dateValue(),
                        pageImageData: data["pageImageData"] as? [String] ?? [],
                        previewImagePaths: data["previewImagePaths"] as? [String] ?? [],
                        pageDraftData: data["pageDraftData"] as? String,
                        pageDraftDataPath: data["pageDraftDataPath"] as? String,
                        updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue(),
                        colourSchemeRaw: data["colourScheme"] as? String
                    )
                }
                
                completion(drafts.sorted { $0.createdAt > $1.createdAt })
            }

        return track(listener, label: "issueDrafts")
    }
    
    func deleteIssueDraft(_ draft: SavedIssueDraftModel) {
        db.collection("issueDrafts").document(draft.id).delete()
    }

    func deleteIssueDraft(id: String) {
        db.collection("issueDrafts").document(id).delete()
    }
    
    func loadStoredImages(
        paths: [String],
        completion: @escaping ([String]) -> Void
    ) {
        guard Auth.auth().currentUser?.uid != nil else {
            print("BLOCKED_QUERY_NO_AUTH", "loadStoredImages")
            completion([])
            return
        }

        guard !paths.isEmpty else {
            completion([])
            return
        }
        
        var values = Array(repeating: "", count: paths.count)
        let group = DispatchGroup()
        
        for (index, path) in paths.enumerated() {
            group.enter()
            storage.reference(withPath: path).getData(maxSize: 12 * 1024 * 1024) { data, _ in
                guard Auth.auth().currentUser?.uid != nil else {
                    print("BLOCKED_QUERY_NO_AUTH", "loadStoredImages completion", path)
                    group.leave()
                    return
                }

                if let data {
                    values[index] = data.base64EncodedString()
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            completion(values.filter { !$0.isEmpty })
        }
    }

    func loadStoredImage(
        path: String,
        completion: @escaping (String?) -> Void
    ) {
        guard Auth.auth().currentUser?.uid != nil else {
            print("BLOCKED_QUERY_NO_AUTH", "loadStoredImage", path)
            completion(nil)
            return
        }

        guard !path.isEmpty else {
            completion(nil)
            return
        }

        storage.reference(withPath: path).getData(maxSize: 12 * 1024 * 1024) { data, _ in
            guard Auth.auth().currentUser?.uid != nil else {
                print("BLOCKED_QUERY_NO_AUTH", "loadStoredImage completion", path)
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            DispatchQueue.main.async {
                completion(data?.base64EncodedString())
            }
        }
    }

    func loadStoredUIImage(
        path: String,
        maxPixelSize: CGFloat = 850,
        completion: @escaping (UIImage?) -> Void
    ) {
        guard Auth.auth().currentUser?.uid != nil else {
            print("BLOCKED_QUERY_NO_AUTH", "loadStoredUIImage", path)
            completion(nil)
            return
        }

        guard !path.isEmpty else {
            completion(nil)
            return
        }

        storage.reference(withPath: path).getData(maxSize: 10 * 1024 * 1024) { data, error in
            if let error {
                print("STORED_IMAGE_LOAD_FAILED", path, error.localizedDescription)
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            guard let data else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let image = downsampledImageFromData(data, maxPixelSize: maxPixelSize)
                DispatchQueue.main.async {
                    completion(image)
                }
            }
        }
    }

    func uploadMagazineImages(
        in pages: [MagazinePage],
        basePath: String,
        completion: @escaping (Result<[MagazinePage], Error>) -> Void
    ) {
        guard Auth.auth().currentUser?.uid != nil else {
            completion(.failure(makeStorageError("No logged-in user.")))
            return
        }

        let startUploads = {
        DispatchQueue.global(qos: .userInitiated).async {
            var preparedPages = pages
            var uploadItems: [(pageIndex: Int, elementIndex: Int, path: String, data: Data?, sourcePath: String?)] = []

            for pageIndex in preparedPages.indices {
                for elementIndex in preparedPages[pageIndex].elements.indices {
                    guard case .image = preparedPages[pageIndex].elements[elementIndex].type else { continue }

                    if let existingPath = preparedPages[pageIndex].elements[elementIndex].imageStoragePath, !existingPath.isEmpty {
                        if existingPath.hasPrefix(basePath + "/") {
                            preparedPages[pageIndex].elements[elementIndex].imageData = nil
                            continue
                        }
                        let elementID = preparedPages[pageIndex].elements[elementIndex].id.uuidString
                        let path = "\(basePath)/page-\(pageIndex)-element-\(elementID).jpg"
                        uploadItems.append((pageIndex, elementIndex, path, nil, existingPath))
                        continue
                    }

                    let data: Data?
                    if let image = preparedPages[pageIndex].elements[elementIndex].image {
                        data = compressedImageData(from: image, maxSize: 1200, quality: 0.56, targetMaxBytes: 500_000)
                    } else if let localPath = preparedPages[pageIndex].elements[elementIndex].localImagePath,
                              !localPath.isEmpty {
                        if let image = downsampledImageFromFile(path: localPath, maxPixelSize: 1200) {
                            data = compressedImageData(from: image, maxSize: 1200, quality: 0.56, targetMaxBytes: 500_000)
                        } else {
                            data = nil
                        }
                    } else if let imageData = preparedPages[pageIndex].elements[elementIndex].imageData, !imageData.isEmpty {
                        if let image = downsampledImageFromBase64(imageData, maxPixelSize: 1200) {
                            data = compressedImageData(from: image, maxSize: 1200, quality: 0.56, targetMaxBytes: 500_000)
                        } else {
                            data = nil
                        }
                    } else {
                        data = nil
                    }

                    guard let data else { continue }
                    let elementID = preparedPages[pageIndex].elements[elementIndex].id.uuidString
                    let path = "\(basePath)/page-\(pageIndex)-element-\(elementID).jpg"
                    uploadItems.append((pageIndex, elementIndex, path, data, nil))
                }
            }

            DispatchQueue.main.async {
                guard !uploadItems.isEmpty else {
                    completion(.success(preparedPages))
                    return
                }

                print("MAGAZINE_IMAGE_UPLOAD_START count", uploadItems.count, "basePath", basePath)
                var firstError: Error?
                let group = DispatchGroup()

                var uploadedPaths: [String] = []
                let lock = NSLock()
                for item in uploadItems {
                    group.enter()
                    let start = CFAbsoluteTimeGetCurrent()
                    let uploadPreparedData: (Data?) -> Void = { sourceData in
                        let privacySafeData: Data?
                        if item.sourcePath != nil, let sourceData,
                           let image = downsampledImageFromData(sourceData, maxPixelSize: 1200) {
                            privacySafeData = compressedImageData(from: image, maxSize: 1200, quality: 0.56, targetMaxBytes: 500_000)
                        } else {
                            privacySafeData = sourceData
                        }
                        guard let privacySafeData else {
                            lock.lock(); if firstError == nil { firstError = self.makeStorageError("Could not prepare published image.") }; lock.unlock()
                            group.leave()
                            return
                        }
                        self.uploadData(privacySafeData, path: item.path, contentType: "image/jpeg") { result in
                        switch result {
                        case .failure(let error):
                            lock.lock(); if firstError == nil { firstError = error }; lock.unlock()
                        case .success(let path):
                            lock.lock(); uploadedPaths.append(path); lock.unlock()
                            preparedPages[item.pageIndex].elements[item.elementIndex].imageStoragePath = path
                            preparedPages[item.pageIndex].elements[item.elementIndex].imageData = nil
                            let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                            print("MAGAZINE_IMAGE_UPLOAD_SUCCESS", path, "bytes", privacySafeData.count, "elapsedMs", elapsed)
                        }
                        group.leave()
                        }
                    }
                    if let sourcePath = item.sourcePath {
                        self.storage.reference(withPath: sourcePath).getData(maxSize: 10 * 1024 * 1024) { data, error in
                            if let error {
                                lock.lock(); if firstError == nil { firstError = error }; lock.unlock()
                                group.leave()
                            } else {
                                uploadPreparedData(data)
                            }
                        }
                    } else {
                        uploadPreparedData(item.data)
                    }
                }

                group.notify(queue: .main) {
                    if let firstError {
                        self.deleteStorageObjects(paths: uploadedPaths)
                        if let issueID = self.publishedIssueID(from: basePath) {
                            self.rollbackPublishedUpload(issueID: issueID)
                        }
                        completion(.failure(firstError))
                    } else {
                        completion(.success(preparedPages))
                    }
                }
            }
        }
        }

        if let issueID = publishedIssueID(from: basePath) {
            beginPublishedUploadSession(issueID: issueID) { error in
                if let error { completion(.failure(error)) } else { startUploads() }
            }
        } else {
            startUploads()
        }
    }

    private func publishedIssueID(from basePath: String) -> String? {
        let parts = basePath.split(separator: "/")
        guard parts.count >= 3, parts[0] == "publishedIssues" else { return nil }
        return String(parts[1])
    }

    private func beginPublishedUploadSession(issueID: String, completion: @escaping (Error?) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(makeStorageError("No logged-in user.")); return
        }
        db.collection("issueUploadSessions").document(issueID).setData([
            "issueID": issueID,
            "ownerID": uid,
            "createdAt": FieldValue.serverTimestamp(),
            "expiresAt": Timestamp(date: Date().addingTimeInterval(60 * 60))
        ], merge: true, completion: completion)
    }

    private func closePublishedUploadSession(issueID: String) {
        db.collection("issueUploadSessions").document(issueID).delete()
    }

    private func rollbackPublishedUpload(issueID: String) {
        closePublishedUploadSession(issueID: issueID)
    }

    private func deleteStorageObjects(paths: [String]) {
        for path in Set(paths) { storage.reference(withPath: path).delete(completion: nil) }
    }
    
    func loadStoredString(
        path: String?,
        completion: @escaping (String?) -> Void
    ) {
        guard Auth.auth().currentUser?.uid != nil else {
            print("BLOCKED_QUERY_NO_AUTH", "loadStoredString", path ?? "")
            completion(nil)
            return
        }

        guard let path, !path.isEmpty else {
            print("STORED_DRAFT_JSON_LOAD_SKIPPED empty path")
            completion(nil)
            return
        }
        
        print("STORED_DRAFT_JSON_LOAD_START", path)
        let start = CFAbsoluteTimeGetCurrent()
        storage.reference(withPath: path).getData(maxSize: 50 * 1024 * 1024) { data, error in
            guard Auth.auth().currentUser?.uid != nil else {
                print("BLOCKED_QUERY_NO_AUTH", "loadStoredString completion", path)
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            if let error {
                print("STORED_DRAFT_JSON_LOAD_FAILED", path, error.localizedDescription)
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            guard let data,
                  let value = String(data: data, encoding: .utf8),
                  !value.isEmpty else {
                print("STORED_DRAFT_JSON_LOAD_FAILED", path, "empty or invalid utf8 data")
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            print("STORED_DRAFT_JSON_LOAD_SUCCESS", path, "length", value.count, "elapsedMs", elapsed)
            DispatchQueue.main.async {
                completion(value)
            }
        }
    }
    
    private func uploadDraftDataIfNeeded(
        _ value: String?,
        path: String,
        completion: @escaping (Result<String?, Error>) -> Void
    ) {
        guard let value, !value.isEmpty else {
            completion(.success(nil))
            return
        }
        
        guard let data = value.data(using: .utf8) else {
            completion(.failure(makeStorageError("Could not encode draft data for upload.")))
            return
        }
        
        uploadData(data, path: path, contentType: "application/json") { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let path):
                completion(.success(path))
            }
        }
    }
    
    private func uploadBase64Images(
        _ values: [String],
        basePath: String,
        filePrefix: String,
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        guard !values.isEmpty else {
            completion(.success([]))
            return
        }
        
        let imageData: [Data]
        do {
            imageData = try values.enumerated().map { index, value in
                guard let data = base64Data(from: value) else {
                    throw makeStorageError("Could not decode image data for \(basePath)/\(filePrefix)-\(index).jpg.")
                }
                return data
            }
        } catch {
            completion(.failure(error))
            return
        }
        
        var paths = Array(repeating: "", count: values.count)
        var firstError: Error?
        let group = DispatchGroup()
        
        for (index, data) in imageData.enumerated() {
            let path = "\(basePath)/\(filePrefix)-\(index).jpg"
            group.enter()
            uploadData(data, path: path, contentType: "image/jpeg") { result in
                switch result {
                case .failure(let error):
                    if firstError == nil {
                        firstError = error
                    }
                case .success(let path):
                    paths[index] = path
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            if let firstError {
                completion(.failure(firstError))
            } else {
                completion(.success(paths))
            }
        }
    }
    
    private func uploadData(
        _ data: Data,
        path: String,
        contentType: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let metadata = StorageMetadata()
        metadata.contentType = contentType
        
        storage.reference(withPath: path).putData(data, metadata: metadata) { _, error in
            DispatchQueue.main.async {
                if let error {
                    print("UPLOAD FAILED:", path, error.localizedDescription)
                    completion(.failure(error))
                } else {
                    completion(.success(path))
                }
            }
        }
    }
    
    private func base64Data(from value: String) -> Data? {
        guard Auth.auth().currentUser?.uid != nil else {
            print("BLOCKED_QUERY_NO_AUTH", "base64Data")
            return nil
        }

        let cleanValue: String
        if let commaIndex = value.firstIndex(of: ",") {
            cleanValue = String(value[value.index(after: commaIndex)...])
        } else {
            cleanValue = value
        }
        
        return Data(base64Encoded: cleanValue)
    }
    
    private func makeStorageError(_ message: String) -> NSError {
        NSError(
            domain: "PenPal.Storage",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
    
    func deleteMyAccount(completion: @escaping (String?) -> Void) {
        guard Auth.auth().currentUser != nil else {
            completion("No logged-in user.")
            return
        }

        AuthEventTracker.record("DELETE_ACCOUNT_CALLED FirestoreManager")
        Task {
            do {
                try await CommerceBackendClient.shared.deleteMyAccountData()
                await MainActor.run {
                    try? Auth.auth().signOut()
                    completion(nil)
                }
            } catch {
                await MainActor.run { completion(error.localizedDescription) }
            }
        }
    }
}
