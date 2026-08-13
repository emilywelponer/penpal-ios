import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: Margin Notes Feature

struct MarginNotesEnvelopeButton: View {
    let hasNotes: Bool
    let action: () -> Void
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "envelope")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(PenPalStyle.ink.opacity(0.34))
                    .frame(width: 34, height: 34)

                if hasNotes {
                    Circle()
                        .fill(Color.red.opacity(0.62))
                        .frame(width: 6, height: 6)
                        .offset(x: -7, y: 7)
                }
            }
            .background(
                Circle()
                    .fill(PenPalStyle.card.opacity(0.34))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(appText("Margin Notes", languageRaw))
    }
}

struct MarginNotesSheet: View {
    let magazineID: String
    let pageIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var notes: [MarginNote] = []
    @State private var draftText = ""
    @State private var listener: ListenerRegistration?
    @State private var isSaving = false
    @State private var errorText = ""
    @State private var didSeedOwnNote = false
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue

    private var ownNote: MarginNote? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        return notes.first { $0.authorID == uid }
    }

    private var remainingCharacters: Int {
        max(0, 250 - draftText.count)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if notes.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "envelope.open")
                            .font(.title3)
                            .foregroundStyle(PenPalStyle.muted)

                        Text(appText("No margin notes on this page yet.", languageRaw))
                            .font(.system(size: 15, weight: .regular, design: .serif))
                            .foregroundStyle(PenPalStyle.muted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .padding(.top, 12)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(notes) { note in
                                MarginNoteRow(note: note)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text(appText(ownNote == nil ? "Leave a Note" : "Edit Your Note", languageRaw))
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .foregroundStyle(PenPalStyle.ink)

                    TextEditor(text: $draftText)
                        .scrollContentBackground(.hidden)
                        .background(PenPalStyle.cardAlt)
                        .frame(minHeight: 92, maxHeight: 118)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(PenPalStyle.border, lineWidth: 1)
                        )
                        .onChange(of: draftText) { _, newValue in
                            if newValue.count > 250 {
                                draftText = String(newValue.prefix(250))
                            }
                        }

                    HStack {
                        Text(localizedRemainingCharacters(remainingCharacters, languageRaw: languageRaw))
                            .font(.caption)
                            .foregroundStyle(PenPalStyle.muted)

                        Spacer()

                        if isSaving {
                            ProgressView()
                        }

                        Button(appText(ownNote == nil ? "Save Note" : "Update Note", languageRaw)) {
                            saveNote()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaving || draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if !errorText.isEmpty {
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(18)
            }
            .background(PenPalStyle.background.ignoresSafeArea())
            .navigationTitle(appText("Margin Notes", languageRaw))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(appText("Done", languageRaw)) {
                        dismiss()
                    }
                }
            }
            .onAppear(perform: startListening)
            .onDisappear {
                listener?.remove()
                listener = nil
            }
            .onChange(of: notes) { _, _ in
                seedOwnNoteIfNeeded()
            }
        }
    }

    private func startListening() {
        listener?.remove()
        listener = MarginNotesService.shared.listen(magazineID: magazineID, pageIndex: pageIndex) { result in
            switch result {
            case .success(let notes):
                self.notes = notes
                self.errorText = ""
            case .failure(let error):
                self.notes = []
                self.errorText = error.localizedDescription
                print("MARGIN_NOTES_LISTEN_ERROR", magazineID, pageIndex, error.localizedDescription)
            }
        }
    }

    private func seedOwnNoteIfNeeded() {
        guard !didSeedOwnNote, let ownNote else { return }
        didSeedOwnNote = true
        draftText = ownNote.text
    }

    private func saveNote() {
        isSaving = true
        errorText = ""

        MarginNotesService.shared.saveNote(magazineID: magazineID, pageIndex: pageIndex, text: draftText) { result in
            isSaving = false
            switch result {
            case .success:
                didSeedOwnNote = false
                seedOwnNoteIfNeeded()
            case .failure(let error):
                errorText = error.localizedDescription
                print("MARGIN_NOTES_SAVE_ERROR", magazineID, pageIndex, error.localizedDescription)
            }
        }
    }
}

private struct MarginNoteRow: View {
    let note: MarginNote

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MarginNoteAvatar(note: note)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(note.authorDisplayName.isEmpty ? note.authorUsername : note.authorDisplayName)
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                        .foregroundStyle(PenPalStyle.ink)

                    Spacer()

                    Text(note.updatedAt, style: .date)
                        .font(.caption2)
                        .foregroundStyle(PenPalStyle.muted)
                }

                Text(note.text)
                    .font(.system(size: 14, weight: .regular, design: .serif))
                    .foregroundStyle(PenPalStyle.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(PenPalStyle.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(PenPalStyle.border, lineWidth: 1)
        )
    }
}

private struct MarginNoteAvatar: View {
    let note: MarginNote

    var body: some View {
        Group {
            if let rawURL = note.authorPhotoURL, let url = URL(string: rawURL), !rawURL.isEmpty {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    initials
                }
            } else {
                initials
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(Circle())
    }

    private var initials: some View {
        Circle()
            .fill(PenPalStyle.cardAlt)
            .overlay(
                Text(String((note.authorDisplayName.isEmpty ? note.authorUsername : note.authorDisplayName).prefix(1)).uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PenPalStyle.ink)
            )
    }
}
