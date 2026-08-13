import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: Monetization Foundation

enum BackendEntitlementLoadState: Equatable {
    case signedOut
    case loading
    case loaded
    case failed(String)
}

@MainActor
final class BackendEntitlementRepository: ObservableObject {
    static let shared = BackendEntitlementRepository()

    @Published private(set) var state: BackendEntitlementLoadState = .signedOut
    @Published private(set) var entitlements: PenPalUserEntitlements = .free
    @Published private(set) var appAccountToken: UUID?

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var observedUID: String?

    private init() {}

    var hasLoadedAuthoritativeEntitlement: Bool {
        if case .loaded = state { return true }
        return false
    }

    var isFounderSupporter: Bool {
        hasLoadedAuthoritativeEntitlement && entitlements.isFounderSupporter
    }

    var hasPremiumAccess: Bool {
        hasLoadedAuthoritativeEntitlement && entitlements.hasActivePremiumAccess
    }

    var currentPlan: PenPalPlan {
        if isFounderSupporter {
            return .founder
        }
        if hasPremiumAccess {
            return .premium
        }
        return .free
    }

    func startObservingCurrentUser() {
        guard let uid = Auth.auth().currentUser?.uid else {
            resetForLogout()
            return
        }

        guard observedUID != uid else { return }
        stopListening()
        observedUID = uid
        state = .loading
        entitlements = .free
        appAccountToken = nil

        listener = db.collection("users")
            .document(uid)
            .collection("privateEntitlements")
            .document("current")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }

                    if let error {
                        self.state = .failed(error.localizedDescription)
                        self.entitlements = .free
                        self.appAccountToken = nil
                        return
                    }

                    guard let data = snapshot?.data() else {
                        self.state = .loaded
                        self.entitlements = .free
                        self.appAccountToken = nil
                        return
                    }

                    self.entitlements = Self.entitlements(from: data)
                    if let tokenRaw = data["appAccountToken"] as? String {
                        self.appAccountToken = UUID(uuidString: tokenRaw)
                    } else {
                        self.appAccountToken = nil
                    }
                    self.state = .loaded
                }
            }
    }

    func ensureAppAccountToken() async throws -> UUID {
        if let appAccountToken {
            return appAccountToken
        }

        state = .loading
        let token = try await CommerceBackendClient.shared.getOrCreateAppAccountToken()
        appAccountToken = token
        startObservingCurrentUser()
        return token
    }

    func refreshFromBackend() {
        startObservingCurrentUser()
    }

    func resetForLogout() {
        stopListening()
        observedUID = nil
        state = .signedOut
        entitlements = .free
        appAccountToken = nil
    }

    private func stopListening() {
        listener?.remove()
        listener = nil
    }

    private static func entitlements(from data: [String: Any]) -> PenPalUserEntitlements {
        let membershipTier = PenPalMembershipTier(rawValue: data["membershipTier"] as? String ?? "") ?? .free
        let premiumStatus = PenPalPremiumStatus(rawValue: data["premiumStatus"] as? String ?? "") ?? .none

        return PenPalUserEntitlements(
            membershipTier: membershipTier,
            isFounderSupporter: data["isFounderSupporter"] as? Bool ?? false,
            premiumProductID: data["premiumProductID"] as? String,
            premiumExpirationDate: (data["premiumExpirationDate"] as? Timestamp)?.dateValue(),
            premiumWillRenew: data["premiumWillRenew"] as? Bool,
            premiumInGracePeriod: data["premiumInGracePeriod"] as? Bool ?? false,
            premiumInBillingRetry: data["premiumInBillingRetry"] as? Bool ?? false,
            premiumStatus: premiumStatus,
            founderPurchasedAt: (data["founderPurchasedAt"] as? Timestamp)?.dateValue(),
            founderRevokedAt: (data["founderRevokedAt"] as? Timestamp)?.dateValue(),
            lastVerifiedAt: (data["lastVerifiedAt"] as? Timestamp)?.dateValue()
        )
    }
}
