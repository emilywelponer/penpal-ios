//
//  PublishedIssueModel.swift
//  TravelingFriends
//
//  Created by Emily on 24/05/2026.
//

import Foundation

struct PublishedIssueModel: Identifiable, Hashable {
    var id: String
    var title: String
    var ownerID: String
    var createdAt: Date
    var month: Int
    var year: Int
    var groupIDs: [String]
    var groupNames: [String]
    var pageImageData: [String]
    var pageImagePaths: [String] = []
    var pageDraftData: String?
    var pageDraftDataPath: String?
    var viewedBy: [String] = []
    var colourSchemeRaw: String?

    static func == (lhs: PublishedIssueModel, rhs: PublishedIssueModel) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
