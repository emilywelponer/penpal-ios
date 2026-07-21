import Foundation

// MARK: Monetization Foundation

enum PenPalMembershipTier: String, Codable, Hashable, Sendable {
    case free
    case premium
}

enum PenPalPremiumStatus: String, Codable, Hashable, Sendable {
    case none
    case active
    case gracePeriod
    case billingRetry
    case expired
    case revoked
}

struct PenPalUserEntitlements: Codable, Equatable, Sendable {
    var membershipTier: PenPalMembershipTier
    var isFounderSupporter: Bool

    var premiumProductID: String?
    var premiumExpirationDate: Date?
    var premiumWillRenew: Bool?
    var premiumInGracePeriod: Bool
    var premiumInBillingRetry: Bool
    var premiumStatus: PenPalPremiumStatus

    var founderPurchasedAt: Date?
    var founderRevokedAt: Date?
    var lastVerifiedAt: Date?

    static let free = PenPalUserEntitlements(
        membershipTier: .free,
        isFounderSupporter: false,
        premiumProductID: nil,
        premiumExpirationDate: nil,
        premiumWillRenew: nil,
        premiumInGracePeriod: false,
        premiumInBillingRetry: false,
        premiumStatus: .none,
        founderPurchasedAt: nil,
        founderRevokedAt: nil,
        lastVerifiedAt: nil
    )

    var hasActivePremiumAccess: Bool {
        switch premiumStatus {
        case .active, .gracePeriod:
            return membershipTier == .premium
        case .none, .billingRetry, .expired, .revoked:
            return false
        }
    }
}

struct PenPalPrivateEntitlementDocument: Codable, Equatable, Sendable {
    var userID: String
    var entitlements: PenPalUserEntitlements
    var premiumOriginalTransactionID: String?
    var founderOriginalTransactionID: String?
    var appAccountToken: UUID?
    var environment: String?
    var updatedAt: Date?
}
