//
//  SettingsView.swift
//  TravelingFriends
//

import SwiftUI
import FirebaseAuth

struct SettingsView: View {
    
    @AppStorage("email") private var email: String = ""
    @AppStorage("username") private var username: String = ""
    @AppStorage("displayName") private var displayName: String = ""
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    @AppStorage("homeResetID") private var homeResetID: String = UUID().uuidString
    
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String = ""
    @State private var isDeletingAccount = false
    @State private var showReauthSheet = false
    @State private var confirmPassword = ""
    @State private var reauthErrorMessage = ""
    @State private var showConfirmPassword = false
    
    var selectedLanguage: Binding<AppLanguage> {
        Binding(
            get: { AppLanguage(rawValue: languageRaw) ?? .english },
            set: {
                languageRaw = $0.rawValue
                PushNotificationManager.shared.refreshAndSaveToken()
            }
        )
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                
                Text(appText("Settings", languageRaw))
                    .font(.system(size: 38, weight: .light, design: .serif))
                
                VStack(spacing: 14) {
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
                }
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
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
            .padding()
        }
        .background(PenPalStyle.background.ignoresSafeArea())
        .confirmationDialog(
            appText("Delete profile permanently?", languageRaw),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(appText("Delete everything", languageRaw), role: .destructive) {
                deleteProfile()
            }
            
            Button(appText("Cancel", languageRaw), role: .cancel) {}
        } message: {
            Text(appText("This deletes your account, profile, drafts, published issues, friend connections and groups you own.", languageRaw))
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
    
    private func reauthenticateAndDelete() {
        
        guard let user = Auth.auth().currentUser,
              let email = user.email else {
            return
        }
        
        isDeletingAccount = true
        reauthErrorMessage = ""
        
        let credential = EmailAuthProvider.credential(
            withEmail: email,
            password: confirmPassword
        )
        
        AuthEventTracker.record("REAUTH_CALLED Settings delete account")
        user.reauthenticate(with: credential) { _, error in

            if let nsError = error as NSError? {

                isDeletingAccount = false

                switch nsError.code {

                case AuthErrorCode.wrongPassword.rawValue:
                    reauthErrorMessage = appText("Incorrect password.", languageRaw)

                case AuthErrorCode.invalidCredential.rawValue:
                    reauthErrorMessage = appText("Incorrect password.", languageRaw)

                case AuthErrorCode.userMismatch.rawValue:
                    reauthErrorMessage = appText("Incorrect password.", languageRaw)

                default:
                    errorMessage = nsError.localizedDescription
                }

                return
            }

            AuthEventTracker.record("DELETE_ACCOUNT_CALLED Settings")
            PushNotificationManager.shared.deleteCurrentTokenForLogout()
            FirestoreManager.shared.deleteMyAccount { error in

                isDeletingAccount = false

                if let error = error {
                    errorMessage = error
                    return
                }

                UserDefaults.standard.set(false, forKey: "isLoggedIn")
                UserDefaults.standard.removeObject(forKey: "currentUserID")
                FirestoreManager.shared.removeAllListeners(reason: "Settings delete account")
                self.email = ""
                username = ""
                displayName = ""

                PenpalGroupStore.shared.clear()
                FriendsStore.shared.friends.removeAll()
                MagazineArchiveStore.shared.savedIssues.removeAll()
                IssueDraftStore.shared.pages.removeAll()

                homeResetID = UUID().uuidString
            }
        }
    }
    
    private func signOut() {
        do {
            AuthEventTracker.record("SIGN_OUT_CALLED Settings")
            PushNotificationManager.shared.deleteCurrentTokenForLogout()
            UserDefaults.standard.set(false, forKey: "isLoggedIn")
            UserDefaults.standard.removeObject(forKey: "currentUserID")
            FirestoreManager.shared.removeAllListeners(reason: "Settings signOut")
            try Auth.auth().signOut()
            PenpalGroupStore.shared.clear()
            FriendsStore.shared.friends.removeAll()
            MagazineArchiveStore.shared.savedIssues.removeAll()
            IssueDraftStore.shared.pages.removeAll()
            homeResetID = UUID().uuidString
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cleanResetAuthState() {
        do {
            AuthEventTracker.record("SIGN_OUT_CALLED Settings debug reset")
            PushNotificationManager.shared.deleteCurrentTokenForLogout()
            FirestoreManager.shared.removeAllListeners(reason: "Settings debug reset auth state")
            try Auth.auth().signOut()
        } catch {
            errorMessage = error.localizedDescription
        }

        UserDefaults.standard.set(false, forKey: "isLoggedIn")
        UserDefaults.standard.removeObject(forKey: "currentUserID")
        UserDefaults.standard.removeObject(forKey: "email")
        UserDefaults.standard.removeObject(forKey: "username")
        UserDefaults.standard.removeObject(forKey: "displayName")
        email = ""
        username = ""
        displayName = ""

        PenpalGroupStore.shared.clear()
        FriendsStore.shared.friends.removeAll()
        MagazineArchiveStore.shared.savedIssues.removeAll()
        IssueDraftStore.shared.pages.removeAll()

        logAuthDiagnostics("debug reset auth state")
        homeResetID = UUID().uuidString
    }
    
    private func deleteProfile() {
        isDeletingAccount = true
        errorMessage = ""
        
        FirestoreManager.shared.deleteMyAccount { error in
            isDeletingAccount = false
            
            if let error = error {
                errorMessage = error
                return
            }
            
            UserDefaults.standard.set(false, forKey: "isLoggedIn")
            UserDefaults.standard.removeObject(forKey: "currentUserID")
            FirestoreManager.shared.removeAllListeners(reason: "Settings delete profile")
            email = ""
            username = ""
            displayName = ""
            
            IssueDraftStore.shared.pages.removeAll()
            MagazineArchiveStore.shared.savedIssues.removeAll()
            PenpalGroupStore.shared.clear()
            
            homeResetID = UUID().uuidString
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .frame(width: 34, height: 34)
                .background(Color.black.opacity(0.08))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}
