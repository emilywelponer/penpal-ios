import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: Margin Notes Feature

final class MarginNotesService {
    static let shared = MarginNotesService()

    private let db = Firestore.firestore()
    private let collectionName = "MarginNotes"

    private init() {}

    func listen(
        magazineID: String,
        pageIndex: Int,
        completion: @escaping (Result<[MarginNote], Error>) -> Void
    ) -> ListenerRegistration? {
        guard Auth.auth().currentUser?.uid != nil else {
            completion(.success([]))
            return nil
        }

        return db.collection(collectionName)
            .whereField("magazineID", isEqualTo: magazineID)
            .whereField("pageIndex", isEqualTo: pageIndex)
            .addSnapshotListener { snapshot, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                let notes = snapshot?.documents
                    .compactMap { MarginNote(documentID: $0.documentID, data: $0.data()) }
                    .sorted { $0.updatedAt > $1.updatedAt } ?? []

                completion(.success(notes))
            }
    }

    func saveNote(
        magazineID: String,
        pageIndex: Int,
        text: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let user = Auth.auth().currentUser else {
            completion(.failure(MarginNotesError.missingAuth))
            return
        }

        let cleanText = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(250))
        guard !cleanText.isEmpty else {
            deleteOwnNote(magazineID: magazineID, pageIndex: pageIndex, completion: completion)
            return
        }

        let documentID = noteID(magazineID: magazineID, pageIndex: pageIndex, authorID: user.uid)
        let ref = db.collection(collectionName).document(documentID)

        ref.getDocument { snapshot, _ in
            let now = Date()
            let createdAt = (snapshot?.data()?["createdAt"] as? Timestamp)?.dateValue() ?? now
            let displayName = user.displayName?.isEmpty == false ? user.displayName! : (user.email ?? "PenPal")
            let username = UserDefaults.standard.string(forKey: "username") ?? displayName

            let payload: [String: Any] = [
                "noteID": documentID,
                "magazineID": magazineID,
                "pageIndex": pageIndex,
                "authorID": user.uid,
                "authorUsername": username,
                "authorDisplayName": displayName,
                "authorPhotoURL": "",
                "createdAt": Timestamp(date: createdAt),
                "updatedAt": Timestamp(date: now),
                "text": cleanText
            ]

            ref.setData(payload, merge: true) { error in
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    func deleteOwnNote(
        magazineID: String,
        pageIndex: Int,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(.failure(MarginNotesError.missingAuth))
            return
        }

        let documentID = noteID(magazineID: magazineID, pageIndex: pageIndex, authorID: uid)
        db.collection(collectionName).document(documentID).delete { error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    private func noteID(magazineID: String, pageIndex: Int, authorID: String) -> String {
        "\(magazineID)_\(pageIndex)_\(authorID)"
    }
}

enum MarginNotesError: LocalizedError {
    case missingAuth

    var errorDescription: String? {
        switch self {
        case .missingAuth:
            return "Please sign in to leave a margin note."
        }
    }
}
