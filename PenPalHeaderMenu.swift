import SwiftUI

// MARK: PenPal Header Menu

struct PenPalHeaderMenu: View {
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    let isFounderSupporter: Bool
    var plan: PenPalPlan = .free
    @State private var subscriptionMessage = ""

    private var canOpenPenPalLab: Bool {
        !PenPalLabConfiguration.restrictPenPalLabToFounders || isFounderSupporter
    }

    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                Text("PenPal")
                    .font(.system(size: 44, weight: .light, design: .serif))

                headerBadge
            }
            .frame(maxWidth: .infinity)

            HStack {
                Spacer()
                menuButton
            }
        }
        .padding(.horizontal, 20)
        .alert(appText("Subscriptions", languageRaw), isPresented: Binding(
            get: { !subscriptionMessage.isEmpty },
            set: { newValue in
                if !newValue { subscriptionMessage = "" }
            }
        )) {
            Button(appText("OK", languageRaw), role: .cancel) {}
        } message: {
            Text(subscriptionMessage)
        }
    }

    private var menuButton: some View {
        Menu {
            NavigationLink {
                SubscriptionDetailsView(plan: plan)
            } label: {
                Label(appText("Your PenPal Plan", languageRaw), systemImage: "person.crop.circle")
            }

            NavigationLink {
                SubscriptionUpgradeView(currentPlan: plan)
            } label: {
                Label(appText("Upgrade or change plan", languageRaw), systemImage: "arrow.up.circle")
            }

            Button {
                Task {
                    subscriptionMessage = await SubscriptionActions.restorePurchases(languageRaw: languageRaw)
                }
            } label: {
                Label(appText("Restore purchases", languageRaw), systemImage: "arrow.clockwise")
            }

            NavigationLink {
                PenPalLabView()
            } label: {
                Label(appText("PenPal Lab", languageRaw), systemImage: "flask.fill")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.headline)
                .foregroundStyle(PenPalStyle.ink)
                .frame(width: 38, height: 38)
                .background(Color.black.opacity(0.06))
                .clipShape(Circle())
        }
        .accessibilityLabel(appText("More PenPal options", languageRaw))
    }

    @ViewBuilder
    private var headerBadge: some View {
        switch plan {
        case .premium:
            NavigationLink {
                SubscriptionDetailsView(plan: plan)
            } label: {
                PlanBadge(plan: plan)
            }
            .buttonStyle(.plain)
        case .founder:
            NavigationLink {
                PenPalLabView()
            } label: {
                PlanBadge(plan: .founder)
            }
            .buttonStyle(.plain)
        case .free:
            if canOpenPenPalLab, isFounderSupporter {
                NavigationLink {
                    PenPalLabView()
                } label: {
                    PlanBadge(plan: .founder)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct PlanBadge: View {
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    let plan: PenPalPlan

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: plan.symbol)
                .font(.caption.weight(.semibold))
            Text(appText(plan.titleKey, languageRaw))
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(PenPalStyle.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.06))
        .clipShape(Capsule())
        .accessibilityLabel(appText(plan.titleKey, languageRaw))
    }
}
