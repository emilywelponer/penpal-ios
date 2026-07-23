import SwiftUI
import StoreKit
import UIKit
import FirebaseAuth

// MARK: Subscription Navigation

enum PenPalPlan: String {
    case free
    case premium
    case founder

    var titleKey: String {
        switch self {
        case .free: return "Free"
        case .premium: return "Premium"
        case .founder: return "Founder Supporter"
        }
    }

    var symbol: String {
        switch self {
        case .free: return "circle"
        case .premium: return "crown.fill"
        case .founder: return "flask.fill"
        }
    }
}

struct SubscriptionDetailsView: View {
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    @StateObject private var entitlementRepository = BackendEntitlementRepository.shared
    var plan: PenPalPlan = .free
    @State private var message = ""

    private var displayedPlan: PenPalPlan {
        entitlementRepository.currentPlan
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: displayedPlan.symbol)
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.08))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(appText("Your PenPal Plan", languageRaw))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(appText(displayedPlan.titleKey, languageRaw))
                            .font(.system(size: 32, weight: .light, design: .serif))
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(appText("Included features", languageRaw))
                        .font(.headline)
                    Text(appText("Create magazines, save drafts, publish to groups and collect your memories in PenPal.", languageRaw))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 20))

                VStack(alignment: .leading, spacing: 12) {
                    Text(appText("Renewal information", languageRaw))
                        .font(.headline)
                    Text(renewalText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 20))

                Button {
                    SubscriptionActions.openManageSubscriptions()
                } label: {
                    Text(appText("Manage subscription", languageRaw))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
            }
            .padding()
        }
        .alert(appText("Subscriptions", languageRaw), isPresented: Binding(
            get: { !message.isEmpty },
            set: { newValue in
                if !newValue { message = "" }
            }
        )) {
            Button(appText("OK", languageRaw), role: .cancel) {}
        } message: {
            Text(message)
        }
        .background(PenPalStyle.background.ignoresSafeArea())
        .navigationTitle(appText("Your PenPal Plan", languageRaw))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SubscriptionUpgradeView: View {
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    @StateObject private var storeKitService = StoreKitPurchaseService.shared
    @StateObject private var entitlementRepository = BackendEntitlementRepository.shared
    let currentPlan: PenPalPlan
    @State private var message = ""
    @State private var purchasingIdentifier: PenPalProductIdentifier?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(appText("Upgrade or change plan", languageRaw))
                    .font(.system(size: 32, weight: .light, design: .serif))

                if case .loading = storeKitService.productLoadState {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }

                PremiumPurchaseCard(
                    monthlyProduct: storeKitService.premiumMonthlyProduct,
                    annualProduct: storeKitService.premiumAnnualProduct,
                    isPurchasing: purchasingIdentifier != nil,
                    purchase: purchase
                )

                FounderPurchaseCard(
                    founderProduct: storeKitService.founderProduct,
                    isPurchasing: purchasingIdentifier != nil,
                    purchase: purchase
                )

                Button {
                    Task {
                        message = await SubscriptionActions.restorePurchases(languageRaw: languageRaw)
                    }
                } label: {
                    Text(appText("Restore purchases", languageRaw))
                        .font(.headline)
                        .foregroundStyle(PenPalStyle.ink)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.black.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(appText("Premium does not include Founder Supporter. Founder Supporter does not include Premium.", languageRaw))
                    Text(appText("Subscriptions renew automatically until cancelled in your Apple ID settings.", languageRaw))
                    Text(appText("Access every monthly magazine while Premium is active. Free keeps the latest six months once archive enforcement launches.", languageRaw))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding()
        }
        .task {
            entitlementRepository.startObservingCurrentUser()
            await storeKitService.loadProducts()
            if let uid = Auth.auth().currentUser?.uid {
                await storeKitService.prepareForSignedInPenPalAccount(userID: uid)
            }
        }
        .alert(appText("Subscriptions", languageRaw), isPresented: Binding(
            get: { !message.isEmpty },
            set: { newValue in
                if !newValue { message = "" }
            }
        )) {
            Button(appText("OK", languageRaw), role: .cancel) {}
        } message: {
            Text(message)
        }
        .background(PenPalStyle.background.ignoresSafeArea())
        .navigationTitle(appText("Upgrade or change plan", languageRaw))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func purchase(_ identifier: PenPalProductIdentifier) {
        guard purchasingIdentifier == nil else { return }
        purchasingIdentifier = identifier
        Task {
            let outcome = await storeKitService.purchase(identifier)
            await MainActor.run {
                purchasingIdentifier = nil
                message = messageText(for: outcome)
            }
        }
    }

    private func messageText(for outcome: StoreKitPurchaseOutcome) -> String {
        switch outcome {
        case .verifiedProcessed:
            return appText("Purchase verified. Your PenPal access is updating.", languageRaw)
        case .backendProcessingFailed(_, let message):
            return message
        case .unverified:
            return appText("Apple could not verify this purchase.", languageRaw)
        case .pending:
            return appText("Purchase pending. You will get access after Apple approves it.", languageRaw)
        case .cancelled:
            return appText("Purchase cancelled.", languageRaw)
        case .failed(let message):
            return message
        }
    }
}

