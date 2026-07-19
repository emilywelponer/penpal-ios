//
//  FriendsStore.swift
//  TravelingFriends
//
//  Created by Emily on 27/05/2026.
//

import Foundation
import Combine

final class FriendsStore: ObservableObject {
    static let shared = FriendsStore()
    @Published var friends: [PenpalProfile] = []
    private init() {}
}
