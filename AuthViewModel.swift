//
//  AuthViewModel.swift
//  TravelingFriends
//
//  Created by Emily on 17/05/2026.
//

import Foundation
import Combine
import FirebaseAuth

final class AuthViewModel: ObservableObject {
    
    @Published var user: User? = Auth.auth().currentUser
    @Published var errorMessage: String = ""
    
    init() {
        _ = Auth.auth().addStateDidChangeListener { _, user in
            print("AUTH_STATE_CHANGED", user?.uid ?? "nil")
            logAuthDiagnostics("AuthViewModel auth state changed")
            FirestoreManager.shared.authStateChanged(user: user)
            if user == nil {
                print("AUTH_STATE_CHANGED_RECENT_ACTION", AuthEventTracker.recentActionSummary())
                print("AUTH_FORCE_LOGOUT", "AuthViewModel auth state nil")
                Task { @MainActor in
                    StoreKitPurchaseService.shared.resetForLogout()
                }
                UserDefaults.standard.set(false, forKey: "isLoggedIn")
                UserDefaults.standard.removeObject(forKey: "currentUserID")
                FirestoreManager.shared.removeAllListeners(reason: "AuthViewModel auth state nil")
                PenpalGroupStore.shared.clear()
                FriendsNewsStore.shared.clear()
                FriendsStore.shared.friends.removeAll()
                MagazineArchiveStore.shared.savedIssues.removeAll()
                IssueDraftStore.shared.pages.removeAll()
            }
            self.user = user
        }
    }
    
    func signUp(
        email: String,
        password: String,
        username: String,
        displayName: String
    ) {
        Auth.auth().createUser(withEmail: email, password: password) { result, error in
            
            if let error = error {
                self.errorMessage = error.localizedDescription
                return
            }
            
            guard let user = result?.user else { return }
            
            let changeRequest = user.createProfileChangeRequest()
            changeRequest.displayName = displayName
            changeRequest.commitChanges()
            
            FirestoreManager.shared.createUserProfile(
                uid: user.uid,
                username: username,
                displayName: displayName,
                email: email
            )
            AuthEventTracker.record("LOGIN_SUCCESS signup \(user.uid)")
            PushNotificationManager.shared.refreshAndSaveToken()
            logAuthDiagnostics("AuthViewModel signup success")
        }
    }
    
    func logIn(email: String, password: String) {
        Auth.auth().signIn(withEmail: email, password: password) { _, error in
            if let error = error {
                self.errorMessage = error.localizedDescription
            } else {
                if let uid = Auth.auth().currentUser?.uid {
                    AuthEventTracker.record("LOGIN_SUCCESS \(uid)")
                }
                PushNotificationManager.shared.refreshAndSaveToken()
                logAuthDiagnostics("AuthViewModel login success")
            }
        }
    }
    
    func resetPassword(email: String) {
        Auth.auth().sendPasswordReset(withEmail: email) { error in
            if let error = error {
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    func signOut() {
        do {
            AuthEventTracker.record("SIGN_OUT_CALLED AuthViewModel")
            PushNotificationManager.shared.deleteCurrentTokenForLogout()
            Task { @MainActor in
                StoreKitPurchaseService.shared.resetForLogout()
            }
            UserDefaults.standard.set(false, forKey: "isLoggedIn")
            UserDefaults.standard.removeObject(forKey: "currentUserID")
            FirestoreManager.shared.removeAllListeners(reason: "AuthViewModel signOut")
            try Auth.auth().signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
