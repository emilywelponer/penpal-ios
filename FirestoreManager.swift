//
//  FirestoreManager.swift
//  TravelingFriends
//
//  Created by Emily on 17/05/2026.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

final class FirestoreManager {
    
    static let shared = FirestoreManager()
    private let db = Firestore.firestore()
    
    private init() {}
    
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
            "createdAt": Timestamp(date: Date())
        ]
        
        db.collection("users").document(uid).setData(data)
    }
    
    func createGroup(name: String, completion: @escaping (Bool) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(false)
            return
        }
        
        let groupID = UUID().uuidString
        
        let data: [String: Any] = [
            "id": groupID,
            "name": name,
            "ownerID": uid,
            "memberIDs": [uid],
            "createdAt": Timestamp(date: Date())
        ]
        
        db.collection("groups").document(groupID).setData(data) { error in
            completion(error == nil)
        }
    }
    
    func saveMagazine(
        title: String,
        groupIDs: [String],
        completion: @escaping (Bool) -> Void
    ) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(false)
            return
        }
        
        let magazineID = UUID().uuidString
        
        let data: [String: Any] = [
            "id": magazineID,
            "title": title,
            "ownerID": uid,
            "groupIDs": groupIDs,
            "createdAt": Timestamp(date: Date())
        ]
        
        db.collection("magazines").document(magazineID).setData(data) { error in
            completion(error == nil)
        }
    }
}

