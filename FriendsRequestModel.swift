//
//  FriendsRequestModel.swift
//  TravelingFriends
//
//  Created by Emily on 22/05/2026.
//

import Foundation

struct FriendRequestModel: Identifiable {
    var id: String
    var fromUserID: String
    var fromUsername: String
    var fromDisplayName: String
    var toUserID: String
    var toUsername: String?
    var status: String
    var createdAt: Date
}
