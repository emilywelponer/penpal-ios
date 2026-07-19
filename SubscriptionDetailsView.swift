import SwiftUI
import StoreKit
import UIKit

// MARK: Subscription Navigation

enum PenPalPlan: String {
    case free
    case pro
    case premium
    case founder

    var titleKey: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro"
        case .premium: return "Premium"
        case .founder: return "Founder Supporter"
        }
    }

    var symbol: String {
        switch self {
        case .free: return "circle"
        case .pro: return "sparkles"
        case .premium: return "crown.fill"
        case .founder: return "flask.fill"
        }
    }
}

struct SubscriptionDetailsView: View {
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    var plan: PenPalPlan = .free
    @State private var message = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: plan.symbol)
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.08))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(appText("Your PenPal Plan", languageRaw))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(appText(plan.titleKey, languageRaw))
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
                    Text(appText("No renewal information is available yet.", languageRaw))
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
    let currentPlan: PenPalPlan
    @State private var message = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(appText("Upgrade or change plan", languageRaw))
                    .font(.system(size: 32, weight: .light, design: .serif))

                Text(appText("Development Preview", languageRaw))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.06))
                    .clipShape(Capsule())

                ForEach([PenPalPlan.free, .pro, .premium, .founder], id: \.rawValue) { plan in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: plan.symbol)
                            Text(appText(plan.titleKey, languageRaw))
                                .font(.headline)
                            Spacer()
                            if plan == currentPlan {
                                Text(appText("Current plan", languageRaw))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(appText(plan.descriptionKey, languageRaw))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }

                Button {
                    message = appText("Subscriptions are not available in this development build yet.", languageRaw)
                } label: {
                    Text(appText("Continue", languageRaw))
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
        .navigationTitle(appText("Upgrade or change plan", languageRaw))
        .navigationBarTitleDisplayMode(.inline)
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
        do {
            try await AppStore.sync()
            return appText("Purchases restored.", languageRaw)
        } catch {
            return appText("Purchases could not be restored right now.", languageRaw)
        }
    }
}

private extension PenPalPlan {
    var descriptionKey: String {
        switch self {
        case .free:
            return "Create magazines, save drafts and share with your groups."
        case .pro:
            return "Extra creative tools and more room to shape each issue."
        case .premium:
            return "The fullest PenPal experience for frequent magazine makers."
        case .founder:
            return "Includes PenPal Lab, voting, roadmap previews and the Founder badge."
        }
    }
}
