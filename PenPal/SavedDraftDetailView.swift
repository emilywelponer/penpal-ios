//
//  SavedDraftDetailView.swift
//  TravelingFriends
//
//  Created by Emily on 26/05/2026.
//

import SwiftUI
import FirebaseAuth

struct SavedDraftDetailView: View {
    
    let draft: SavedIssueDraftModel
    
    @StateObject private var issueStore = IssueDraftStore.shared
    @StateObject private var groupStore = PenpalGroupStore.shared
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    @State private var selectedGroupIDs: Set<String> = []
    @State private var editablePages: [MagazinePage] = []
    @State private var previewImageData: [String] = []
    @State private var selectedPreviewPage = 0
    @State private var messageText = ""
    @State private var isLoadingDraftData = false
    @State private var isPublishing = false
    @State private var didRequestDraftData = false
    @State private var didDecodeInlineDraftData = false
    @State private var route: DraftDetailRoute?
    @State private var pendingRoute: DraftDetailRoute?
    @State private var loadingImagePaths: Set<String> = []
    @Environment(\.dismiss) private var dismiss

    private var pageWidth: CGFloat {
        min(UIScreen.main.bounds.width - 16, (UIScreen.main.bounds.height - 260) * 170.0 / 250.0)
    }

    private var pageHeight: CGFloat {
        pageWidth * 250.0 / 170.0
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                draftActions
                
                draftPreviewReader
                
                Text(appText("Publish to", languageRaw))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                ForEach(groupStore.groups) { group in
                    Button {
                        toggleGroup(group.id)
                    } label: {
                        HStack {
                            Image(systemName: selectedGroupIDs.contains(group.id) ? "checkmark.circle.fill" : "circle")
                            Text(group.name)
                            Spacer()
                        }
                        .padding()
                        .background(Color.gray.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
                
                publishButton

                if !messageText.isEmpty {
                    Text(messageText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical)
        }
        .navigationTitle(appText("Draft", languageRaw))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadDraft()
            groupStore.loadGroups()
        }
        .onChange(of: editablePages.count) { _, _ in
            clampSelectedPreviewPage()
        }
        .onChange(of: previewImageData.count) { _, _ in
            clampSelectedPreviewPage()
        }
        .onChange(of: selectedPreviewPage) { _, _ in
            hydratePreviewPageImagesIfNeeded()
        }
        .fullScreenCover(item: $route) { route in
            NavigationStack {
                Group {
                    switch route {
                    case .edit:
                        LockedMagazineEditorView(colourScheme: draftColourScheme(for: restoredPages()))
                    case .review:
                        DraftMagazineReaderView(title: draft.title)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(appText("Close", languageRaw)) {
                            self.route = nil
                        }
                    }
                }
            }
        }
        .background(PenPalStyle.background.ignoresSafeArea())
    }

    private var draftPreviewReader: some View {
        Group {
            if !previewImageData.isEmpty {
                TabView(selection: $selectedPreviewPage) {
                    ForEach(previewImageData.indices, id: \.self) { index in
                        Base64CachedImageView(
                            imageData: previewImageData[index],
                            debugID: "draft-detail-preview-\(draft.id)-\(index)"
                        ) { image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: pageWidth, height: pageHeight)
                                .clipShape(RoundedRectangle(cornerRadius: 24))
                                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
                        } placeholder: {
                            ProgressView()
                                .frame(width: pageWidth, height: pageHeight)
                        }
                        .padding(.horizontal, 16)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .frame(height: pageHeight + 36)
            } else if !editablePages.isEmpty {
                TabView(selection: $selectedPreviewPage) {
                    ForEach(editablePages.indices, id: \.self) { index in
                        SinglePageCanvas(page: .constant(editablePages[index]), editable: false)
                            .frame(width: pageWidth, height: pageHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                            .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
                            .padding(.horizontal, 16)
                            .onAppear {
                                selectedPreviewPage = index
                                hydratePreviewPageImagesIfNeeded()
                            }
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .frame(height: pageHeight + 36)
            } else if isLoadingDraftData {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(appText("Loading draft...", languageRaw))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: pageWidth, height: min(pageHeight, 260))
            } else {
                Image(systemName: "doc.text.image")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .frame(width: pageWidth, height: min(pageHeight, 260))
            }
        }
    }

    private var draftActions: some View {
        VStack(spacing: 12) {
            Button {
                openDraft(.edit)
            } label: {
                draftActionLabel(appText("Continue editing", languageRaw), systemImage: "pencil")
            }

            Button {
                openDraft(.review)
            } label: {
                draftActionLabel(appText("Review draft", languageRaw), systemImage: "book")
            }
        }
        .buttonStyle(.plain)
    }

    private var publishButton: some View {
        Button {
            publishDraft()
        } label: {
            HStack {
                Text(isPublishing ? appText("Publishing...", languageRaw) : appText("Publish draft", languageRaw))
                    .font(.headline)
                if isPublishing {
                    ProgressView()
                        .tint(.white)
                }
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding()
        .background(selectedGroupIDs.isEmpty || isPublishing ? Color.gray : Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .disabled(selectedGroupIDs.isEmpty || isPublishing || isLoadingDraftData)
    }

    private func draftActionLabel(_ title: String, systemImage: String) -> some View {
        HStack {
            Image(systemName: systemImage)
            Text(isLoadingDraftData ? appText("Loading draft...", languageRaw) : title)
                .font(.headline)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.primary)
        .padding()
        .background(Color.gray.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    
    private func toggleGroup(_ id: String) {
        if selectedGroupIDs.contains(id) {
            selectedGroupIDs.remove(id)
        } else {
            selectedGroupIDs.insert(id)
        }
    }
    
    private func clampSelectedPreviewPage() {
        let count = editablePages.isEmpty ? previewImageData.count : editablePages.count
        selectedPreviewPage = min(max(selectedPreviewPage, 0), max(count - 1, 0))
        if count == 0 {
            selectedPreviewPage = 0
        }
    }
    
    private func publishDraft() {
        guard !selectedGroupIDs.isEmpty, !isPublishing else { return }
        
        let selectedGroups = groupStore.groups.filter {
            selectedGroupIDs.contains($0.id)
        }

        var pages = restoredPages()
        if pages.isEmpty {
            pages = decodeInlineDraftDataIfPresent()
            editablePages = pages
        }
        guard !pages.isEmpty else {
            if draft.pageDraftDataPath?.isEmpty == false {
                messageText = appText("Loading draft... Please wait.", languageRaw)
                loadStoredDraftPages { loadedPages in
                    editablePages = loadedPages
                    publishDraft()
                }
            } else {
                messageText = appText("This draft has no pages to publish.", languageRaw)
            }
            return
        }

        isPublishing = true
        messageText = appText("Publishing...", languageRaw)

        let issueID = UUID().uuidString
        FirestoreManager.shared.uploadMagazineImages(
            in: pages,
            basePath: "publishedIssues/\(issueID)/images"
        ) { result in
            switch result {
            case .failure(let error):
                isPublishing = false
                messageText = "\(appText("Issue could not be published:", languageRaw)) \(error.localizedDescription)"

            case .success(let preparedPages):
                editablePages = preparedPages
                guard let pageDraftData = MagazineDraftCodec.encode(preparedPages) else {
                    isPublishing = false
                    messageText = appText("Issue could not be prepared for publishing.", languageRaw)
                    return
                }

                FirestoreManager.shared.publishIssueToGroups(
                    title: publishedIssueTitle,
                    groups: selectedGroups,
                    pageImageData: [],
                    pageDraftData: pageDraftData,
                    issueID: issueID,
                    colourScheme: draftColourScheme(for: preparedPages)
                ) { error in
                    DispatchQueue.main.async {
                        isPublishing = false
                        if let error {
                            messageText = "\(appText("Issue could not be published:", languageRaw)) \(error)"
                            return
                        }

                        messageText = appText("Issue published.", languageRaw)
                        FirestoreManager.shared.deleteIssueDraft(draft)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private func loadDraft() {
        if draft.isLocalDraft, let localID = draft.localDraftID ?? Optional(draft.id) {
            guard editablePages.isEmpty else { return }
            isLoadingDraftData = true
            DispatchQueue.global(qos: .userInitiated).async {
                let pages = (try? LocalIssueDraftStore.loadPages(id: localID)) ?? []
                DispatchQueue.main.async {
                    editablePages = pages
                    isLoadingDraftData = false
                    selectedPreviewPage = 0
                    hydratePreviewPageImagesIfNeeded()
                }
            }
            return
        }

        guard previewImageData.isEmpty, editablePages.isEmpty else { return }

        previewImageData = Array(draft.pageImageData.prefix(1))
        
        if previewImageData.isEmpty, let firstPreviewPath = draft.previewImagePaths.first {
            FirestoreManager.shared.loadStoredImages(paths: [firstPreviewPath]) { values in
                previewImageData = values
                selectedPreviewPage = 0
            }
        }
    }

    private var canOpenDraft: Bool {
        !isLoadingDraftData && !restoredPages().isEmpty
    }

    private func openDraft(_ destination: DraftDetailRoute) {
        if draft.isLocalDraft, let localID = draft.localDraftID ?? Optional(draft.id), editablePages.isEmpty {
            isLoadingDraftData = true
            messageText = appText("Loading draft...", languageRaw)
            DispatchQueue.global(qos: .userInitiated).async {
                let pages = (try? LocalIssueDraftStore.loadPages(id: localID)) ?? []
                DispatchQueue.main.async {
                    isLoadingDraftData = false
                    editablePages = pages
                    guard !pages.isEmpty else {
                        messageText = appText("This draft has no editable pages.", languageRaw)
                        return
                    }
                    assignPagesAndNavigate(pages, to: destination)
                }
            }
            return
        }

        var pages = restoredPages()
        if pages.isEmpty {
            pages = decodeInlineDraftDataIfPresent()
            editablePages = pages
        }

        if pages.isEmpty, isLoadingDraftData {
            pendingRoute = destination
            messageText = appText("Loading draft...", languageRaw)
            return
        }

        if pages.isEmpty,
           draft.pageDraftDataPath != nil,
           !isLoadingDraftData {
            pendingRoute = destination
            messageText = appText("Loading draft... Please wait.", languageRaw)
            loadStoredDraftPages { pages in
                editablePages = pages
                let loadedPages = restoredPages()
                guard !loadedPages.isEmpty else {
                    messageText = appText("This draft has no editable pages.", languageRaw)
                    pendingRoute = nil
                    return
                }

                pendingRoute = nil
                assignPagesAndNavigate(loadedPages, to: destination)
            }
            return
        }

        guard !pages.isEmpty else {
            messageText = appText("This draft is still loading or has no editable pages.", languageRaw)
            return
        }

        assignPagesAndNavigate(pages, to: destination)
    }

    private func hydratePreviewPageImagesIfNeeded() {
        guard editablePages.indices.contains(selectedPreviewPage) else { return }
        for index in editablePages[selectedPreviewPage].elements.indices {
            guard editablePages[selectedPreviewPage].elements[index].type == .image,
                  editablePages[selectedPreviewPage].elements[index].image == nil else { continue }

            let elementID = editablePages[selectedPreviewPage].elements[index].id

            if let localPath = editablePages[selectedPreviewPage].elements[index].localImagePath, !localPath.isEmpty {
                DispatchQueue.global(qos: .userInitiated).async {
                    let image = downsampledImageFromFile(path: localPath, maxPixelSize: 850)
                    DispatchQueue.main.async {
                        guard editablePages.indices.contains(selectedPreviewPage),
                              let currentIndex = editablePages[selectedPreviewPage].elements.firstIndex(where: { $0.id == elementID }) else { return }
                        editablePages[selectedPreviewPage].elements[currentIndex].image = image
                    }
                }
                continue
            }

            if let path = editablePages[selectedPreviewPage].elements[index].imageStoragePath,
               !path.isEmpty,
               !loadingImagePaths.contains(path) {
                loadingImagePaths.insert(path)
                FirestoreManager.shared.loadStoredUIImage(path: path, maxPixelSize: 850) { image in
                    loadingImagePaths.remove(path)
                    guard editablePages.indices.contains(selectedPreviewPage),
                          let currentIndex = editablePages[selectedPreviewPage].elements.firstIndex(where: { $0.id == elementID }) else { return }
                    editablePages[selectedPreviewPage].elements[currentIndex].image = image
                }
            }
        }
    }

    private func assignPagesAndNavigate(_ pages: [MagazinePage], to destination: DraftDetailRoute) {
        messageText = appText("Opening editor...", languageRaw)
        issueStore.pages = pages
        issueStore.currentDraftID = draft.id
        issueStore.currentDraftTitle = draft.title
        issueStore.currentColourScheme = draftColourScheme(for: pages)
        MagazineTemplateFactory.renumberPages(&issueStore.pages)
        route = destination
    }

    private func draftColourScheme(for pages: [MagazinePage]) -> PenPalColourScheme {
        if let raw = draft.colourSchemeRaw,
           let scheme = PenPalColourScheme(rawValue: raw) {
            return scheme
        }
        return PenPalColourScheme.inferred(from: pages) ?? .clean
    }

    private func restoredPages() -> [MagazinePage] {
        if !editablePages.isEmpty {
            return editablePages
        }

        return []
    }

    private func decodeInlineDraftDataIfPresent() -> [MagazinePage] {
        guard !didDecodeInlineDraftData else {
            return editablePages
        }

        guard let pageDraftData = draft.pageDraftData, !pageDraftData.isEmpty else {
            if draft.pageDraftDataPath?.isEmpty == false {
                print("DRAFT_PAGE_DRAFT_DATA_PATH_EXISTS", draft.id, draft.pageDraftDataPath ?? "")
            }
            return []
        }

        print("DRAFT_INLINE_DECODE_START", draft.id, "length", pageDraftData.count)
        let pages = MagazineDraftCodec.decode(pageDraftData, decodeImages: false)
        print("DRAFT_INLINE_DECODE_SUCCESS", draft.id, "pageCount", pages.count)
        didDecodeInlineDraftData = true
        return pages
    }

    private func loadStoredDraftPages(completion: @escaping ([MagazinePage]) -> Void) {
        guard let path = draft.pageDraftDataPath, !path.isEmpty else {
            isLoadingDraftData = false
            completion([])
            return
        }

        guard !didRequestDraftData else {
            completion(editablePages)
            return
        }

        didRequestDraftData = true
        isLoadingDraftData = true
        print("DRAFT_PAGE_DRAFT_DATA_PATH_EXISTS", draft.id, path)
        print("DRAFT_STORED_JSON_LOAD_START", draft.id, path)
        FirestoreManager.shared.loadStoredString(path: path) { value in
            isLoadingDraftData = false
            guard let value, !value.isEmpty else {
                print("DRAFT_STORED_JSON_LOAD_FAILED", draft.id, path)
                completion([])
                return
            }

            print("DRAFT_STORED_JSON_LOAD_SUCCESS", draft.id, "length", value.count)
            print("DRAFT_DECODE_START", draft.id)
            let decodeStart = CFAbsoluteTimeGetCurrent()
            DispatchQueue.global(qos: .userInitiated).async {
                let pages = MagazineDraftCodec.decode(value, decodeImages: false)
                DispatchQueue.main.async {
                    let elapsed = Int((CFAbsoluteTimeGetCurrent() - decodeStart) * 1000)
                    print("DRAFT_DECODE_SUCCESS", draft.id, "pageCount", pages.count, "elapsedMs", elapsed)
                    completion(pages)
                }
            }
        }
    }

    private var publishedIssueTitle: String {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: Date())
        let owner = draft.title
            .replacingOccurrences(of: " Draft Issue", with: "")
            .replacingOccurrences(of: " Draft", with: "")
        return localizedIssueTitle(owner: owner, month: month, languageRaw: languageRaw)
            .replacingOccurrences(of: "'s's", with: "'s")
    }
}

private enum DraftDetailRoute: String, Identifiable {
    case edit
    case review

    var id: String { rawValue }
}

private struct DraftMagazineReaderView: View {
    @StateObject private var issueStore = IssueDraftStore.shared
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    @State private var selectedPage = 0
    @State private var loadingImagePaths: Set<String> = []
    let title: String

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

                if issueStore.pages.isEmpty {
                    Spacer()
                    Text(appText("No pages saved.", languageRaw))
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    if issueStore.pages.indices.contains(selectedPage) {
                        SinglePageCanvas(page: .constant(issueStore.pages[selectedPage]), editable: false)
                            .frame(width: pageWidth, height: pageHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                            .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
                            .padding(.horizontal, 16)

                        HStack {
                            Button {
                                selectedPage = max(0, selectedPage - 1)
                            } label: {
                                Image(systemName: "chevron.left")
                            }
                            .disabled(selectedPage == 0)

                            Spacer()

                            Text("\(appText("Page", languageRaw)) \(min(selectedPage + 1, issueStore.pages.count)) / \(issueStore.pages.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button {
                                selectedPage = min(max(issueStore.pages.count - 1, 0), selectedPage + 1)
                            } label: {
                                Image(systemName: "chevron.right")
                            }
                            .disabled(selectedPage >= issueStore.pages.count - 1)
                        }
                        .padding(.horizontal, 24)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PenPalStyle.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    LockedMagazineEditorView(
                        colourScheme: issueStore.currentColourScheme ?? PenPalColourScheme.inferred(from: issueStore.pages) ?? .clean,
                        initialPageIndex: selectedPage
                    )
                } label: {
                    Text(appText("Edit", languageRaw))
                }
            }
        }
        .onChange(of: issueStore.pages.count) { _, _ in
            clampSelectedPage()
            hydrateSelectedPageImagesIfNeeded()
        }
        .onChange(of: selectedPage) { _, _ in
            hydrateSelectedPageImagesIfNeeded()
        }
        .onAppear {
            hydrateSelectedPageImagesIfNeeded()
        }
    }

    private var displayTitle: String {
        title
            .replacingOccurrences(of: " Draft Issue", with: " Issue")
            .replacingOccurrences(of: "Draft ", with: "")
    }
    
    private func clampSelectedPage() {
        selectedPage = min(max(selectedPage, 0), max(issueStore.pages.count - 1, 0))
        if issueStore.pages.isEmpty {
            selectedPage = 0
        }
    }

    private func hydrateSelectedPageImagesIfNeeded() {
        guard issueStore.pages.indices.contains(selectedPage) else { return }
        for index in issueStore.pages[selectedPage].elements.indices {
            guard issueStore.pages[selectedPage].elements[index].type == .image,
                  issueStore.pages[selectedPage].elements[index].image == nil else { continue }
            let elementID = issueStore.pages[selectedPage].elements[index].id

            if let localPath = issueStore.pages[selectedPage].elements[index].localImagePath, !localPath.isEmpty {
                DispatchQueue.global(qos: .userInitiated).async {
                    let image = downsampledImageFromFile(path: localPath, maxPixelSize: 850)
                    DispatchQueue.main.async {
                        guard issueStore.pages.indices.contains(selectedPage),
                              let currentIndex = issueStore.pages[selectedPage].elements.firstIndex(where: { $0.id == elementID }) else { return }
                        issueStore.pages[selectedPage].elements[currentIndex].image = image
                    }
                }
                continue
            }

            if let path = issueStore.pages[selectedPage].elements[index].imageStoragePath,
               !path.isEmpty,
               !loadingImagePaths.contains(path) {
                loadingImagePaths.insert(path)
                FirestoreManager.shared.loadStoredUIImage(path: path, maxPixelSize: 850) { image in
                    loadingImagePaths.remove(path)
                    guard issueStore.pages.indices.contains(selectedPage),
                          let currentIndex = issueStore.pages[selectedPage].elements.firstIndex(where: { $0.id == elementID }) else { return }
                    issueStore.pages[selectedPage].elements[currentIndex].image = image
                }
            }
        }
    }
}
