import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct GroupIssuesView: View {
    
    let group: GroupModel
    let issues: [PublishedIssueModel]
    let month: Int
    let monthName: String
    let year: Int
    
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    @State private var selectedIssue: PublishedIssueModel?
    @State private var showIssueDetail = false
    
    private var fullMonthTitle: String {
        "\(localizedFullMonthName(for: month, languageRaw: languageRaw)) \(year)"
    }
    
    private var monthIssues: [PublishedIssueModel] {
        issues
            .filter {
                $0.month == month && $0.year == year
            }
            .sorted { $0.createdAt > $1.createdAt }
    }
    
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(fullMonthTitle)
                        .font(.system(size: 42, weight: .light, design: .serif))

                    Text(group.name)
                        .foregroundStyle(.secondary)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            if monthIssues.isEmpty {
                Text(appText("No magazines published this month yet.", languageRaw))
                    .font(.system(size: 16, weight: .medium, design: .serif))
                    .foregroundStyle(PenPalStyle.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 22)
                            .fill(PenPalStyle.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: 22)
                                    .stroke(PenPalStyle.border, lineWidth: 1)
                            )
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(monthIssues) { issue in
                    Button {
                        openIssue(issue)
                    } label: {
                        GroupIssueTextRow(issue: issue)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(PenPalStyle.background.ignoresSafeArea())
        .navigationTitle(fullMonthTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PenPalStyle.background, for: .navigationBar)
        .fullScreenCover(isPresented: $showIssueDetail) {
            NavigationStack {
                if let selectedIssue {
                    GroupPublishedIssueDetailView(issue: selectedIssue)
                }
            }
        }
        .onAppear {
            guard Auth.auth().currentUser?.uid != nil else {
                print("BLOCKED_QUERY_NO_AUTH", "GroupIssuesView.onAppear")
                return
            }
        }
        .onChange(of: showIssueDetail) { _, isPresented in
            if !isPresented {
                selectedIssue = nil
            }
        }
    }

    private func openIssue(_ issue: PublishedIssueModel) {
        selectedIssue = issue
        showIssueDetail = true
    }
}

private struct GroupIssueTextRow: View {
    let issue: PublishedIssueModel
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue

    private var title: String {
        issue.title.replacingOccurrences(of: "Draft ", with: "")
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "book.pages.fill")
                .font(.title3)
                .foregroundStyle(PenPalStyle.ink)
                .frame(width: 44, height: 44)
                .background(PenPalStyle.cardAlt)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(PenPalStyle.ink)

                Text(localizedDisplayDate(issue.createdAt, languageRaw: languageRaw))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PenPalStyle.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(PenPalStyle.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(PenPalStyle.border, lineWidth: 1)
        )
        .padding(.vertical, 2)
    }
}

private struct GroupPublishedIssueDetailView: View {
    let issue: PublishedIssueModel

    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    @State private var pages: [MagazinePage] = []
    @State private var selectedPage = 0
    @State private var isLoading = false
    @State private var messageText = ""
    @State private var isViewActive = false
    @State private var didStartLoading = false
    @State private var pageZoom: CGFloat = 1
    @State private var lastPageZoom: CGFloat = 1
    @State private var loadingImagePaths: Set<String> = []
    @State private var showAddGroupsSheet = false
    // MARK: Margin Notes Feature
    @State private var showMarginNotes = false
    @State private var currentPageHasMarginNotes = false
    @State private var marginNotesBadgeListener: ListenerRegistration?

    private var pageWidth: CGFloat {
        min(UIScreen.main.bounds.width - 16, (UIScreen.main.bounds.height - 96) * 170.0 / 250.0)
    }

    private var pageHeight: CGFloat {
        pageWidth * 250.0 / 170.0
    }

