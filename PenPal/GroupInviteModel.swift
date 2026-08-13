//
//  GroupInviteModel.swift
//  TravelingFriends
//
//  Created by Emily on 22/05/2026.
//

import Foundation

struct GroupInviteModel: Identifiable {
    var id: String
    var groupID: String
    var groupName: String
    var fromUserID: String
    var fromDisplayName: String
    var toUserID: String
    var status: String
    var createdAt: Date
}
