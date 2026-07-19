//
//  Untitled.swift
//  TravelingFriends
//
//  Created by Emily on 26/05/2026.
//

import Foundation

struct SavedIssueDraftModel: Identifiable {
    var id: String
    var title: String
    var ownerID: String
    var createdAt: Date
    var pageImageData: [String]
    var previewImagePaths: [String] = []
    var pageDraftData: String?
    var pageDraftDataPath: String?
    var updatedAt: Date?
    var colourSchemeRaw: String?
    var isLocalDraft: Bool = false
    var localDraftID: String?
    var previewLocalImagePath: String?
}
