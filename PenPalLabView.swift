import SwiftUI

// MARK: PenPal Lab Feature

struct PenPalLabView: View {
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    @StateObject private var service = PenPalLabService.shared
    @State private var sortOption: PenPalLabSortOption = .mostSupported
    @State private var showSuggestionForm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if !service.entitlementChecked {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if !service.canAccessLab {
                    accessDenied
                } else {
                    controls
                    roadmap
                    suggestionList
                }
            }
            .padding()
        }
        .background(PenPalStyle.background.ignoresSafeArea())
        .navigationTitle(appText("PenPal Lab", languageRaw))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSuggestionForm) {
            PenPalLabSuggestionFormView { error in
                if error == nil {
                    showSuggestionForm = false
                }
            }
        }
        .onAppear {
            service.refreshEntitlement()
            service.startListening(sort: sortOption)
        }
        .onDisappear {
            service.stopListening()
        }
        .onChange(of: sortOption) { _, newValue in
            service.startListening(sort: newValue)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(appText("PenPal Lab", languageRaw))
                    .font(.system(size: 36, weight: .light, design: .serif))

                FounderSupporterBadge()
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

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                showSuggestionForm = true
            } label: {
                HStack {
                    Image(systemName: "lightbulb")
                    Text(appText("Suggest an idea", languageRaw))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .font(.headline)
                .foregroundStyle(.primary)
                .padding()
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)

            Picker(appText("Sort suggestions", languageRaw), selection: $sortOption) {
                ForEach(PenPalLabSortOption.allCases) { option in
                    Text(appText(option.localizationKey, languageRaw)).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var roadmap: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(appText("Roadmap", languageRaw))
                .font(.headline)

            let groups = PenPalLabRoadmap.grouped(service.suggestions)
            if groups.allSatisfy({ $0.1.isEmpty }) {
                Text(appText("No roadmap items yet.", languageRaw))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            } else {
                VStack(spacing: 10) {
                    ForEach(groups, id: \.0) { status, items in
                        if !items.isEmpty {
                            PenPalLabRoadmapSection(status: status, items: items)
                        }
                    }
                }
            }
        }
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(appText("Suggestions", languageRaw))
                .font(.headline)

            if service.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
            } else if !service.errorMessage.isEmpty {
                Text(service.errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if service.suggestions.isEmpty {
                Text(appText("No suggestions yet.", languageRaw))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(service.suggestions) { suggestion in
                        PenPalLabSuggestionRow(suggestion: suggestion) {
                            service.toggleVote(for: suggestion)
                        }
                    }
                }
            }
        }
    }

    private var accessDenied: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appText("PenPal Lab is only available to Founder Supporters.", languageRaw))
                .font(.headline)
            Text(appText("This area is not available for your account right now.", languageRaw))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

private struct PenPalLabSuggestionFormView: View {
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = PenPalLabService.shared
    @State private var title = ""
    @State private var description = ""
    @State private var category: PenPalLabCategory = .feature
    @State private var isSaving = false
    @State private var message = ""
    let completion: (String?) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(appText("What should PenPal do next?", languageRaw))
                        .font(.system(size: 28, weight: .light, design: .serif))

                    Text(appText("Suggestions may be visible to other Founder Supporters.", languageRaw))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(appText("Title", languageRaw))
                            .font(.headline)
                        TextField(appText("Suggest an idea", languageRaw), text: $title)
                            .textFieldStyle(.plain)
                            .padding()
                            .background(Color.gray.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .onChange(of: title) { _, newValue in
                                if newValue.count > 100 {
                                    title = String(newValue.prefix(100))
                                }
                            }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(appText("Description", languageRaw))
                            .font(.headline)
                        TextEditor(text: $description)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 150)
                            .padding(10)
                            .background(Color.gray.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .onChange(of: description) { _, newValue in
                                if newValue.count > 2000 {
                                    description = String(newValue.prefix(2000))
                                }
                            }
                    }

                    Picker(appText("Category", languageRaw), selection: $category) {
                        ForEach(PenPalLabCategory.allCases) { category in
                            Text(appText(category.localizationKey, languageRaw)).tag(category)
                        }
                    }
                    .pickerStyle(.menu)

                    if !message.isEmpty {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(message == appText("Thanks for helping shape PenPal", languageRaw) ? Color.secondary : Color.red)
                    }

                    Button {
                        submit()
                    } label: {
                        HStack {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(appText(isSaving ? "Submitting..." : "Submit suggestion", languageRaw))
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                    .disabled(isSaving)
                }
                .padding()
            }
            .background(PenPalStyle.background.ignoresSafeArea())
            .navigationTitle(appText("Suggest an idea", languageRaw))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(appText("Cancel", languageRaw)) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func submit() {
        guard !isSaving else { return }
        isSaving = true
        message = ""
        service.createSuggestion(title: title, description: description, category: category) { error in
            isSaving = false
            if let error {
                message = error
                completion(error)
            } else {
                message = appText("Thanks for helping shape PenPal", languageRaw)
                completion(nil)
            }
        }
    }
}

private struct PenPalLabSuggestionRow: View {
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    let suggestion: PenPalLabSuggestion
    let voteAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(suggestion.title)
                    .font(.headline)

                Spacer()

                Text(appText(suggestion.status.localizationKey, languageRaw))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(suggestion.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(4)

            HStack(spacing: 8) {
                Text(appText(suggestion.category.localizationKey, languageRaw))
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.06))
                    .clipShape(Capsule())

                Text(suggestion.authorDisplayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                FounderSupporterBadge(compact: true)

                Spacer()

                Button {
                    voteAction()
                } label: {
                    Label(
                        suggestion.currentUserHasVoted ? appText("Vote removed", languageRaw) : appText("I want this too", languageRaw),
                        systemImage: suggestion.currentUserHasVoted ? "heart.fill" : "heart"
                    )
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)

                Text("\(suggestion.voteCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct PenPalLabRoadmapSection: View {
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    let status: PenPalLabStatus
    let items: [PenPalLabSuggestion]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appText(status.localizationKey, languageRaw))
                .font(.subheadline.weight(.semibold))

            ForEach(items.prefix(3)) { item in
                HStack {
                    Text(item.title)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text("\(item.voteCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct FounderSupporterBadge: View {
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.system(size: compact ? 9 : 11, weight: .semibold))
            if !compact {
                Text(appText("Founder", languageRaw))
                    .font(.caption.weight(.semibold))
            }
        }
        .foregroundStyle(Color(red: 0.64, green: 0.45, blue: 0.13))
        .padding(.horizontal, compact ? 0 : 8)
        .padding(.vertical, compact ? 0 : 5)
        .background(compact ? Color.clear : Color(red: 0.95, green: 0.87, blue: 0.68).opacity(0.45))
        .clipShape(Capsule())
        .accessibilityLabel(appText("Founder Supporter", languageRaw))
    }
}
