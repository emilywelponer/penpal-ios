//
//  TravelingFriendsTests.swift
//  TravelingFriendsTests
//
//  Created by Emily on 15/05/2026.
//

import Testing
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
}
