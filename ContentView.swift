import SwiftUI
import Combine
import FirebaseAuth

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "English"
    case german = "Deutsch"
    case italian = "Italiano"
    case spanish = "Español"
    case french = "Français"
    
    var id: String { rawValue }
}

struct PenpalProfile: Identifiable, Hashable {
    let id = UUID()
    var username: String
    var displayName: String
}

struct SavedMagazineIssue: Identifiable {
    let id = UUID()
    var title: String
    var date: Date
    var pages: [MagazinePage]
}

struct PenpalGroup: Identifiable {
    let id = UUID()
    var name: String
    var members: [PenpalProfile]
    var issues: [SavedMagazineIssue] = []
}

final class MagazineArchiveStore: ObservableObject {
    static let shared = MagazineArchiveStore()
    @Published var savedIssues: [SavedMagazineIssue] = []
    private init() {}
}

final class PenpalGroupStore: ObservableObject {
    static let shared = PenpalGroupStore()
    
    @Published var groups: [PenpalGroup] = [
        PenpalGroup(name: "Close Friends", members: []),
        PenpalGroup(name: "Family", members: []),
        PenpalGroup(name: "Creative Circle", members: [])
    ]
    
    private init() {}
}

struct ContentView: View {
    
    @AppStorage("homeResetID") private var homeResetID: String = UUID().uuidString
    @State private var firebaseUser: User? = Auth.auth().currentUser
    
    var body: some View {
        Group {
            if firebaseUser != nil {
                HomeDashboardView()
                    .id(homeResetID)
            } else {
                LoginView()
            }
        }
        .onAppear {
            firebaseUser = Auth.auth().currentUser
            
            Auth.auth().addStateDidChangeListener { _, user in
                firebaseUser = user
            }
        }
    }
}

// ============================================================
// MARK: - LOGIN
// ============================================================

struct LoginView: View {
    
    @AppStorage("username") private var savedUsername: String = ""
    @AppStorage("displayName") private var savedDisplayName: String = ""
    @AppStorage("email") private var savedEmail: String = ""
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    
    @State private var isLoginMode: Bool = true
    
    @State private var username: String = ""
    @State private var displayName: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var errorMessage: String = ""
    @State private var successMessage: String = ""
    @State private var isLoading: Bool = false
    
    @State private var showPassword: Bool = false
    @State private var showConfirmPassword: Bool = false
    
    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .english
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                
                Spacer().frame(height: 60)
                
                Text("PenPal")
                    .font(.system(size: 48, weight: .light, design: .serif))
                    .kerning(1.2)
                
