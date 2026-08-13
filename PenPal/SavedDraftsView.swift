//
//  Untitled.swift
//  TravelingFriends
//
//  Created by Emily on 26/05/2026.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SavedDraftsView: View {
    
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    @State private var drafts: [SavedIssueDraftModel] = []
    @State private var draftToDelete: SavedIssueDraftModel?
    @State private var draftListener: ListenerRegistration?
    
    var body: some View {
        List {
            if drafts.isEmpty {
                Text(appText("No drafts yet — start your first issue and save it here.", languageRaw))
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
                ForEach(drafts) { draft in
                    NavigationLink {
                        SavedDraftDetailView(draft: draft)
                    } label: {
                        SavedDraftRow(draft: draft)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions {
                        Button(role: .destructive) {
                            draftToDelete = draft
                        } label: {
                            Label(appText("Delete", languageRaw), systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(PenPalStyle.background.ignoresSafeArea())
        .navigationTitle(appText("Saved Drafts", languageRaw))
        .toolbarBackground(PenPalStyle.background, for: .navigationBar)
        .onAppear {
            loadLocalDrafts()
            guard Auth.auth().currentUser?.uid != nil else {
                print("BLOCKED_QUERY_NO_AUTH", "SavedDraftsView.onAppear")
                return
            }

            FirestoreManager.shared.removeListener(draftListener)
            draftListener = FirestoreManager.shared.listenToMyIssueDrafts { cloudDrafts in
                DispatchQueue.main.async {
                    self.mergeCloudDrafts(cloudDrafts)
                }
            }
        }
        .onDisappear {
            FirestoreManager.shared.removeListener(draftListener)
            draftListener = nil
        }
        .alert(appText("Delete draft?", languageRaw), isPresented: Binding(
            get: { draftToDelete != nil },
            set: { if !$0 { draftToDelete = nil } }
        )) {
            Button(appText("Cancel", languageRaw), role: .cancel) {
                draftToDelete = nil
            }

            Button(appText("Delete", languageRaw), role: .destructive) {
                if let draft = draftToDelete {
                    if draft.isLocalDraft, let localID = draft.localDraftID {
                        try? LocalIssueDraftStore.delete(id: localID)
                    } else {
                        FirestoreManager.shared.deleteIssueDraft(draft)
                    }
                    drafts.removeAll { $0.id == draft.id }
                }

                draftToDelete = nil
            }
        } message: {
            Text(appText("This draft will be permanently removed.", languageRaw))
        }
    }

    private func loadLocalDrafts() {
        drafts = LocalIssueDraftStore.list().map { info in
            SavedIssueDraftModel(
                id: info.id,
                title: info.title,
                ownerID: Auth.auth().currentUser?.uid ?? "local",
                createdAt: info.updatedAt,
                pageImageData: [],
                previewImagePaths: [],
                pageDraftData: nil,
                pageDraftDataPath: nil,
                updatedAt: info.updatedAt,
                colourSchemeRaw: info.colourSchemeRaw,
                isLocalDraft: true,
                localDraftID: info.id,
                previewLocalImagePath: info.previewImagePath
            )
        }
    }

    private func mergeCloudDrafts(_ cloudDrafts: [SavedIssueDraftModel]) {
        let localIDs = Set(drafts.compactMap { $0.localDraftID ?? ($0.isLocalDraft ? $0.id : nil) })
        let filteredCloud = cloudDrafts.filter { !localIDs.contains($0.id) }
        drafts = (drafts.filter { $0.isLocalDraft } + filteredCloud)
            .sorted { ($0.updatedAt ?? $0.createdAt) > ($1.updatedAt ?? $1.createdAt) }
    }
}

private struct SavedDraftRow: View {
    let draft: SavedIssueDraftModel
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    @State private var previewImageData: String?
    @State private var firstLocalPage: MagazinePage?
    @State private var isLoadingPreview = false
    
    private var displayDate: Date {
        draft.updatedAt ?? draft.createdAt
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let localPath = draft.previewLocalImagePath,
                   let image = downsampledImageFromFile(path: localPath, maxPixelSize: 220) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else if let firstLocalPage {
                    DraftRowPageMiniature(page: firstLocalPage)
                } else if let imageData = previewImageData ?? draft.pageImageData.first {
                    Base64CachedImageView(
                        imageData: imageData,
                        debugID: "draft-row-\(draft.id)"
                    ) { image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    } placeholder: {
                        Image(systemName: "doc.text.image")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "doc.text.image")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 48, height: 70)
            .background(Color.gray.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 6) {
                Text(draft.title)
                    .font(.headline)
                
                Text(localizedDateTime(displayDate, languageRaw: languageRaw))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 2)
        .onAppear {
            loadPreviewIfNeeded()
        }
    }
    
    private func loadPreviewIfNeeded() {
        if firstLocalPage == nil, draft.isLocalDraft, let localID = draft.localDraftID {
            DispatchQueue.global(qos: .utility).async {
                let page = (try? LocalIssueDraftStore.loadPages(id: localID).first)
                DispatchQueue.main.async {
                    firstLocalPage = page
                }
            }
            return
        }

        guard Auth.auth().currentUser?.uid != nil else {
            print("BLOCKED_QUERY_NO_AUTH", "SavedDraftRow.loadPreviewIfNeeded", draft.id)
            return
        }

        guard !isLoadingPreview else { return }
        isLoadingPreview = true

        guard previewImageData == nil,
              let path = draft.previewImagePaths.first
        else {
            isLoadingPreview = false
            return
        }
        
        FirestoreManager.shared.loadStoredImages(paths: [path]) { values in
            previewImageData = values.first
            isLoadingPreview = false
        }
    }
}

private struct DraftRowPageMiniature: View {
    let page: MagazinePage

    var body: some View {
        GeometryReader { proxy in
            let scaleX = proxy.size.width / 170.0
            let scaleY = proxy.size.height / 250.0

            ZStack {
                Color(uiColor: page.backgroundColor)

                ForEach(page.elements.prefix(28)) { element in
                    let width = max(1, element.size.width * scaleX)
                    let height = max(1, element.size.height * scaleY)
                    let x = element.position.x * scaleX
                    let y = element.position.y * scaleY

                    switch element.type {
                    case .image:
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.black.opacity(0.12))
                            .frame(width: width, height: height)
                            .position(x: x, y: y)
                    case .line:
                        Rectangle()
                            .fill(Color(uiColor: page.textColor).opacity(0.3))
                            .frame(width: width, height: 0.7)
                            .position(x: x, y: y)
                    case .box:
                        RoundedRectangle(cornerRadius: 1)
                            .stroke(Color(uiColor: page.textColor).opacity(0.25), lineWidth: 0.6)
                            .frame(width: width, height: height)
                            .position(x: x, y: y)
                    case .title, .text:
                        if !element.text.isEmpty {
                            Text(String(element.text.prefix(12)))
                                .font(.system(size: max(3, min(6, element.fontSize * scaleY)), weight: element.isBold ? .bold : .regular))
                                .foregroundStyle(Color(uiColor: page.textColor).opacity(0.65))
                                .lineLimit(1)
                                .frame(width: width, height: height, alignment: .leading)
                                .position(x: x, y: y)
                        }
                    }
                }
            }
        }
        .aspectRatio(170.0 / 250.0, contentMode: .fit)
    }
}
