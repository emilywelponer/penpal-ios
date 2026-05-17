//
//  GroupModel.swift
//  TravelingFriends
//
//  Created by Emily on 17/05/2026.
//

import Foundation

struct CloudPenpalGroup: Identifiable, Codable {
    var id: String
    var name: String
    var ownerID: String
    var memberIDs: [String]
    var createdAt: Date
}
