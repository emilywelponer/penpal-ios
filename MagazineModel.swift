//
//  MagazineModel.swift
//  TravelingFriends
//
//  Created by Emily on 17/05/2026.
//

import Foundation

struct CloudMagazineIssue: Identifiable, Codable {
    var id: String
    var title: String
    var ownerID: String
    var groupIDs: [String]
    var createdAt: Date
}
