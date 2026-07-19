import SwiftUI
import FirebaseAuth
import FirebaseFirestore

enum PublishedIssueDetailSource {
    case throwback
    case group
}

struct PublishedIssueDetailView: View {
    let issue: PublishedIssueModel
    let source: PublishedIssueDetailSource
    let allowBase64Fallback: Bool

    init(
        issue: PublishedIssueModel,
        source: PublishedIssueDetailSource = .throwback,
        allowBase64Fallback: Bool = true
    ) {
        self.issue = issue
        self.source = source
        self.allowBase64Fallback = allowBase64Fallback
    }
    
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    @State private var selectedPage = 0
    @State private var loadedPageImageData: [String] = []
    @State private var selectedFallbackImage: UIImage?
    @State private var selectedFallbackImageIndex: Int?
    @State private var isLoadingFallbackImage = false
    @State private var decodedPages: [MagazinePage] = []
    @State private var isLoadingDraftData = false
    @State private var hydratedIssue: PublishedIssueModel?
    @State private var didRequestFullIssue = false
    @State private var isViewActive = false
    @State private var pageZoom: CGFloat = 1
    @State private var lastPageZoom: CGFloat = 1
    @State private var loadingImagePaths: Set<String> = []
    @State private var showAddGroupsSheet = false
    // MARK: Margin Notes Feature
    @State private var showMarginNotes = false
    @State private var currentPageHasMarginNotes = false
    @State private var marginNotesBadgeListener: ListenerRegistration?

    private var activeIssue: PublishedIssueModel {
        hydratedIssue ?? issue
    }

    private var hasEditableDraftDataPath: Bool {
        activeIssue.pageDraftDataPath?.isEmpty == false
    }

    private var canUseBase64Fallback: Bool {
        allowBase64Fallback && !hasEditableDraftDataPath
    }

    private var fallbackPageImageData: [String] {
        guard canUseBase64Fallback else { return [] }
        let activeIssue = hydratedIssue ?? issue
        return loadedPageImageData.isEmpty ? activeIssue.pageImageData : loadedPageImageData
    }

    private var fallbackPageCount: Int {
        guard canUseBase64Fallback else { return 0 }
        let activeIssue = hydratedIssue ?? issue
        if !activeIssue.pageImagePaths.isEmpty {
            return activeIssue.pageImagePaths.count
        }

        return fallbackPageImageData.count
    }

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

