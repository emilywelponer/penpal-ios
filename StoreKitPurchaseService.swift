import Foundation
import Combine
import StoreKit

// MARK: Monetization Foundation

enum StoreKitProductLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case unavailable(missingProductIDs: [String])
    case failed(message: String)
}

enum StoreKitPurchaseOutcome: Equatable, Sendable {
    case verifiedProcessed(VerifiedStoreTransaction)
    case backendProcessingFailed(VerifiedStoreTransaction, message: String)
    case unverified
    case pending
    case cancelled
    case failed(message: String)

    var grantsBackendEntitlement: Bool {
        false
    }
}

enum StoreKitPurchaseServiceError: Error, Equatable, LocalizedError, Sendable {
    case productUnavailable
    case accountTokenUnavailable
    case unverifiedTransaction

    var errorDescription: String? {
        switch self {
        case .productUnavailable:
            return "The selected PenPal product is not available right now."
        case .accountTokenUnavailable:
            return "Purchases are not available until secure account linking is configured."
        case .unverifiedTransaction:
            return "Apple could not verify this transaction."
        }
    }
}

enum PenPalAccountTokenState: Equatable, Sendable {
    case unavailableBackendRequired
    case available(UUID)
}

struct VerifiedStoreTransaction: Equatable, Identifiable, Sendable {
    var id: String { "\(transactionID)" }

    let transactionID: UInt64
    let originalTransactionID: UInt64
    let productID: String
    let productIdentifier: PenPalProductIdentifier?
    let purchaseDate: Date
    let expirationDate: Date?
    let revocationDate: Date?
    let isUpgraded: Bool

    init(
        transactionID: UInt64,
        originalTransactionID: UInt64,
        productID: String,
        purchaseDate: Date,
        expirationDate: Date?,
        revocationDate: Date?,
        isUpgraded: Bool
    ) {
        self.transactionID = transactionID
        self.originalTransactionID = originalTransactionID
        self.productID = productID
        self.productIdentifier = PenPalStoreKitProductCatalog.productIdentifier(for: productID)
        self.purchaseDate = purchaseDate
        self.expirationDate = expirationDate
        self.revocationDate = revocationDate
        self.isUpgraded = isUpgraded
    }

    init(transaction: Transaction) {
        self.init(
            transactionID: transaction.id,
            originalTransactionID: transaction.originalID,
            productID: transaction.productID,
            purchaseDate: transaction.purchaseDate,
            expirationDate: transaction.expirationDate,
            revocationDate: transaction.revocationDate,
            isUpgraded: transaction.isUpgraded
        )
    }

    func isActive(at date: Date = Date()) -> Bool {
        guard revocationDate == nil, !isUpgraded else { return false }

        if PenPalStoreKitProductCatalog.isPremiumProductID(productID) {
            guard let expirationDate else { return true }
            return expirationDate > date
        }

        return productID == PenPalStoreKitProductCatalog.founderProductID
    }
}

enum StoreKitTransactionVerificationState: Equatable, Sendable {
    case verified(VerifiedStoreTransaction)
    case unverified
}

enum StoreKitVerifiedTransactionMapper {
    static func transaction(from state: StoreKitTransactionVerificationState) -> VerifiedStoreTransaction? {
        switch state {
        case .verified(let transaction):
            return transaction
        case .unverified:
            return nil
        }
    }

    static func state(from result: VerificationResult<Transaction>) -> StoreKitTransactionVerificationState {
        switch result {
        case .verified(let transaction):
            return .verified(VerifiedStoreTransaction(transaction: transaction))
        case .unverified:
            return .unverified
        }
    }
}

struct StoreKitEntitlementSnapshot: Equatable, Sendable {
    let verifiedTransactions: [VerifiedStoreTransaction]
    let capturedAt: Date

    static let empty = StoreKitEntitlementSnapshot(verifiedTransactions: [], capturedAt: .distantPast)

    init(verifiedTransactions: [VerifiedStoreTransaction], capturedAt: Date = Date()) {
        self.verifiedTransactions = verifiedTransactions
        self.capturedAt = capturedAt
    }

    var activeProductIDs: Set<String> {
        Set(verifiedTransactions.filter { $0.isActive(at: capturedAt) }.map(\.productID))
    }

    var hasActiveFounderSupporterPurchase: Bool {
        activeProductIDs.contains(PenPalStoreKitProductCatalog.founderProductID)
    }

    var activePremiumProductID: String? {
        verifiedTransactions
            .filter { $0.isActive(at: capturedAt) && PenPalStoreKitProductCatalog.isPremiumProductID($0.productID) }
            .sorted { ($0.expirationDate ?? .distantFuture) > ($1.expirationDate ?? .distantFuture) }
            .first?
            .productID
    }

    var appleLocalMembershipTier: PenPalMembershipTier {
        activePremiumProductID == nil ? .free : .premium
    }
}

