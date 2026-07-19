//
//  GroupModel.swift
//  TravelingFriends
//
//  Created by Emily on 17/05/2026.
//
import Foundation

struct GroupModel: Identifiable {

    var id: String
    var name: String

    var ownerID: String
    var memberIDs: [String]

    var createdAt: Date

    var issues: [SavedMagazineIssue] = []
    
    var imageData: String?
    var publishingDay: Int?
    var reminderEnabled: Bool = false
    var reminderDay: Int = 15
    var reminderHour: Int = 19
    var reminderMinute: Int = 0
}
