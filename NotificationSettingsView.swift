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
                    masterPreferenceCard
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
        Button {
            handlePermissionCardTap()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: permissionManager.status == .enabled ? "bell.badge" : "bell.slash")
                        .frame(width: 34, height: 34)
                        .background(Color.black.opacity(0.08))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(appText("iPhone notifications", languageRaw))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(appText(permissionManager.status.displayText, languageRaw))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: permissionManager.status == .notDetermined ? "bell.badge" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if permissionManager.status == .disabled {
                    Text(appText("Notifications are disabled in iPhone Settings.", languageRaw))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if permissionManager.status == .enabled {
                    Text(appText("Manage iPhone notification delivery in Settings.", languageRaw))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(appText("Tap to allow iPhone notifications for PenPal.", languageRaw))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    private var masterPreferenceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(
                get: { preferences.masterEnabled },
                set: { updateMaster($0) }
            )) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(appText("Allow PenPal notifications", languageRaw))
                        .font(.headline)
                    Text(appText("Covers friend requests, groups, magazines, activity, margin notes and PenPal announcements.", languageRaw))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.black)

            if permissionManager.status == .disabled {
                HStack(spacing: 10) {
                    Text(appText("Enable notifications in iPhone Settings to receive PenPal notifications.", languageRaw))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        permissionManager.openSettings()
                    } label: {
                        Text(appText("Open Settings", languageRaw))
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                }
            }

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
                if granted {
                    preferences = .enabledDefaults
                    message = appText("Notification preferences saved.", languageRaw)
                } else {
                    preferences.masterEnabled = false
                    message = appText("Notifications are disabled in iPhone Settings.", languageRaw)
                }
                savePreferences()
            }
            return
        }

        if enabled, permissionManager.status == .disabled {
            preferences.masterEnabled = false
            message = appText("Enable notifications in iPhone Settings to receive PenPal notifications.", languageRaw)
            return
        }

        preferences.masterEnabled = enabled
        savePreferences()
    }

    private func handlePermissionCardTap() {
        switch permissionManager.status {
        case .notDetermined:
            permissionManager.requestPermission { granted in
                if granted {
                    preferences = .enabledDefaults
                    savePreferences()
                }
            }
        case .disabled, .enabled:
            permissionManager.openSettings()
        }
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
