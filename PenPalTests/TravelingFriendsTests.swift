//
//  TravelingFriendsTests.swift
//  TravelingFriendsTests
//
//  Created by Emily on 15/05/2026.
//

import Testing
import FirebaseFirestore
@testable import TravelingFriends

struct TravelingFriendsTests {

    @Test func marginNoteNotificationRouteParsesValidPayload() async throws {
        let route = MarginNoteNotificationRoute(userInfo: [
            "type": "margin_note_published",
            "magazineID": "magazine-1",
            "marginNoteID": "note-1",
            "pageIndex": "3"
        ])

        #expect(route?.magazineID == "magazine-1")
        #expect(route?.marginNoteID == "note-1")
        #expect(route?.pageIndex == 3)
    }

    @Test func marginNoteNotificationRouteRejectsWrongType() async throws {
        let route = MarginNoteNotificationRoute(userInfo: [
            "type": "newIssue",
            "magazineID": "magazine-1",
            "marginNoteID": "note-1"
        ])

        #expect(route == nil)
    }

    @Test func marginNoteNotificationRouteRequiresIdentifiers() async throws {
        let route = MarginNoteNotificationRoute(userInfo: [
            "type": "margin_note_published",
            "magazineID": "magazine-1"
        ])

        #expect(route == nil)
    }

    @Test func penPalLabCategoryValuesAreStable() async throws {
        #expect(PenPalLabCategory.feature.rawValue == "feature")
        #expect(PenPalLabCategory.design.rawValue == "design")
        #expect(PenPalLabCategory.magazinePage.rawValue == "magazine_page")
        #expect(PenPalLabCategory.bug.rawValue == "bug")
        #expect(PenPalLabCategory.other.rawValue == "other")
    }

    @Test func penPalLabRoadmapOnlyShowsRoadmapStatuses() async throws {
        let suggestions = [
            makeLabSuggestion(id: "planned", status: .planned, votes: 1),
            makeLabSuggestion(id: "progress", status: .inProgress, votes: 3),
            makeLabSuggestion(id: "released", status: .released, votes: 2),
            makeLabSuggestion(id: "review", status: .underReview, votes: 10),
            makeLabSuggestion(id: "not-planned", status: .notPlanned, votes: 4)
        ].compactMap { $0 }

        let groups = PenPalLabRoadmap.grouped(suggestions)

        #expect(groups.map(\.0) == [.planned, .inProgress, .released])
        #expect(groups.flatMap(\.1).map(\.status).allSatisfy { [.planned, .inProgress, .released].contains($0) })
    }

    @Test func penPalLabSuggestionRejectsInvalidCategory() async throws {
        let suggestion = PenPalLabSuggestion(id: "bad", data: [
            "authorID": "user-1",
            "authorDisplayName": "Emily",
            "title": "Idea",
            "description": "Description",
            "category": "random",
            "status": PenPalLabStatus.underReview.rawValue,
            "isVisible": true,
            "createdAt": Timestamp(date: Date()),
            "updatedAt": Timestamp(date: Date()),
            "voteCount": 0
        ])

        #expect(suggestion == nil)
    }

    private func makeLabSuggestion(
        id: String,
        status: PenPalLabStatus,
        votes: Int
    ) -> PenPalLabSuggestion? {
        PenPalLabSuggestion(id: id, data: [
            "authorID": "user-1",
            "authorDisplayName": "Emily",
            "title": id,
            "description": "A suggestion",
            "category": PenPalLabCategory.feature.rawValue,
            "status": status.rawValue,
            "isVisible": true,
            "createdAt": Timestamp(date: Date()),
            "updatedAt": Timestamp(date: Date()),
            "voteCount": votes
        ])
    }
}