enum SubscriptionActions {
    @MainActor
    static func openManageSubscriptions() {
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
        UIApplication.shared.open(url)
    }

    @MainActor
    static func restorePurchases(languageRaw: String) async -> String {
        let errorMessage = await StoreKitPurchaseService.shared.restorePurchases()
        if let errorMessage {
            return errorMessage
        }
        return appText("Purchases restored.", languageRaw)
    }
}

private struct PremiumPurchaseCard: View {
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    let monthlyProduct: Product?
    let annualProduct: Product?
    let isPurchasing: Bool
    let purchase: (PenPalProductIdentifier) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(appText("Premium", languageRaw), systemImage: "crown.fill")
                .font(.headline)

            Text(appText("Keep your complete magazine story. Access every monthly magazine while Premium is active.", languageRaw))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            purchaseButton(
                title: appText("Premium Monthly", languageRaw),
                price: monthlyProduct?.displayPrice,
                identifier: .premiumMonthly
            )

            purchaseButton(
                title: appText("Premium Annual", languageRaw),
                price: annualProduct?.displayPrice,
                identifier: .premiumAnnual
            )
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func purchaseButton(title: String, price: String?, identifier: PenPalProductIdentifier) -> some View {
        Button {
            purchase(identifier)
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(price ?? appText("Unavailable", languageRaw))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding()
            .background(price == nil ? Color.gray : Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .disabled(isPurchasing || price == nil)
    }
}

private struct FounderPurchaseCard: View {
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    let founderProduct: Product?
    let isPurchasing: Bool
    let purchase: (PenPalProductIdentifier) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(appText("Founder Supporter", languageRaw), systemImage: "flask.fill")
                .font(.headline)

            Text(appText("One-time purchase. Includes the Founder badge, PenPal Lab, suggestions and voting. Premium is not included.", languageRaw))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                purchase(.founderSupporter)
            } label: {
                HStack {
                    Text(appText("Become a Founder Supporter", languageRaw))
                    Spacer()
                    Text(founderProduct?.displayPrice ?? appText("Unavailable", languageRaw))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding()
                .background(founderProduct == nil ? Color.gray : Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(isPurchasing || founderProduct == nil)
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

private extension SubscriptionDetailsView {
    var renewalText: String {
        if entitlementRepository.hasPremiumAccess,
           let expiration = entitlementRepository.entitlements.premiumExpirationDate {
            return "\(appText("Premium active until", languageRaw)) \(expiration.formatted(date: .abbreviated, time: .omitted))."
        }

        if entitlementRepository.entitlements.isFounderSupporter {
            return appText("Founder Supporter is a one-time purchase and does not renew.", languageRaw)
        }

        return appText("No active paid plan.", languageRaw)
    }
}

private extension PenPalPlan {
    var descriptionKey: String {
        switch self {
        case .free:
            return "Create magazines, save drafts and share with your groups."
        case .premium:
            return "The fullest PenPal experience for frequent magazine makers."
        case .founder:
            return "Includes PenPal Lab, voting, roadmap previews and the Founder badge."
        }
    }
}
