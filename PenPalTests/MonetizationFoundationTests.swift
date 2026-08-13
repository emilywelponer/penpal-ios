import Foundation
import Testing
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import TravelingFriends

struct MonetizationFoundationTests {
    @Test func uploadedJPEGEncodingStripsGPSMetadata() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32))
        let sourceImage = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        let sourceData = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(sourceData, UTType.jpeg.identifier as CFString, 1, nil))
        let cgImage = try #require(sourceImage.cgImage)
        let metadata: [CFString: Any] = [kCGImagePropertyGPSDictionary: [
            kCGImagePropertyGPSLatitude: 45.0,
            kCGImagePropertyGPSLongitude: 9.0,
        ]]
        CGImageDestinationAddImage(destination, cgImage, metadata as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))

        let metadataImage = try #require(UIImage(data: sourceData as Data))
        let uploaded = try #require(compressedImageData(from: metadataImage, maxSize: 1200, quality: 0.56, targetMaxBytes: 500_000))
        let uploadedSource = try #require(CGImageSourceCreateWithData(uploaded as CFData, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(uploadedSource, 0, nil) as? [CFString: Any]
        #expect(properties?[kCGImagePropertyGPSDictionary] == nil)
    }

    @Test func productCatalogueUsesExpectedIdentifiers() {
        #expect(PenPalStoreKitProductCatalog.bundleIdentifier == "com.emily.penpal")
        #expect(PenPalStoreKitProductCatalog.founderProductID == "com.emily.penpal.founder")
        #expect(PenPalStoreKitProductCatalog.premiumMonthlyProductID == "com.emily.penpal.premium.monthly")
        #expect(PenPalStoreKitProductCatalog.premiumAnnualProductID == "com.emily.penpal.premium.annual")
        #expect(PenPalStoreKitProductCatalog.allProductIDs.count == 3)
    }

    @Test func founderRemainsIndependentFromPremium() {
        let founder = VerifiedStoreTransaction(
            transactionID: 1,
            originalTransactionID: 1,
            productID: PenPalStoreKitProductCatalog.founderProductID,
            purchaseDate: Date(),
            expirationDate: nil,
            revocationDate: nil,
            isUpgraded: false
        )

        let snapshot = StoreKitEntitlementSnapshot(verifiedTransactions: [founder], capturedAt: Date())

        #expect(snapshot.hasActiveFounderSupporterPurchase)
        #expect(snapshot.activePremiumProductID == nil)
        #expect(snapshot.appleLocalMembershipTier == .free)
    }

    @Test func monthlyAndAnnualPremiumMapToPremiumMembership() {
        #expect(PenPalProductIdentifier.premiumMonthly.entitlement == .premium)
        #expect(PenPalProductIdentifier.premiumAnnual.entitlement == .premium)
        #expect(PenPalStoreKitProductCatalog.isPremiumProductID(PenPalStoreKitProductCatalog.premiumMonthlyProductID))
        #expect(PenPalStoreKitProductCatalog.isPremiumProductID(PenPalStoreKitProductCatalog.premiumAnnualProductID))
    }

    @Test func revokedFounderTransactionIsNotActive() {
        let revokedFounder = VerifiedStoreTransaction(
            transactionID: 2,
            originalTransactionID: 2,
            productID: PenPalStoreKitProductCatalog.founderProductID,
            purchaseDate: Date(),
            expirationDate: nil,
            revocationDate: Date(),
            isUpgraded: false
        )

        let snapshot = StoreKitEntitlementSnapshot(verifiedTransactions: [revokedFounder], capturedAt: Date())

        #expect(!snapshot.hasActiveFounderSupporterPurchase)
    }

    @Test func expiredPremiumTransactionIsNotActive() {
        let now = Date()
        let expiredPremium = VerifiedStoreTransaction(
            transactionID: 3,
            originalTransactionID: 3,
            productID: PenPalStoreKitProductCatalog.premiumMonthlyProductID,
            purchaseDate: now.addingTimeInterval(-86400 * 40),
            expirationDate: now.addingTimeInterval(-86400),
            revocationDate: nil,
            isUpgraded: false
        )

        let snapshot = StoreKitEntitlementSnapshot(verifiedTransactions: [expiredPremium], capturedAt: now)

        #expect(snapshot.activePremiumProductID == nil)
        #expect(snapshot.appleLocalMembershipTier == .free)
    }

    @Test func unverifiedTransactionsAreRejectedByMapper() {
        #expect(StoreKitVerifiedTransactionMapper.transaction(from: .unverified) == nil)
    }

    @Test func pendingAndCancelledPurchasesDoNotGrantBackendAccess() {
        #expect(!StoreKitPurchaseOutcome.pending.grantsBackendEntitlement)
        #expect(!StoreKitPurchaseOutcome.cancelled.grantsBackendEntitlement)
    }

    @Test func productLoadingFailureIsRepresentedCleanly() {
        let state = StoreKitProductLoadState.failed(message: "Network unavailable")
        if case .failed(let message) = state {
            #expect(message == "Network unavailable")
        } else {
            Issue.record("Expected product loading to expose a failure state.")
        }
    }

    @Test func backendProcessorFailureDoesNotGrantPenPalEntitlement() {
        let transaction = VerifiedStoreTransaction(
            transactionID: 4,
            originalTransactionID: 4,
            productID: PenPalStoreKitProductCatalog.premiumAnnualProductID,
            purchaseDate: Date(),
            expirationDate: Date().addingTimeInterval(86400 * 365),
            revocationDate: nil,
            isUpgraded: false
        )

        let outcome = StoreKitPurchaseOutcome.backendProcessingFailed(
            transaction,
            message: "Backend processing failed."
        )

        #expect(!outcome.grantsBackendEntitlement)
        #expect(PenPalUserEntitlements.free.membershipTier == .free)
        #expect(!PenPalUserEntitlements.free.isFounderSupporter)
    }

    @MainActor
    @Test func transactionListenerStartsOnlyOnce() {
        let service = StoreKitPurchaseService()

        service.startTransactionListener()
        service.startTransactionListener()

        #expect(service.transactionListenerStartCount == 1)
        service.stopTransactionListener()
    }
}