    var body: some View {
        ZStack {
            PenPalStyle.background.ignoresSafeArea()

            VStack(spacing: 10) {
                Text(displayTitle)
                    .font(.system(size: 22, weight: .medium, design: .serif))
                    .foregroundStyle(PenPalStyle.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if pages.isEmpty {
                    Spacer()

                    if isLoading {
                        ProgressView()
                    }

                    Text(messageText.isEmpty ? appText("Loading draft...", languageRaw) : messageText)
                        .foregroundStyle(.secondary)

                    Spacer()
                } else {
                    TabView(selection: $selectedPage) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                            SinglePageCanvas(page: .constant(page), editable: false)
                                .frame(width: pageWidth * pageZoom, height: pageHeight * pageZoom)
                                .clipShape(RoundedRectangle(cornerRadius: 24))
                                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
                                .padding(.horizontal, 16)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                    .frame(height: pageHeight * pageZoom + 30)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                pageZoom = min(3.2, max(1, lastPageZoom * value))
                            }
                            .onEnded { _ in
                                lastPageZoom = pageZoom
                            }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    MarginNotesEnvelopeButton(hasNotes: currentPageHasMarginNotes) {
                        showMarginNotes = true
                    }
                    .padding(.trailing, 18)
                    .padding(.bottom, 28)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PenPalStyle.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            if issue.ownerID == Auth.auth().currentUser?.uid {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showAddGroupsSheet = true
                    } label: {
                        Image(systemName: "paperplane")
                    }
                    .accessibilityLabel(appText("Send to groups", languageRaw))
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }
        }
        .onAppear {
            guard Auth.auth().currentUser?.uid != nil else {
                print("BLOCKED_QUERY_NO_AUTH", "GroupPublishedIssueDetailView.onAppear", issue.id)
                return
            }

            isViewActive = true
            FirestoreManager.shared.markIssueAsRead(issue)
            startMarginNotesBadgeListener()
        }
        .task {
            await loadIssue()
        }
        .onDisappear {
            marginNotesBadgeListener?.remove()
            marginNotesBadgeListener = nil
            isViewActive = false
            pages = []
            selectedPage = 0
            isLoading = false
            didStartLoading = false
            messageText = ""
            pageZoom = 1
            lastPageZoom = 1
            loadingImagePaths.removeAll()
        }
        .onChange(of: pages.count) { _, _ in
            clampSelectedPage()
            hydrateSelectedPageImagesIfNeeded()
        }
        .onChange(of: selectedPage) { _, _ in
            clampSelectedPage()
            startMarginNotesBadgeListener()
            hydrateSelectedPageImagesIfNeeded()
        }
        .sheet(isPresented: $showMarginNotes) {
            MarginNotesSheet(magazineID: issue.id, pageIndex: selectedPage)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAddGroupsSheet) {
            AddPublishedIssueToGroupsSheet(issue: issue)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var displayTitle: String {
        let cleanTitle = issue.title.replacingOccurrences(of: "Draft ", with: "")
        if cleanTitle.localizedCaseInsensitiveContains("issue") {
            return cleanTitle
        }

        let suffix = (AppLanguage(rawValue: languageRaw) ?? .english) == .spanish ? "Edición" : "Issue"
        return "\(cleanTitle) \(localizedFullMonthName(for: issue.month, languageRaw: languageRaw)) \(suffix)"
    }

    private func loadIssue() async {
        guard Auth.auth().currentUser?.uid != nil else {
            print("BLOCKED_QUERY_NO_AUTH", "GroupPublishedIssueDetailView.loadIssue", issue.id)
            return
        }

        let shouldStart = await MainActor.run { () -> Bool in
            guard !didStartLoading, pages.isEmpty else { return false }
            didStartLoading = true
            isLoading = true
            messageText = appText("Loading draft...", languageRaw)
            return true
        }

        guard shouldStart else { return }

        let dataString: String?

        if let path = issue.pageDraftDataPath, !path.isEmpty {
            print("GROUP_PAGE_DRAFT_DATA_PATH_EXISTS", issue.id, path)
            dataString = await downloadPageDraftData(path: path)
        } else if let pageDraftData = issue.pageDraftData, !pageDraftData.isEmpty {
            print("GROUP_INLINE_DRAFTDATA_PRESENT", issue.id, "length", pageDraftData.count)
            dataString = pageDraftData
        } else {
            await MainActor.run {
                guard isViewActive else { return }
                isLoading = false
                messageText = appText("No pages saved.", languageRaw)
            }
            return
        }

        let decoded = await decodePagesInBackground(dataString)

        await MainActor.run {
            guard isViewActive else { return }
            pages = decoded
            clampSelectedPage()
            hydrateSelectedPageImagesIfNeeded()
            isLoading = false
            messageText = decoded.isEmpty ? appText("No pages saved.", languageRaw) : ""
        }
    }

    private func downloadPageDraftData(path: String) async -> String? {
        await withCheckedContinuation { continuation in
            print("GROUP_STORED_JSON_LOAD_START", issue.id, path)
            FirestoreManager.shared.loadStoredString(path: path) { value in
                if let value, !value.isEmpty {
                    print("GROUP_STORED_JSON_LOAD_SUCCESS", issue.id, "length", value.count)
                } else {
                    print("GROUP_STORED_JSON_LOAD_FAILED", issue.id, path)
                }
                continuation.resume(returning: value)
            }
        }
    }

    private func decodePagesInBackground(_ value: String?) async -> [MagazinePage] {
        guard let value, !value.isEmpty else {
            print("GROUP_DECODE_SKIPPED_EMPTY", issue.id)
            return []
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard Auth.auth().currentUser?.uid != nil else {
                    print("BLOCKED_QUERY_NO_AUTH", "GroupPublishedIssueDetailView.decodePagesInBackground", issue.id)
                    continuation.resume(returning: [])
                    return
                }

                print("GROUP_DRAFTDATA_DECODE_START", issue.id, "length", value.count)
                let decoded = MagazineDraftCodec.decode(value, decodeImages: false)
                print("GROUP_DRAFTDATA_DECODE_END", issue.id, "pageCount", decoded.count)
                continuation.resume(returning: decoded)
            }
        }
    }

    private func hydrateSelectedPageImagesIfNeeded() {
        guard pages.indices.contains(selectedPage) else { return }
        for index in pages[selectedPage].elements.indices {
            guard pages[selectedPage].elements[index].type == .image,
                  pages[selectedPage].elements[index].image == nil,
                  let path = pages[selectedPage].elements[index].imageStoragePath,
                  !path.isEmpty,
                  !loadingImagePaths.contains(path) else { continue }

            let elementID = pages[selectedPage].elements[index].id
            loadingImagePaths.insert(path)
            let start = CFAbsoluteTimeGetCurrent()
            FirestoreManager.shared.loadStoredUIImage(path: path, maxPixelSize: 850) { image in
                let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                loadingImagePaths.remove(path)
                guard pages.indices.contains(selectedPage),
                      let currentIndex = pages[selectedPage].elements.firstIndex(where: { $0.id == elementID }) else { return }
                if let image {
                    pages[selectedPage].elements[currentIndex].image = image
                    print("GROUP_VISIBLE_IMAGE_LOAD_END", issue.id, "page", selectedPage, "elapsedMs", elapsed)
                } else {
                    print("GROUP_VISIBLE_IMAGE_LOAD_FAILED", issue.id, "page", selectedPage, "elapsedMs", elapsed)
                }
            }
        }
    }
    
    private func clampSelectedPage() {
        selectedPage = min(max(selectedPage, 0), max(pages.count - 1, 0))
        if pages.isEmpty {
            selectedPage = 0
        }
    }

    // MARK: Margin Notes Feature

    private func startMarginNotesBadgeListener() {
        guard isViewActive, Auth.auth().currentUser?.uid != nil else { return }
        marginNotesBadgeListener?.remove()
        currentPageHasMarginNotes = false
        let pageIndex = selectedPage
        marginNotesBadgeListener = MarginNotesService.shared.listen(magazineID: issue.id, pageIndex: pageIndex) { result in
            switch result {
            case .success(let notes):
                guard selectedPage == pageIndex else { return }
                currentPageHasMarginNotes = !notes.isEmpty
            case .failure(let error):
                currentPageHasMarginNotes = false
                print("MARGIN_NOTES_BADGE_ERROR", issue.id, pageIndex, error.localizedDescription)
            }
        }
    }
}