                Text(isLoginMode
                     ? "Welcome back."
                     : "Create your profile to start making and sharing your magazine.")
                    .font(.system(size: 16, design: .serif))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 30)
                
                Picker("", selection: $isLoginMode) {
                    Text("Sign up").tag(false)
                    Text("Log in").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .onChange(of: isLoginMode) { _, _ in
                    errorMessage = ""
                    successMessage = ""
                }
                
                VStack(spacing: 14) {
                    
                    if !isLoginMode {
                        TextField("Display name", text: $displayName)
                            .textContentType(.name)
                            .padding()
                            .background(Color.gray.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        
                        TextField("Username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.username)
                            .padding()
                            .background(Color.gray.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.emailAddress)
                        .padding()
                        .background(Color.gray.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    
                    PasswordInputField(
                        title: "Password",
                        text: $password,
                        isVisible: $showPassword
                    )
                    
                    if !isLoginMode {
                        PasswordInputField(
                            title: "Confirm password",
                            text: $confirmPassword,
                            isVisible: $showConfirmPassword
                        )
                    }
                }
                .padding(.horizontal)
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                if !successMessage.isEmpty {
                    Text(successMessage)
                        .font(.caption)
                        .foregroundStyle(.green)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                Button {
                    isLoginMode ? logIn() : signUp()
                } label: {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    } else {
                        Text(isLoginMode ? "Log in" : "Create Profile")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.horizontal)
                .disabled(isLoading)
                
                if isLoginMode {
                    Button {
                        forgotPassword()
                    } label: {
                        Text("Forgot password?")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer(minLength: 40)
            }
        }
    }
    
    private func signUp() {
        let cleanUsername = clean(username)
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        errorMessage = ""
        successMessage = ""
        
        guard !cleanUsername.isEmpty else {
            errorMessage = "Please enter a username."
            return
        }
        
        guard cleanEmail.contains("@") && cleanEmail.contains(".") else {
            errorMessage = "Please enter a valid email."
            return
        }
        
        guard password.count >= 6 else {
            errorMessage = "Password must have at least 6 characters."
            return
        }
        
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match."
            return
        }
        
        isLoading = true
        
        Auth.auth().createUser(withEmail: cleanEmail, password: password) { result, error in
            isLoading = false
            
            if let error = error {
                errorMessage = error.localizedDescription
                return
            }
            
            savedUsername = cleanUsername
            savedDisplayName = displayName.isEmpty ? cleanUsername.capitalized : displayName
            savedEmail = cleanEmail
            
            let changeRequest = Auth.auth().currentUser?.createProfileChangeRequest()
            changeRequest?.displayName = savedDisplayName
            changeRequest?.commitChanges { error in
                if let error = error {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func logIn() {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        errorMessage = ""
        successMessage = ""
        
        guard cleanEmail.contains("@") && cleanEmail.contains(".") else {
            errorMessage = "Please enter your email."
            return
        }
        
        guard !password.isEmpty else {
            errorMessage = "Please enter your password."
            return
        }
        
        isLoading = true
        
        Auth.auth().signIn(withEmail: cleanEmail, password: password) { result, error in
            isLoading = false
            
            if let error = error {
                errorMessage = error.localizedDescription
                return
            }
            
            savedEmail = cleanEmail
            
            if let user = result?.user {
                savedDisplayName = user.displayName ?? savedDisplayName
            }
        }
    }
    
    private func forgotPassword() {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        errorMessage = ""
        successMessage = ""
        
        guard cleanEmail.contains("@") && cleanEmail.contains(".") else {
            errorMessage = "Enter your email first, then tap forgot password."
            return
        }
        
        Auth.auth().sendPasswordReset(withEmail: cleanEmail) { error in
            if let error = error {
                errorMessage = error.localizedDescription
            } else {
                successMessage = "Password reset email sent to \(cleanEmail)."
            }
        }
    }
    
    private func clean(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "@", with: "")
    }
}

struct PasswordInputField: View {
    
    let title: String
    @Binding var text: String
    @Binding var isVisible: Bool
    
    var body: some View {
        
        HStack {
            
            Group {
                
                if isVisible {
                    
                    TextField(title, text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    
                } else {
                    
                    SecureField(title, text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            
            Button {
                isVisible.toggle()
            } label: {
                
                Image(systemName: isVisible ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// ============================================================
// MARK: - HOME
// ============================================================

struct HomeDashboardView: View {
    
    @StateObject private var archiveStore = MagazineArchiveStore.shared
    @StateObject private var groupStore = PenpalGroupStore.shared
    
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    
    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .english
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    
                    Spacer().frame(height: 20)
                    
                    VStack(spacing: 10) {
                        Text("PenPal")
                            .font(.system(size: 44, weight: .light, design: .serif))
                            .kerning(1.2)
                        
                        Text(t("A digital scrapbook of who we are becoming.",
                               "Ein digitales Scrapbook von dem, wer wir werden.",
                               "Uno scrapbook digitale di ciò che stiamo diventando.",
                               "Un scrapbook digital de quienes estamos llegando a ser.",
                               "Un scrapbook numérique de ce que nous devenons."))
                            .font(.system(size: 16, design: .serif))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 30)
                    }
                    
                    NavigationLink {
                        IssueBuilderView()
                    } label: {
                        Text(t("Create New Issue", "Neue Ausgabe erstellen", "Crea nuovo numero", "Crear nueva edición", "Créer un nouveau numéro"))
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 13)
                            .background(Color.black.opacity(0.9))
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    
                    NavigationLink {
                        ProfileSettingsView()
                    } label: {
                        HomeCardButton(
                            icon: "person.crop.circle",
                            title: t("Profile & language", "Profil & Sprache", "Profilo e lingua", "Perfil e idioma", "Profil et langue"),
                            subtitle: t("Account, sign out and app language", "Konto, Abmelden und App-Sprache", "Account, logout e lingua", "Cuenta, cerrar sesión e idioma", "Compte, déconnexion et langue")
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                            Text(t("Throwback", "Rückblick", "Ricordi", "Recuerdos", "Souvenirs"))
                                .font(.headline)
                            Spacer()
                        }
                        
                        NavigationLink {
                            ThrowbackView()
                        } label: {
                            HomeCardButton(
                                icon: "book.pages",
                                title: t("View old magazines", "Alte Magazine ansehen", "Vedi vecchi magazine", "Ver revistas antiguas", "Voir les anciens magazines"),
                                subtitle: "\(archiveStore.savedIssues.count) \(t("saved issues", "gespeicherte Ausgaben", "numeri salvati", "ediciones guardadas", "numéros sauvegardés"))"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "person.3")
                            Text(t("Subscriptions", "Abos", "Abbonamenti", "Suscripciones", "Abonnements"))
                                .font(.headline)
                            Spacer()
                        }
                        
                        ForEach(groupStore.groups) { group in
                            NavigationLink {
                                GroupDetailView(group: binding(for: group))
                            } label: {
                                HomeCardButton(
                                    icon: "person.3.fill",
                                    title: group.name,
                                    subtitle: "\(group.members.count) \(t("members", "Mitglieder", "membri", "miembros", "membres")) · \(group.issues.count) \(t("issues", "Ausgaben", "numeri", "ediciones", "numéros"))"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        
                        NavigationLink {
                            CreateGroupView(groups: $groupStore.groups)
                        } label: {
                            HomeCardButton(
                                icon: "plus",
                                title: t("Create new group", "Neue Gruppe erstellen", "Crea nuovo gruppo", "Crear nuevo grupo", "Créer un nouveau groupe"),
                                subtitle: t("Add people you want to send issues to", "Füge Personen hinzu, denen du Ausgaben senden willst", "Aggiungi persone a cui inviare i numeri", "Añade personas a quienes enviar tus ediciones", "Ajoute les personnes à qui envoyer tes numéros")
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding()
            }
        }
    }
    
    private func binding(for group: PenpalGroup) -> Binding<PenpalGroup> {
        guard let index = groupStore.groups.firstIndex(where: { $0.id == group.id }) else {
            return .constant(group)
        }
        return $groupStore.groups[index]
    }
    
    private func t(_ en: String, _ de: String, _ it: String, _ es: String, _ fr: String) -> String {
        switch language {
        case .english: return en
        case .german: return de
        case .italian: return it
        case .spanish: return es
        case .french: return fr
        }
    }
}

// ============================================================
// MARK: - PROFILE
// ============================================================

struct ProfileSettingsView: View {
    
    @AppStorage("username") private var username: String = ""
    @AppStorage("displayName") private var displayName: String = ""
    @AppStorage("email") private var email: String = ""
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    @AppStorage("homeResetID") private var homeResetID: String = UUID().uuidString
    
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String = ""
    
    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .english
    }
    
    private var firebaseUser: User? {
        Auth.auth().currentUser
    }
    
    var selectedLanguage: Binding<AppLanguage> {
        Binding(
            get: { AppLanguage(rawValue: languageRaw) ?? .english },
            set: { languageRaw = $0.rawValue }
        )
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                
                Text("Profile")
                    .font(.system(size: 32, weight: .light, design: .serif))
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(displayNameFromFirebase)
                        .font(.headline)
                    
                    if !username.isEmpty {
                        Text("@\(username)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text(emailFromFirebase)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                
                VStack(alignment: .leading, spacing: 14) {
                    Text("App language")
                        .font(.headline)
                    
                    Picker("Language", selection: selectedLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.rawValue).tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                
                Button {
                    signOut()
                } label: {
                    Text("Sign out")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                
                Button {
                    showDeleteConfirmation = true
                } label: {
                    Text("Delete profile permanently")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete profile?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete everything", role: .destructive) {
                deleteProfile()
            }
            
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your Firebase account from PenPal on this prototype.")
        }
    }
    
    private var displayNameFromFirebase: String {
        firebaseUser?.displayName
        ?? (displayName.isEmpty ? username.capitalized : displayName)
    }
    
    private var emailFromFirebase: String {
        firebaseUser?.email ?? email
    }
    
    private func signOut() {
        do {
            try Auth.auth().signOut()
            homeResetID = UUID().uuidString
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func deleteProfile() {
        guard let user = Auth.auth().currentUser else { return }
        
        user.delete { error in
            if let error = error {
                errorMessage = error.localizedDescription
                return
            }
            
            username = ""
            displayName = ""
            email = ""
            
            IssueDraftStore.shared.pages.removeAll()
            MagazineArchiveStore.shared.savedIssues.removeAll()
            PenpalGroupStore.shared.groups.removeAll()
            
            homeResetID = UUID().uuidString
        }
    }
}
// ============================================================
// MARK: - PREPRINT REVIEW
// ============================================================

struct PreprintReviewView: View {
    
    @StateObject private var issueStore = IssueDraftStore.shared
    @StateObject private var archiveStore = MagazineArchiveStore.shared
    @StateObject private var groupStore = PenpalGroupStore.shared
    
    @AppStorage("homeResetID") private var homeResetID: String = UUID().uuidString
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    
    @State private var selectedGroupIDs: Set<UUID> = []
    @State private var showSentMessage = false
    
    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .english
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                
                Text(t("Preprint Review", "Preprint prüfen", "Revisione preprint", "Revisión previa", "Relecture prépublication"))
                    .font(.system(size: 32, weight: .light, design: .serif))
                
                Text(t("Look over your magazine before publishing. Tap a section to edit it again.",
                       "Prüfe dein Magazin vor dem Veröffentlichen. Tippe auf einen Abschnitt, um ihn erneut zu bearbeiten.",
                       "Controlla il magazine prima di pubblicarlo. Tocca una sezione per modificarla di nuovo.",
                       "Revisa tu revista antes de publicarla. Toca una sección para editarla otra vez.",
                       "Relis ton magazine avant de le publier. Appuie sur une section pour la modifier."))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                ForEach(uniqueSections, id: \.self) { sectionTitle in
                    NavigationLink {
                        FreeMagazineEditorView(
                            section: IssueSection(title: sectionTitle),
                            startingLayout: .layout1,
                            startingTitleStyle: .editorial
                        ) { }
                    } label: {
                        HomeCardButton(
                            icon: "square.and.pencil",
                            title: sectionTitle,
                            subtitle: t("Edit this section", "Diesen Abschnitt bearbeiten", "Modifica questa sezione", "Editar esta sección", "Modifier cette section")
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 14) {
                    Text(t("Send to groups", "An Gruppen senden", "Invia ai gruppi", "Enviar a grupos", "Envoyer aux groupes"))
                        .font(.headline)
                    
                    if groupStore.groups.isEmpty {
                        Text(t("Create a group first before sending.",
                               "Erstelle zuerst eine Gruppe, bevor du sendest.",
                               "Crea prima un gruppo prima di inviare.",
                               "Crea primero un grupo antes de enviar.",
                               "Crée d’abord un groupe avant d’envoyer."))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(groupStore.groups) { group in
                            Button {
                                toggleGroup(group.id)
                            } label: {
                                HStack {
                                    Image(systemName: selectedGroupIDs.contains(group.id) ? "checkmark.circle.fill" : "circle")
                                    
                                    VStack(alignment: .leading) {
                                        Text(group.name)
                                        Text("\(group.members.count) \(t("members", "Mitglieder", "membri", "miembros", "membres"))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                }
                                .padding()
                                .background(Color.gray.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                Divider()
                
                Text(t("Preview pages", "Seitenvorschau", "Anteprima pagine", "Vista previa de páginas", "Aperçu des pages"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                ForEach(issueStore.pages.indices, id: \.self) { index in
                    FinalMagazinePagePreview(page: issueStore.pages[index])
                        .frame(width: 170, height: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(radius: 3)
                }
                
                Button {
                    publishIssue()
                } label: {
                    Text(t("Publish / Send", "Veröffentlichen / Senden", "Pubblica / Invia", "Publicar / Enviar", "Publier / Envoyer"))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                
                if showSentMessage {
                    Text(t("Magazine sent and saved to Throwback.",
                           "Magazin gesendet und im Rückblick gespeichert.",
                           "Magazine inviato e salvato nei ricordi.",
                           "Revista enviada y guardada en recuerdos.",
                           "Magazine envoyé et sauvegardé dans les souvenirs."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle(t("Preprint", "Preprint", "Preprint", "Preprint", "Prépublication"))
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var uniqueSections: [String] {
        var seen: [String] = []
        
        for page in issueStore.pages {
            guard page.sectionTitle != "Cover",
                  page.sectionTitle != "Back Cover" else { continue }
            
            if !seen.contains(page.sectionTitle) {
                seen.append(page.sectionTitle)
            }
        }
        
        return seen
    }
    
    private func toggleGroup(_ id: UUID) {
        if selectedGroupIDs.contains(id) {
            selectedGroupIDs.remove(id)
        } else {
            selectedGroupIDs.insert(id)
        }
    }
    
    private func publishIssue() {
        let savedIssue = SavedMagazineIssue(
            title: "PenPal Issue",
            date: Date(),
            pages: issueStore.pages
        )
        
        archiveStore.savedIssues.append(savedIssue)
        
        for index in groupStore.groups.indices {
            if selectedGroupIDs.contains(groupStore.groups[index].id) {
                groupStore.groups[index].issues.append(savedIssue)
            }
        }
        
        showSentMessage = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            issueStore.pages.removeAll()
            homeResetID = UUID().uuidString
        }
    }
    
    private func t(_ en: String, _ de: String, _ it: String, _ es: String, _ fr: String) -> String {
        switch language {
        case .english: return en
        case .german: return de
        case .italian: return it
        case .spanish: return es
        case .french: return fr
        }
    }
}

// ============================================================
// MARK: - THROWBACK
// ============================================================

struct ThrowbackView: View {
    
    @StateObject private var archiveStore = MagazineArchiveStore.shared
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    
    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .english
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                
                if archiveStore.savedIssues.isEmpty {
                    VStack(spacing: 18) {
                        Image(systemName: "book.pages")
                            .font(.system(size: 46))
                            .foregroundStyle(.secondary)
                        
                        Text(t("Your old magazines will appear here.",
                               "Deine alten Magazine erscheinen hier.",
                               "I tuoi vecchi magazine appariranno qui.",
                               "Tus revistas antiguas aparecerán aquí.",
                               "Tes anciens magazines apparaîtront ici."))
                            .font(.headline)
                        
                        Text(t("Once you publish a finished issue, it will be stored here as a throwback.",
                               "Sobald du eine fertige Ausgabe veröffentlichst, wird sie hier als Rückblick gespeichert.",
                               "Quando pubblichi un numero finito, verrà salvato qui come ricordo.",
                               "Cuando publiques una edición terminada, se guardará aquí como recuerdo.",
                               "Quand tu publies un numéro terminé, il sera sauvegardé ici comme souvenir."))
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else {
                    ForEach(archiveStore.savedIssues) { issue in
                        NavigationLink {
                            FinalMagazineReviewView(issue: issue)
                        } label: {
                            HomeCardButton(
                                icon: "book.closed",
                                title: issue.title,
                                subtitle: issue.date.formatted(date: .abbreviated, time: .omitted)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(t("Throwback", "Rückblick", "Ricordi", "Recuerdos", "Souvenirs"))
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func t(_ en: String, _ de: String, _ it: String, _ es: String, _ fr: String) -> String {
        switch language {
        case .english: return en
        case .german: return de
        case .italian: return it
        case .spanish: return es
        case .french: return fr
        }
    }
}

// ============================================================
// MARK: - FINAL REVIEW
// ============================================================

struct FinalMagazineReviewView: View {
    
    let issue: SavedMagazineIssue
    
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    
    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .english
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(issue.title)
                    .font(.system(size: 32, weight: .light, design: .serif))
                
                ForEach(issue.pages.indices, id: \.self) { index in
                    FinalMagazinePagePreview(page: issue.pages[index])
                        .frame(width: 170, height: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(radius: 3)
                }
            }
            .padding()
        }
        .navigationTitle(t("Magazine", "Magazin", "Magazine", "Revista", "Magazine"))
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func t(_ en: String, _ de: String, _ it: String, _ es: String, _ fr: String) -> String {
        switch language {
        case .english: return en
        case .german: return de
        case .italian: return it
        case .spanish: return es
        case .french: return fr
        }
    }
}

struct FinalMagazinePagePreview: View {
    
    let page: MagazinePage
    
    var body: some View {
        ZStack {
            Color(uiColor: page.backgroundColor)
            
            Rectangle()
                .stroke(Color.black.opacity(0.18), lineWidth: 1)
                .padding(6)
            
            ForEach(page.elements) { element in
                FinalMagazineElementPreview(element: element, page: page)
                    .frame(width: element.size.width, height: element.size.height)
                    .position(element.position)
            }
        }
    }
}

struct FinalMagazineElementPreview: View {
    
    let element: MagazineElement
    let page: MagazinePage
    
    var body: some View {
        switch element.type {
        case .title:
            Text(element.text)
                .font(page.titleStyle.font)
                .foregroundStyle(Color(uiColor: page.titleColor))
                .minimumScaleFactor(0.2)
                .multilineTextAlignment(.center)
            
        case .text:
            Text(element.text)
                .font(.system(size: 8))
                .foregroundStyle(Color(uiColor: page.textColor))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(5)
            
        case .image:
            if let image = element.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
            
        case .shape:
            ShapeOrIconView(shape: element.shape, color: Color(uiColor: element.shapeColor))
            
        case .drawing:
            if let image = element.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
        }
    }
}

// ============================================================
// MARK: - GROUP DETAIL
// ============================================================

struct GroupDetailView: View {
    
    @Binding var group: PenpalGroup
    @State private var friendUsername: String = ""
    
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    
    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .english
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(group.name)
                    .font(.system(size: 32, weight: .light, design: .serif))
                
                Text(t("Add friends by their PenPal username.",
                       "Füge Freunde über ihren PenPal-Benutzernamen hinzu.",
                       "Aggiungi amici tramite il loro nome utente PenPal.",
                       "Añade amigos con su nombre de usuario de PenPal.",
                       "Ajoute des amis avec leur nom d’utilisateur PenPal."))
                    .foregroundStyle(.secondary)
                
                HStack {
                    TextField("@username", text: $friendUsername)
                        .textInputAutocapitalization(.never)
                        .padding()
                        .background(Color.gray.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    
                    Button {
                        addFriend()
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding()
                            .background(Color.black)
                            .clipShape(Circle())
                    }
                }
                
                Divider()
                
                Text(t("Members", "Mitglieder", "Membri", "Miembros", "Membres"))
                    .font(.headline)
                
                if group.members.isEmpty {
                    Text(t("No members yet.", "Noch keine Mitglieder.", "Ancora nessun membro.", "Aún no hay miembros.", "Aucun membre pour l’instant."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(group.members) { member in
                        HStack {
                            Image(systemName: "person.crop.circle")
                            
                            VStack(alignment: .leading) {
                                Text(member.displayName)
                                Text("@\(member.username)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding()
                        .background(Color.gray.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                
                Divider()
                
                Text(t("Group magazines", "Gruppenmagazine", "Magazine del gruppo", "Revistas del grupo", "Magazines du groupe"))
                    .font(.headline)
                
                if group.issues.isEmpty {
                    Text(t("No magazines have been published to this group yet.",
                           "In dieser Gruppe wurden noch keine Magazine veröffentlicht.",
                           "Nessun magazine è stato ancora pubblicato in questo gruppo.",
                           "Todavía no se ha publicado ninguna revista en este grupo.",
                           "Aucun magazine n’a encore été publié dans ce groupe."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(group.issues) { issue in
                        NavigationLink {
                            FinalMagazineReviewView(issue: issue)
                        } label: {
                            HomeCardButton(
                                icon: "book.closed",
                                title: issue.title,
                                subtitle: issue.date.formatted(date: .abbreviated, time: .omitted)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(t("Group", "Gruppe", "Gruppo", "Grupo", "Groupe"))
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func addFriend() {
        let clean = friendUsername
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "@", with: "")
        
        guard !clean.isEmpty else { return }
        
        group.members.append(
            PenpalProfile(username: clean, displayName: clean.capitalized)
        )
        
        friendUsername = ""
    }
    
    private func t(_ en: String, _ de: String, _ it: String, _ es: String, _ fr: String) -> String {
        switch language {
        case .english: return en
        case .german: return de
        case .italian: return it
        case .spanish: return es
        case .french: return fr
        }
    }
}

// ============================================================
// MARK: - CREATE GROUP
// ============================================================

struct CreateGroupView: View {
    
    @Binding var groups: [PenpalGroup]
    @Environment(\.dismiss) private var dismiss
    @State private var groupName: String = ""
    
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    
    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .english
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(t("Create group", "Gruppe erstellen", "Crea gruppo", "Crear grupo", "Créer un groupe"))
                .font(.system(size: 32, weight: .light, design: .serif))
            
            TextField(t("Group name", "Gruppenname", "Nome del gruppo", "Nombre del grupo", "Nom du groupe"), text: $groupName)
                .padding()
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            
            Button {
                createGroup()
            } label: {
                Text(t("Create group", "Gruppe erstellen", "Crea gruppo", "Crear grupo", "Créer un groupe"))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle(t("New Group", "Neue Gruppe", "Nuovo gruppo", "Nuevo grupo", "Nouveau groupe"))
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func createGroup() {
        let clean = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        
        groups.append(PenpalGroup(name: clean, members: []))
        dismiss()
    }
    
    private func t(_ en: String, _ de: String, _ it: String, _ es: String, _ fr: String) -> String {
        switch language {
        case .english: return en
        case .german: return de
        case .italian: return it
        case .spanish: return es
        case .french: return fr
        }
    }
}

// ============================================================
// MARK: - CARD BUTTON
// ============================================================

struct HomeCardButton: View {
    
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(Color.black.opacity(0.08))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    ContentView()
}
