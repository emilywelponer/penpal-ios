//
//  FriendsListView.swift
//  TravelingFriends
//
//  Created by Emily on 27/05/2026.
//

import SwiftUI
import FirebaseAuth

struct FriendsListView: View {
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    @State private var friends: [PenpalProfile] = []
    @State private var friendToRemove: PenpalProfile?
    
    var body: some View {
        List {
            if friends.isEmpty {
                Text(appText("No friends yet.", languageRaw))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(friends) { friend in
                    UserMiniBannerCard(profile: friend)
                        .swipeActions {
                            Button(role: .destructive) {
                                friendToRemove = friend
                            } label: {
                                Label(appText("Remove", languageRaw), systemImage: "person.badge.minus")
                            }
                        }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(PenPalStyle.background.ignoresSafeArea())
        .navigationTitle(appText("My friends", languageRaw))
        .onAppear {
            guard Auth.auth().currentUser?.uid != nil else {
                print("BLOCKED_QUERY_NO_AUTH", "FriendsListView.onAppear")
                friends = []
                return
            }

            FirestoreManager.shared.fetchMyFriends { friends in
                self.friends = friends
            }
        }
        .alert(appText("Remove friend?", languageRaw), isPresented: Binding(
            get: { friendToRemove != nil },
            set: { if !$0 { friendToRemove = nil } }
        )) {
            Button(appText("Cancel", languageRaw), role: .cancel) {
                friendToRemove = nil
            }

            Button(appText("Remove", languageRaw), role: .destructive) {
                if let friend = friendToRemove {
                    FirestoreManager.shared.removeFriend(userID: friend.id)
                    friends.removeAll { $0.id == friend.id }
                }

                friendToRemove = nil
            }
        } message: {
            Text(appText("You will no longer be connected.", languageRaw))
        }
    }
}