struct StoreKitSubscriptionStatusSnapshot: Equatable, Sendable {
    let productID: String
    let stateDescription: String
}

protocol PurchaseTransactionProcessor: Sendable {
    func process(_ transaction: Transaction, signedTransactionInfo: String) async throws
}

struct BackendPurchaseTransactionProcessor: PurchaseTransactionProcessor {
    nonisolated init() {}

    func process(_ transaction: Transaction, signedTransactionInfo: String) async throws {
        try await CommerceBackendClient.shared.processAppStoreTransaction(
            signedTransactionInfo: signedTransactionInfo
        )
    }
}

@MainActor
final class StoreKitPurchaseService: ObservableObject {
    static let shared = StoreKitPurchaseService()

    @Published private(set) var productLoadState: StoreKitProductLoadState = .idle
    @Published private(set) var productsByIdentifier: [PenPalProductIdentifier: Product] = [:]
    @Published private(set) var appleLocalSnapshot: StoreKitEntitlementSnapshot = .empty
    @Published private(set) var subscriptionStatuses: [StoreKitSubscriptionStatusSnapshot] = []
    @Published private(set) var lastPurchaseOutcome: StoreKitPurchaseOutcome?

    private let processor: PurchaseTransactionProcessor
    private var transactionListenerTask: Task<Void, Never>?
    private(set) var transactionListenerStartCount = 0
    private(set) var signedInPenPalUserID: String?
    private(set) var accountTokenState: PenPalAccountTokenState = .unavailableBackendRequired

    init(processor: PurchaseTransactionProcessor = BackendPurchaseTransactionProcessor()) {
        self.processor = processor
    }

    var founderProduct: Product? {
        productsByIdentifier[.founderSupporter]
    }

    var premiumMonthlyProduct: Product? {
        productsByIdentifier[.premiumMonthly]
    }

    var premiumAnnualProduct: Product? {
        productsByIdentifier[.premiumAnnual]
    }

    func configureSignedInPenPalAccount(userID: String, appAccountToken: UUID?) {
        signedInPenPalUserID = userID
        if let appAccountToken {
            accountTokenState = .available(appAccountToken)
        } else {
            accountTokenState = .unavailableBackendRequired
        }
    }

    func prepareForSignedInPenPalAccount(userID: String) async {
        signedInPenPalUserID = userID
        BackendEntitlementRepository.shared.startObservingCurrentUser()

        do {
            let token = try await BackendEntitlementRepository.shared.ensureAppAccountToken()
            configureSignedInPenPalAccount(userID: userID, appAccountToken: token)
        } catch {
            accountTokenState = .unavailableBackendRequired
            lastPurchaseOutcome = .failed(message: error.localizedDescription)
        }
    }

    func resetForLogout() {
        signedInPenPalUserID = nil
        accountTokenState = .unavailableBackendRequired
        appleLocalSnapshot = .empty
        subscriptionStatuses = []
        lastPurchaseOutcome = nil
        BackendEntitlementRepository.shared.resetForLogout()
    }

