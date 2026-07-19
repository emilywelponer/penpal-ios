import Foundation
import FirebaseFirestore

// MARK: PenPal Lab Feature

enum PenPalLabConfiguration {
    static let restrictPenPalLabToFounders = false
}

enum PenPalLabCategory: String, CaseIterable, Identifiable {
    case feature
    case design
    case magazinePage = "magazine_page"
    case bug
    case other

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .feature: return "Feature"
        case .design: return "Design"
        case .magazinePage: return "Magazine page"
        case .bug: return "Bug"
        case .other: return "Other"
        }
    }
}

enum PenPalLabStatus: String, CaseIterable, Identifiable {
    case underReview = "under_review"
    case planned
    case inProgress = "in_progress"
    case released
    case notPlanned = "not_planned"

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .underReview: return "Under review"
        case .planned: return "Planned"
        case .inProgress: return "In progress"
        case .released: return "Released"
        case .notPlanned: return "Not planned"
        }
    }

    var isRoadmapVisible: Bool {
        switch self {
        case .planned, .inProgress, .released:
            return true
        case .underReview, .notPlanned:
            return false
        }
    }
}

struct PenPalLabSuggestion: Identifiable, Equatable {
    var id: String
    var authorID: String
    var authorDisplayName: String
    var title: String
    var description: String
    var category: PenPalLabCategory
    var status: PenPalLabStatus
    var isVisible: Bool
    var createdAt: Date
    var updatedAt: Date
    var voteCount: Int
    var currentUserHasVoted: Bool

    init?(
        id: String,
        data: [String: Any],
        currentUserHasVoted: Bool = false
    ) {
        guard
            let authorID = data["authorID"] as? String,
            let authorDisplayName = data["authorDisplayName"] as? String,
            let title = data["title"] as? String,
            let description = data["description"] as? String,
            let categoryRaw = data["category"] as? String,
            let category = PenPalLabCategory(rawValue: categoryRaw),
            let statusRaw = data["status"] as? String,
            let status = PenPalLabStatus(rawValue: statusRaw)
        else {
            return nil
        }

        self.id = id
        self.authorID = authorID
        self.authorDisplayName = authorDisplayName
        self.title = title
        self.description = description
        self.category = category
        self.status = status
        self.isVisible = data["isVisible"] as? Bool ?? true
        self.createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        self.updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? self.createdAt
        self.voteCount = max(0, data["voteCount"] as? Int ?? 0)
        self.currentUserHasVoted = currentUserHasVoted
    }
}

enum PenPalLabSortOption: String, CaseIterable, Identifiable {
    case mostSupported
    case newest

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .mostSupported: return "Most supported"
        case .newest: return "Newest"
        }
    }
}

enum PenPalLabRoadmap {
    static func grouped(_ suggestions: [PenPalLabSuggestion]) -> [(PenPalLabStatus, [PenPalLabSuggestion])] {
        [.planned, .inProgress, .released].map { status in
            (
                status,
                suggestions
                    .filter { $0.status == status && $0.isVisible }
                    .sorted {
                        if $0.voteCount == $1.voteCount {
                            return $0.createdAt > $1.createdAt
                        }
                        return $0.voteCount > $1.voteCount
                    }
            )
        }
    }
}
