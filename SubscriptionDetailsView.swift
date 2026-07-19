import SwiftUI

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
                    // StoreKit is intentionally not implemented in this task.
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
        .background(PenPalStyle.background.ignoresSafeArea())
        .navigationTitle(appText("Your PenPal Plan", languageRaw))
        .navigationBarTitleDisplayMode(.inline)
    }
}
