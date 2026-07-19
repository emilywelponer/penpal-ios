import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: PenPal Lab Feature

@MainActor
final class PenPalLabService: ObservableObject {
    static let shared = PenPalLabService()

    @Published private(set) var suggestions: [PenPalLabSuggestion] = []
    @Published private(set) var isLoading = false
    @Published private(set) var entitlementChecked = false
    @Published private(set) var currentUserIsFounder = false
    @Published var errorMessage = ""

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var voteListeners: [String: ListenerRegistration] = [:]

    private init() {}

    var canAccessLab: Bool {
        !PenPalLabConfiguration.restrictPenPalLabToFounders || currentUserIsFounder
    }

    func refreshEntitlement() {
        guard let uid = Auth.auth().currentUser?.uid else {
            entitlementChecked = true
            currentUserIsFounder = false
            suggestions = []
            stopListening()
            return
        }

        db.collection("users").document(uid).getDocument { [weak self] snapshot, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.entitlementChecked = true

                if let error {
                    self.currentUserIsFounder = false
                    self.errorMessage = error.localizedDescription
                    return
                }

                self.currentUserIsFounder = snapshot?.data()?["founderSupporter"] as? Bool ?? false
            }
        }
    }

    func startListening(sort: PenPalLabSortOption) {
        guard Auth.auth().currentUser?.uid != nil else {
            suggestions = []
            errorMessage = appText("You need to be logged in.", UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.english.rawValue)
            return
        }

        refreshEntitlement()
        guard canAccessLab else {
            suggestions = []
            return
        }

        isLoading = true
        errorMessage = ""
        stopSuggestionListenerOnly()

        let query: Query = db.collection("penpalLabSuggestions")
            .whereField("isVisible", isEqualTo: true)
            .order(by: "createdAt", descending: true)
            .limit(to: 50)

        listener = query.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false

                if let error {
                    self.suggestions = []
                    self.errorMessage = error.localizedDescription
                    return
                }

                let docs = snapshot?.documents ?? []
                let mapped = docs.compactMap { document in
                    PenPalLabSuggestion(
                        id: document.documentID,
                        data: document.data(),
                        currentUserHasVoted: self.suggestions.first(where: { existing in existing.id == document.documentID })?.currentUserHasVoted ?? false
                    )
                }
                self.suggestions = self.sorted(mapped, by: sort)
                self.syncVoteListeners()
            }
        }
    }

    func stopListening() {
        stopSuggestionListenerOnly()
        for listener in voteListeners.values {
            listener.remove()
        }
        voteListeners.removeAll()
    }

    func createSuggestion(
        title: String,
        description: String,
        category: PenPalLabCategory,
        completion: @escaping (String?) -> Void
    ) {
        guard let user = Auth.auth().currentUser else {
            completion(appText("You need to be logged in.", UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.english.rawValue))
            return
        }

        guard canAccessLab else {
            completion(appText("PenPal Lab is only available to Founder Supporters.", UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.english.rawValue))
            return
        }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanTitle.isEmpty else {
            completion(appText("Please add a title.", UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.english.rawValue))
            return
        }

        guard !cleanDescription.isEmpty else {
            completion(appText("Please add a description.", UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.english.rawValue))
            return
        }

        guard cleanTitle.count <= 100, cleanDescription.count <= 2000 else {
            completion(appText("Please keep your suggestion a little shorter.", UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.english.rawValue))
            return
        }

        let displayName = UserDefaults.standard.string(forKey: "displayName")
            ?? user.displayName
            ?? UserDefaults.standard.string(forKey: "username")
            ?? "PenPal user"

        let payload: [String: Any] = [
            "authorID": user.uid,
            "authorDisplayName": displayName,
            "title": cleanTitle,
            "description": cleanDescription,
            "category": category.rawValue,
            "status": PenPalLabStatus.underReview.rawValue,
            "isVisible": true,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "voteCount": 0
        ]

        db.collection("penpalLabSuggestions").addDocument(data: payload) { error in
            Task { @MainActor in
                completion(error.map { $0.localizedDescription })
            }
        }
    }

    func toggleVote(for suggestion: PenPalLabSuggestion) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard canAccessLab else { return }

        let voteRef = db.collection("penpalLabSuggestions")
            .document(suggestion.id)
            .collection("votes")
            .document(uid)

        if suggestion.currentUserHasVoted {
            voteRef.delete { [weak self] error in
                if let error {
                    Task { @MainActor [weak self] in
                        self?.errorMessage = error.localizedDescription
                    }
                }
            }
        } else {
            voteRef.setData([
                "userID": uid,
                "createdAt": FieldValue.serverTimestamp()
            ]) { [weak self] error in
                if let error {
                    Task { @MainActor [weak self] in
                        self?.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    private func stopSuggestionListenerOnly() {
        listener?.remove()
        listener = nil
    }

    private func syncVoteListeners() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let activeIDs = Set(suggestions.map(\.id))

        for (suggestionID, listener) in voteListeners where !activeIDs.contains(suggestionID) {
            listener.remove()
            voteListeners[suggestionID] = nil
        }

        for suggestion in suggestions where voteListeners[suggestion.id] == nil {
            voteListeners[suggestion.id] = db.collection("penpalLabSuggestions")
                .document(suggestion.id)
                .collection("votes")
                .document(uid)
                .addSnapshotListener { [weak self] snapshot, _ in
                    Task { @MainActor in
                        guard let self,
                              let index = self.suggestions.firstIndex(where: { $0.id == suggestion.id }) else { return }
                        self.suggestions[index].currentUserHasVoted = snapshot?.exists == true
                    }
                }
        }
    }

    private func sorted(_ suggestions: [PenPalLabSuggestion], by sort: PenPalLabSortOption) -> [PenPalLabSuggestion] {
        switch sort {
        case .mostSupported:
            return suggestions.sorted {
                if $0.voteCount == $1.voteCount {
                    return $0.createdAt > $1.createdAt
                }
                return $0.voteCount > $1.voteCount
            }
        case .newest:
            return suggestions.sorted { $0.createdAt > $1.createdAt }
        }
    }
}
