import SwiftUI

// MARK: Notification Settings

struct NotificationSettingsView: View {
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    @StateObject private var permissionManager = NotificationPermissionManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var preferences = NotificationPreferences()
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var message = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(appText("Notifications", languageRaw))
                        .font(.system(size: 34, weight: .light, design: .serif))
                    Text(appText("Choose what PenPal can notify you about.", languageRaw))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                permissionStatusCard

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                } else {
                    settingsCard
                }

                if !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(PenPalStyle.background.ignoresSafeArea())
        .navigationTitle(appText("Notifications", languageRaw))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            load()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                permissionManager.refreshStatus()
            }
        }
    }

    private var permissionStatusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: permissionManager.status == .enabled ? "bell.badge" : "bell.slash")
                    .frame(width: 34, height: 34)
                    .background(Color.black.opacity(0.08))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(appText("iPhone notifications", languageRaw))
                        .font(.headline)
                    Text(appText(permissionManager.status.displayText, languageRaw))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if permissionManager.status == .disabled {
                Text(appText("Notifications are disabled in iPhone Settings.", languageRaw))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    permissionManager.openSettings()
                } label: {
                    Text(appText("Open iPhone Settings", languageRaw))
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: Binding(
                get: { preferences.masterEnabled },
                set: { updateMaster($0) }
            )) {
                Text(appText("Allow PenPal notifications", languageRaw))
                    .font(.headline)
            }
            .tint(.black)

            Divider()

            preferenceToggle("Friend requests and new friends", binding: \.friendActivity)
            preferenceToggle("Group invitations and group updates", binding: \.groupUpdates)
            preferenceToggle("New magazines", binding: \.newMagazines)
            preferenceToggle("Magazine activity", binding: \.magazineActivity)
            preferenceToggle("Margin notes", binding: \.marginNotes)
            preferenceToggle("Replies and reactions", binding: \.repliesAndReactions)
            preferenceToggle("PenPal announcements", binding: \.penPalAnnouncements)

            if isSaving {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(appText("Saving...", languageRaw))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func preferenceToggle(
        _ title: String,
        binding keyPath: WritableKeyPath<NotificationPreferences, Bool>
    ) -> some View {
        Toggle(isOn: Binding(
            get: { preferences[keyPath: keyPath] },
            set: { value in
                preferences[keyPath: keyPath] = value
                savePreferences()
            }
        )) {
            Text(appText(title, languageRaw))
                .font(.subheadline)
        }
        .tint(.black)
        .disabled(!preferences.masterEnabled)
    }

    private func load() {
        permissionManager.refreshStatus()
        FirestoreManager.shared.fetchNotificationPreferences { loaded in
            preferences = loaded
            isLoading = false
        }
    }

    private func updateMaster(_ enabled: Bool) {
        if enabled, permissionManager.status == .notDetermined {
            permissionManager.requestPermission { granted in
                preferences.masterEnabled = granted
                if granted {
                    preferences = .enabledDefaults
                    message = appText("Notification preferences saved.", languageRaw)
                } else {
                    message = appText("Notifications are disabled in iPhone Settings.", languageRaw)
                }
                savePreferences()
            }
            return
        }

        preferences.masterEnabled = enabled
        savePreferences()
    }

    private func savePreferences() {
        isSaving = true
        message = ""
        FirestoreManager.shared.updateNotificationPreferences(preferences) { error in
            isSaving = false
            if let error {
                message = error
            } else {
                message = appText("Notification preferences saved.", languageRaw)
            }
        }
    }
}