                if decodedPages.isEmpty && fallbackPageCount == 0 {
                    Spacer()
                    
                    Text(isLoadingDraftData || isLoadingFallbackImage ? appText("Loading draft...", languageRaw) : appText("No pages saved.", languageRaw))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                } else {
                    pageReader
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
            if activeIssue.ownerID == Auth.auth().currentUser?.uid {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddGroupsSheet = true
                    } label: {
                        Image(systemName: "paperplane")
                    }
                    .accessibilityLabel(appText("Send to groups", languageRaw))
                }
            }
        }
        .onAppear {
            guard Auth.auth().currentUser?.uid != nil else {
                print("BLOCKED_QUERY_NO_AUTH", "PublishedIssueDetailView.onAppear", issue.id)
                return
            }

            isViewActive = true
            FirestoreManager.shared.markIssueAsRead(issue)
            loadEditablePages()
            startMarginNotesBadgeListener()
        }
        .onDisappear {
            marginNotesBadgeListener?.remove()
            marginNotesBadgeListener = nil
            isViewActive = false
            decodedPages = []
            loadedPageImageData = []
            selectedFallbackImage = nil
            selectedFallbackImageIndex = nil
            hydratedIssue = nil
            selectedPage = 0
            isLoadingDraftData = false
            isLoadingFallbackImage = false
            didRequestFullIssue = false
            pageZoom = 1
            lastPageZoom = 1
            loadingImagePaths.removeAll()
        }
        .onChange(of: selectedPage) { _, _ in
            clampSelectedPage()
            startMarginNotesBadgeListener()
            if !decodedPages.isEmpty {
                hydrateSelectedPageImagesIfNeeded()
                return
            }
            loadSelectedFallbackImage()
        }
        .onChange(of: decodedPages.count) { _, _ in
            clampSelectedPage()
            hydrateSelectedPageImagesIfNeeded()
        }
        .sheet(isPresented: $showMarginNotes) {
            MarginNotesSheet(magazineID: issue.id, pageIndex: selectedPage)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAddGroupsSheet) {
            AddPublishedIssueToGroupsSheet(issue: activeIssue)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var pageReader: some View {
        TabView(selection: $selectedPage) {
            if !decodedPages.isEmpty {
                ForEach(Array(decodedPages.enumerated()), id: \.offset) { index, page in
                    SinglePageCanvas(page: .constant(page), editable: false)
                        .frame(width: pageWidth * pageZoom, height: pageHeight * pageZoom)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
                        .padding(.horizontal, 16)
                        .tag(index)
                }
            } else {
                ForEach(0..<fallbackPageCount, id: \.self) { index in
                    fallbackPageView(index: index)
                        .tag(index)
                }
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

    private var displayTitle: String {
        let cleanTitle = issue.title.replacingOccurrences(of: "Draft ", with: "")
        if cleanTitle.localizedCaseInsensitiveContains("issue") {
            return cleanTitle
        }

        let suffix = (AppLanguage(rawValue: languageRaw) ?? .english) == .spanish ? "Edición" : "Issue"
        return "\(cleanTitle) \(localizedFullMonthName(for: issue.month, languageRaw: languageRaw)) \(suffix)"
    }
    
    private func loadEditablePages() {
        guard Auth.auth().currentUser?.uid != nil else {
            print("BLOCKED_QUERY_NO_AUTH", "PublishedIssueDetailView.loadEditablePages", issue.id)
            return
        }

        if let pageDraftData = activeIssue.pageDraftData, !pageDraftData.isEmpty {
            isLoadingDraftData = true
            print("PUBLISHED_INLINE_DECODE_START", issue.id, "length", pageDraftData.count)
            decodeDraftData(pageDraftData, decodeImages: false) {
                isLoadingDraftData = false
                if decodedPages.isEmpty {
                    loadPageImagesFallback()
                } else {
                    hydrateSelectedPageImagesIfNeeded()
                }
            }
            return
        }

        if activeIssue.pageDraftDataPath != nil {
            isLoadingDraftData = true
            print("PUBLISHED_PAGE_DRAFT_DATA_PATH_EXISTS", issue.id, activeIssue.pageDraftDataPath ?? "")
            print("PUBLISHED_STORED_JSON_LOAD_START", issue.id)
            FirestoreManager.shared.loadStoredString(path: activeIssue.pageDraftDataPath) { value in
                guard isViewActive else { return }
                guard let value, !value.isEmpty else {
                    print("PUBLISHED_STORED_JSON_LOAD_FAILED", issue.id)
                    isLoadingDraftData = false
                    return
                }

                print("PUBLISHED_STORED_JSON_LOAD_SUCCESS", issue.id, "length", value.count)
                decodeDraftData(value, decodeImages: false) {
                    isLoadingDraftData = false
                    hydrateSelectedPageImagesIfNeeded()
                }
            }
            return
        }

        if source == .group && !allowBase64Fallback {
            isLoadingDraftData = false
            print("GROUP_DETAIL_LOAD_DRAFTDATA_END", issue.id, "missing pageDraftDataPath", "bytes", 0)
            return
        }

        if hydratedIssue == nil && !didRequestFullIssue {
            didRequestFullIssue = true
            isLoadingDraftData = true
            FirestoreManager.shared.fetchPublishedIssue(id: issue.id) { fullIssue in
                guard isViewActive else { return }
                hydratedIssue = fullIssue
                isLoadingDraftData = false
                loadEditablePages()
            }
            return
        }

        loadPageImagesFallback()
    }

    @ViewBuilder
    private func fallbackPageView(index: Int) -> some View {
        if index == selectedFallbackImageIndex, let selectedFallbackImage {
            Image(uiImage: selectedFallbackImage)
                .resizable()
                .scaledToFit()
                .frame(width: pageWidth * pageZoom, height: pageHeight * pageZoom)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
                .padding(.horizontal, 16)
        } else {
            ProgressView()
                .frame(width: pageWidth * pageZoom, height: pageHeight * pageZoom)
                .padding(.horizontal, 16)
                .onAppear {
                    if index == selectedPage {
                        loadSelectedFallbackImage()
                    }
                }
        }
    }

    private func decodeDraftData(
        _ value: String?,
        decodeImages: Bool,
        completion: @escaping () -> Void
    ) {
        guard Auth.auth().currentUser?.uid != nil else {
            print("BLOCKED_QUERY_NO_AUTH", "PublishedIssueDetailView.decodeDraftData", issue.id)
            completion()
            return
        }

        let rawValue = value
        guard let rawValue, !rawValue.isEmpty else {
            print("PUBLISHED_DECODE_SKIPPED_EMPTY", issue.id)
            completion()
            return
        }

        print("PUBLISHED_DECODE_START", issue.id, "length", rawValue.count)
        DispatchQueue.global(qos: .userInitiated).async {
            guard Auth.auth().currentUser?.uid != nil else {
                print("BLOCKED_QUERY_NO_AUTH", "PublishedIssueDetailView.decodeDraftData background", issue.id)
                DispatchQueue.main.async {
                    completion()
                }
                return
            }

            let pages = MagazineDraftCodec.decode(rawValue, decodeImages: decodeImages)
            DispatchQueue.main.async {
                guard isViewActive else { return }
                guard Auth.auth().currentUser?.uid != nil else {
                    print("BLOCKED_QUERY_NO_AUTH", "PublishedIssueDetailView.decodeDraftData assign", issue.id)
                    completion()
                    return
                }

                decodedPages = pages
                print("PUBLISHED_DECODE_SUCCESS", issue.id, "pageCount", pages.count)
                selectedPage = min(selectedPage, max(decodedPages.count - 1, 0))
                hydrateSelectedPageImagesIfNeeded()
                completion()
            }
        }
    }

    private func hydrateSelectedPageImagesIfNeeded() {
        guard decodedPages.indices.contains(selectedPage) else { return }
        for index in decodedPages[selectedPage].elements.indices {
            guard decodedPages[selectedPage].elements[index].type == .image,
                  decodedPages[selectedPage].elements[index].image == nil,
                  let path = decodedPages[selectedPage].elements[index].imageStoragePath,
                  !path.isEmpty,
                  !loadingImagePaths.contains(path) else { continue }

            let elementID = decodedPages[selectedPage].elements[index].id
            loadingImagePaths.insert(path)
            let start = CFAbsoluteTimeGetCurrent()
            FirestoreManager.shared.loadStoredUIImage(path: path, maxPixelSize: 850) { image in
                let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                loadingImagePaths.remove(path)
                guard decodedPages.indices.contains(selectedPage),
                      let currentIndex = decodedPages[selectedPage].elements.firstIndex(where: { $0.id == elementID }) else { return }
                if let image {
                    decodedPages[selectedPage].elements[currentIndex].image = image
                    print("PUBLISHED_VISIBLE_IMAGE_LOAD_END", issue.id, "page", selectedPage, "elapsedMs", elapsed)
                } else {
                    print("PUBLISHED_VISIBLE_IMAGE_LOAD_FAILED", issue.id, "page", selectedPage, "elapsedMs", elapsed)
                }
            }
        }
    }

    private func loadPageImagesFallback() {
        guard canUseBase64Fallback else { return }
        clampSelectedPage()
        loadSelectedFallbackImage()
    }

    private func loadSelectedFallbackImage() {
        guard Auth.auth().currentUser?.uid != nil else {
            print("BLOCKED_QUERY_NO_AUTH", "PublishedIssueDetailView.loadSelectedFallbackImage", issue.id)
            return
        }

        guard canUseBase64Fallback else { return }
        guard isViewActive, decodedPages.isEmpty, fallbackPageCount > 0 else { return }
        let index = min(selectedPage, fallbackPageCount - 1)

        if selectedFallbackImageIndex == index, selectedFallbackImage != nil {
            return
        }

        selectedFallbackImage = nil
        selectedFallbackImageIndex = nil

        if activeIssue.pageImagePaths.indices.contains(index) {
            isLoadingFallbackImage = true
            FirestoreManager.shared.loadStoredImage(path: activeIssue.pageImagePaths[index]) { value in
                guard isViewActive, selectedPage == index else { return }
                selectedFallbackImage = decodeFallbackImage(value)
                selectedFallbackImageIndex = selectedFallbackImage == nil ? nil : index
                isLoadingFallbackImage = false
            }
            return
        }

        if fallbackPageImageData.indices.contains(index) {
            selectedFallbackImage = decodeFallbackImage(fallbackPageImageData[index])
            selectedFallbackImageIndex = selectedFallbackImage == nil ? nil : index
        }
    }

    private func decodeFallbackImage(_ value: String?) -> UIImage? {
        if hasEditableDraftDataPath || !allowBase64Fallback {
            print("ERROR imageFromBase64 blocked while pageDraftDataPath exists", issue.id, "pathExists", hasEditableDraftDataPath)
            return nil
        }

        return imageFromBase64(value)
    }
    
    private func clampSelectedPage() {
        let count = decodedPages.isEmpty ? fallbackPageCount : decodedPages.count
        selectedPage = min(max(selectedPage, 0), max(count - 1, 0))
        if count == 0 {
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
