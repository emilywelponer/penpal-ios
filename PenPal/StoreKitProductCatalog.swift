import Foundation

// MARK: Monetization Foundation

enum PenPalProductIdentifier: String, CaseIterable, Codable, Hashable, Sendable {
    case founderSupporter = "com.emily.penpal.founder"
    case premiumMonthly = "com.emily.penpal.premium.monthly"
    case premiumAnnual = "com.emily.penpal.premium.annual"

    var entitlement: PenPalPaidEntitlementKind {
        switch self {
        case .founderSupporter:
            return .founderSupporter
        case .premiumMonthly, .premiumAnnual:
            return .premium
        }
    }
}

enum PenPalPaidEntitlementKind: String, Codable, Hashable, Sendable {
    case premium
    case founderSupporter
}

enum PenPalStoreKitProductCatalog {
    static let bundleIdentifier = "com.emily.penpal"
    static let premiumSubscriptionGroupName = "PenPal Premium"

    static let founderProductID = PenPalProductIdentifier.founderSupporter.rawValue
    static let premiumMonthlyProductID = PenPalProductIdentifier.premiumMonthly.rawValue
    static let premiumAnnualProductID = PenPalProductIdentifier.premiumAnnual.rawValue

    static let allProductIDs: Set<String> = Set(PenPalProductIdentifier.allCases.map(\.rawValue))
    static let premiumProductIDs: Set<String> = [
        PenPalProductIdentifier.premiumMonthly.rawValue,
        PenPalProductIdentifier.premiumAnnual.rawValue
    ]

    static func productIdentifier(for rawValue: String) -> PenPalProductIdentifier? {
        PenPalProductIdentifier(rawValue: rawValue)
    }

    static func isKnownProductID(_ productID: String) -> Bool {
        allProductIDs.contains(productID)
    }

    static func isPremiumProductID(_ productID: String) -> Bool {
        premiumProductIDs.contains(productID)
    }
}
