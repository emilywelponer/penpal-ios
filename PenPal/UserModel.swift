//
//  UserModel.swift
//  TravelingFriends
//
//  Created by Emily on 17/05/2026.
//

import Foundation

struct PenpalUser: Identifiable, Codable {
    var id: String
    var username: String
    var displayName: String
    var email: String
    var createdAt: Date
}
