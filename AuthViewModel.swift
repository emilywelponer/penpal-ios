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
        }
    }
    
    func logIn(email: String, password: String) {
        Auth.auth().signIn(withEmail: email, password: password) { _, error in
            if let error = error {
                self.errorMessage = error.localizedDescription
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
            try Auth.auth().signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
