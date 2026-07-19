import SwiftUI

// MARK: PenPal Header Menu

struct PenPalHeaderMenu: View {
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    let isFounderSupporter: Bool
    var plan: PenPalPlan = .free

    private var canOpenFounderHub: Bool {
        !PenPalLabConfiguration.restrictPenPalLabToFounders || isFounderSupporter
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 8) {
                Text("PenPal")
                    .font(.system(size: 44, weight: .light, design: .serif))

                headerBadge
            }

            Spacer()

            Menu {
                NavigationLink {
                    SubscriptionDetailsView(plan: plan)
                } label: {
                    Label(appText("Your PenPal Plan", languageRaw), systemImage: "person.crop.circle")
                }

                Button {
                    // StoreKit upgrade flow is intentionally not implemented in this navigation cleanup.
                } label: {
                    Label(appText("Upgrade or change plan", languageRaw), systemImage: "arrow.up.circle")
                }

                NavigationLink {
                    SubscriptionDetailsView(plan: plan)
                } label: {
                    Label(appText("Compare plans", languageRaw), systemImage: "rectangle.3.group")
                }

                Button {
                    // Restore purchases will connect to StoreKit when subscriptions are implemented.
                } label: {
                    Label(appText("Restore purchases", languageRaw), systemImage: "arrow.clockwise")
                }

                if canOpenFounderHub {
                    NavigationLink {
                        FounderSupporterHubView(isFounderSupporter: isFounderSupporter)
                    } label: {
                        Label(appText("PenPal Lab", languageRaw), systemImage: "flask.fill")
                    }
                }

                NavigationLink {
                    AboutPenPalView()
                } label: {
                    Label(appText("About PenPal", languageRaw), systemImage: "info.circle")
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
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var headerBadge: some View {
        switch plan {
        case .pro, .premium:
            NavigationLink {
                SubscriptionDetailsView(plan: plan)
            } label: {
                PlanBadge(plan: plan)
            }
            .buttonStyle(.plain)
        case .founder:
            NavigationLink {
                FounderSupporterHubView(isFounderSupporter: isFounderSupporter)
            } label: {
                PlanBadge(plan: .founder)
            }
            .buttonStyle(.plain)
        case .free:
            if canOpenFounderHub, isFounderSupporter {
                NavigationLink {
                    FounderSupporterHubView(isFounderSupporter: isFounderSupporter)
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

private struct AboutPenPalView: View {
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("PenPal")
                .font(.system(size: 42, weight: .light, design: .serif))
            Text(appText("A quieter place for shared monthly magazines.", languageRaw))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PenPalStyle.background.ignoresSafeArea())
        .navigationTitle(appText("About PenPal", languageRaw))
        .navigationBarTitleDisplayMode(.inline)
    }
}
