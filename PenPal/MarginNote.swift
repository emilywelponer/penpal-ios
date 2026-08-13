import Foundation
import FirebaseFirestore

// MARK: Margin Notes Feature

struct MarginNote: Identifiable, Hashable {
    var id: String
    var noteID: String
    var magazineID: String
    var pageIndex: Int
    var authorID: String
    var authorUsername: String
    var authorDisplayName: String
    var authorPhotoURL: String?
    var createdAt: Date
    var updatedAt: Date
    var text: String

    init(
        id: String,
        noteID: String,
        magazineID: String,
        pageIndex: Int,
        authorID: String,
        authorUsername: String,
        authorDisplayName: String,
        authorPhotoURL: String?,
        createdAt: Date,
        updatedAt: Date,
        text: String
    ) {
        self.id = id
        self.noteID = noteID
        self.magazineID = magazineID
        self.pageIndex = pageIndex
        self.authorID = authorID
        self.authorUsername = authorUsername
        self.authorDisplayName = authorDisplayName
        self.authorPhotoURL = authorPhotoURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.text = text
    }

    init?(documentID: String, data: [String: Any]) {
        guard
            let magazineID = data["magazineID"] as? String,
            let pageIndex = data["pageIndex"] as? Int,
            let authorID = data["authorID"] as? String,
            let text = data["text"] as? String
        else {
            return nil
        }

        self.id = documentID
        self.noteID = data["noteID"] as? String ?? documentID
        self.magazineID = magazineID
        self.pageIndex = pageIndex
        self.authorID = authorID
        self.authorUsername = data["authorUsername"] as? String ?? ""
        self.authorDisplayName = data["authorDisplayName"] as? String ?? self.authorUsername
        self.authorPhotoURL = data["authorPhotoURL"] as? String
        self.createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        self.updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? self.createdAt
        self.text = text
    }
}