    func startTransactionListener() {
        guard transactionListenerTask == nil else { return }
        transactionListenerStartCount += 1
        transactionListenerTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handleTransactionUpdate(result)
            }
        }
    }

    func stopTransactionListener() {
        transactionListenerTask?.cancel()
        transactionListenerTask = nil
    }

    func loadProducts() async {
        productLoadState = .loading
        let requestedProductIDs = PenPalStoreKitProductCatalog.allProductIDs.sorted()

        do {
            let products = try await Product.products(for: requestedProductIDs)
            var mappedProducts: [PenPalProductIdentifier: Product] = [:]

            for product in products {
                guard let identifier = PenPalStoreKitProductCatalog.productIdentifier(for: product.id) else { continue }
                mappedProducts[identifier] = product
            }

            productsByIdentifier = mappedProducts

            let missingProductIDs = PenPalProductIdentifier.allCases
                .filter { mappedProducts[$0] == nil }
                .map(\.rawValue)
                .sorted()

            Self.logProductLoadingResult(
                requestedProductIDs: requestedProductIDs,
                returnedProducts: products,
                missingProductIDs: missingProductIDs
            )

            productLoadState = missingProductIDs.isEmpty
                ? .loaded
                : .unavailable(missingProductIDs: missingProductIDs)

            await refreshSubscriptionStatuses()
        } catch {
            Self.logProductLoadingError(requestedProductIDs: requestedProductIDs, error: error)
            productLoadState = .failed(message: error.localizedDescription)
        }
    }

    @discardableResult
    func purchase(_ identifier: PenPalProductIdentifier) async -> StoreKitPurchaseOutcome {
        guard let product = productsByIdentifier[identifier] else {
            let outcome = StoreKitPurchaseOutcome.failed(message: StoreKitPurchaseServiceError.productUnavailable.localizedDescription)
            lastPurchaseOutcome = outcome
            return outcome
        }

        guard case .available(let appAccountToken) = accountTokenState else {
            let outcome = StoreKitPurchaseOutcome.failed(message: StoreKitPurchaseServiceError.accountTokenUnavailable.localizedDescription)
            lastPurchaseOutcome = outcome
            return outcome
        }

        do {
            let result = try await product.purchase(options: [.appAccountToken(appAccountToken)])

            switch result {
            case .success(let verificationResult):
                let outcome = await handleVerifiedPurchaseResult(verificationResult)
                lastPurchaseOutcome = outcome
                return outcome
            case .pending:
                lastPurchaseOutcome = .pending
                return .pending
            case .userCancelled:
                lastPurchaseOutcome = .cancelled
                return .cancelled
            @unknown default:
                let outcome = StoreKitPurchaseOutcome.failed(message: "The purchase could not be completed.")
                lastPurchaseOutcome = outcome
                return outcome
            }
        } catch {
            let outcome = StoreKitPurchaseOutcome.failed(message: error.localizedDescription)
            lastPurchaseOutcome = outcome
            return outcome
        }
    }

    func restorePurchases() async -> String? {
        do {
            try await AppStore.sync()
            await processCurrentEntitlementsWithBackend()
            try await CommerceBackendClient.shared.reconcileAppStoreEntitlements()
            await refreshCurrentEntitlements()
            return nil
        } catch {
            Self.logRestoreError(error)
            return error.localizedDescription
        }
    }

    func refreshCurrentEntitlements() async {
        var verifiedTransactions: [VerifiedStoreTransaction] = []

        for await result in Transaction.currentEntitlements {
            if let transaction = StoreKitVerifiedTransactionMapper.transaction(from: StoreKitVerifiedTransactionMapper.state(from: result)) {
                verifiedTransactions.append(transaction)
            }
        }

        appleLocalSnapshot = StoreKitEntitlementSnapshot(verifiedTransactions: verifiedTransactions)
        await refreshSubscriptionStatuses()
    }

    private func refreshSubscriptionStatuses() async {
        var snapshots: [StoreKitSubscriptionStatusSnapshot] = []

        for product in productsByIdentifier.values {
            guard let subscription = product.subscription else { continue }

            do {
                let statuses = try await subscription.status
                snapshots.append(contentsOf: statuses.map {
                    StoreKitSubscriptionStatusSnapshot(
                        productID: product.id,
                        stateDescription: String(describing: $0.state)
                    )
                })
            } catch {
                continue
            }
        }

        subscriptionStatuses = snapshots.sorted { $0.productID < $1.productID }
    }

    private func handleTransactionUpdate(_ result: VerificationResult<Transaction>) async {
        _ = await handleVerifiedPurchaseResult(result)
        await refreshCurrentEntitlements()
    }

    private func processCurrentEntitlementsWithBackend() async {
        for await result in Transaction.currentEntitlements {
            _ = await handleVerifiedPurchaseResult(result)
        }
    }

    private func handleVerifiedPurchaseResult(_ result: VerificationResult<Transaction>) async -> StoreKitPurchaseOutcome {
        switch result {
        case .verified(let transaction):
            let verifiedTransaction = VerifiedStoreTransaction(transaction: transaction)

            do {
                try await processor.process(transaction, signedTransactionInfo: result.jwsRepresentation)
                await transaction.finish()
                await refreshCurrentEntitlements()
                return .verifiedProcessed(verifiedTransaction)
            } catch {
                return .backendProcessingFailed(verifiedTransaction, message: error.localizedDescription)
            }
        case .unverified:
            return .unverified
        }
    }

    private static func logProductLoadingResult(
        requestedProductIDs: [String],
        returnedProducts: [Product],
        missingProductIDs: [String]
    ) {
        #if DEBUG
        print("Requested StoreKit IDs:")
        requestedProductIDs.forEach { print("- \($0)") }

        if returnedProducts.isEmpty {
            print("Returned StoreKit products: <none>")
            print("StoreKit returned an empty product array.")
        } else {
            print("Returned StoreKit products:")
            returnedProducts
                .sorted { $0.id < $1.id }
                .forEach { product in
                    print("- \(product.id) | \(product.displayName) | \(product.displayPrice) | \(String(describing: product.type))")
                }
        }

        if missingProductIDs.isEmpty {
            print("Missing requested StoreKit IDs: <none>")
        } else {
            print("Missing requested StoreKit IDs:")
            missingProductIDs.forEach { print("- \($0)") }
        }
        #endif
    }

    private static func logProductLoadingError(requestedProductIDs: [String], error: Error) {
        #if DEBUG
        print("StoreKit product loading failed.")
        print("Requested StoreKit IDs:")
        requestedProductIDs.forEach { print("- \($0)") }
        print("Error: \(error)")
        #endif
    }

    private static func logRestoreError(_ error: Error) {
        #if DEBUG
        print("StoreKit restore failed: \(error)")
        #endif
    }
}
