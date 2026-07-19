import SwiftUI

// MARK: Founder Supporter Hub

struct FounderSupporterHubView: View {
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    let isFounderSupporter: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                NavigationLink {
                    PenPalLabView()
                } label: {
                    HubRow(
                        icon: "flask.fill",
                        title: appText("PenPal Lab", languageRaw),
                        subtitle: appText("Shape upcoming ideas, vote on suggestions and follow what is planned.", languageRaw)
                    )
                }
                .buttonStyle(.plain)

                HubRow(
                    icon: "paperplane",
                    title: appText("Submit feedback", languageRaw),
                    subtitle: appText("Share thoughtful product ideas with the PenPal team.", languageRaw)
                )

                HubRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: appText("Voting and roadmap", languageRaw),
                    subtitle: appText("Support ideas and see what is planned, in progress or released.", languageRaw)
                )

                HubRow(
                    icon: "star",
                    title: appText("Founder benefits", languageRaw),
                    subtitle: appText("See what Founder Supporter unlocks as PenPal grows.", languageRaw)
                )

                HubRow(
                    icon: "sparkles",
                    title: appText("Founder badge", languageRaw),
                    subtitle: appText("A subtle mark for early supporters inside PenPal Lab.", languageRaw)
                )
            }
            .padding()
        }
        .background(PenPalStyle.background.ignoresSafeArea())
        .navigationTitle(appText("Founder Supporter Hub", languageRaw))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "flask.fill")
                    .font(.headline)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.08))
                    .clipShape(Circle())

                Text(appText("Founder Supporter Hub", languageRaw))
                    .font(.system(size: 32, weight: .light, design: .serif))
            }

            Text(appText("Help shape the future of PenPal", languageRaw))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !PenPalLabConfiguration.restrictPenPalLabToFounders {
                Text(appText("Development Preview", languageRaw))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.06))
                    .clipShape(Capsule())
            }
        }
    }
}

private struct HubRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .frame(width: 36, height: 36)
                .background(Color.black.opacity(0.08))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
