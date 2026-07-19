//
//  FriendRequestsView.swift
//  TravelingFriends
//
//  Created by Emily on 24/05/2026.
//

import SwiftUI

struct FriendRequestsView: View {
    
    let friendRequests: [FriendRequestModel]
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                
                ForEach(friendRequests) { request in
                    
                    VStack(alignment: .leading, spacing: 14) {
                        
                        Text(request.fromDisplayName)
                            .font(.headline)
                        
                        Text("@\(request.fromUsername)")
                            .foregroundStyle(.secondary)
                        
                        HStack {
                            
                            Button(appText("Accept", languageRaw)) {
                                FirestoreManager.shared.acceptFriendRequest(request)

                                FirestoreManager.shared.fetchMyFriends { friends in
                                    DispatchQueue.main.async {
                                        FriendsStore.shared.friends = friends
                                    }
                                }
                            }
                            
                            Button(appText("Decline", languageRaw)) {
                                FirestoreManager.shared.declineFriendRequest(request)
                            }
                            .foregroundStyle(.red)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }
            }
            .padding()
        }
        .background(PenPalStyle.background.ignoresSafeArea())
        .navigationTitle(appText("Friend Requests", languageRaw))
    }
}
