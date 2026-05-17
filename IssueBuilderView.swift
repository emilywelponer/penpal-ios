import SwiftUI

struct IssueSection: Identifiable, Hashable {
    let id = UUID()
    var title: String
}

struct IssueBuilderView: View {
    
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    
    @State private var customTopic: String = ""
    
    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .english
    }
    
    private var sections: [IssueSection] {
        [
            .init(title: t("Monthly reset", "Monatsreset", "Reset mensile", "Reinicio mensual", "Reset mensuel")),
            .init(title: t("Mental health check-in", "Mental-Health-Check-in", "Check-in mentale", "Chequeo de salud mental", "Point santé mentale")),
            .init(title: t("Creative inspiration", "Kreative Inspiration", "Ispirazione creativa", "Inspiración creativa", "Inspiration créative")),
            .init(title: t("Relationship update", "Beziehungsupdate", "Aggiornamento relazioni", "Actualización de relaciones", "Point relations")),
            .init(title: t("What I’m avoiding", "Was ich vermeide", "Cosa sto evitando", "Lo que estoy evitando", "Ce que j’évite")),
            .init(title: t("Tiny wins", "Kleine Erfolge", "Piccole vittorie", "Pequeñas victorias", "Petites victoires")),
            .init(title: t("New hobbies", "Neue Hobbys", "Nuovi hobby", "Nuevos hobbies", "Nouveaux loisirs")),
            .init(title: t("Current obsessions", "Aktuelle Obsessionen", "Ossessioni attuali", "Obsesiones actuales", "Obsessions du moment")),
            .init(title: t("Books", "Bücher", "Libri", "Libros", "Livres")),
            .init(title: t("Films & TV", "Filme & Serien", "Film & TV", "Películas y TV", "Films & TV")),
            .init(title: t("Music", "Musik", "Musica", "Música", "Musique"))
        ]
    }
    
    var body: some View {
        
        NavigationStack {
            
            ScrollView {
                
                VStack(alignment: .leading, spacing: 24) {
                    
                    Text(t(
                        "Set the tone of your newest issue.",
                        "Lege die Stimmung deiner neuesten Ausgabe fest.",
                        "Imposta il tono del tuo nuovo numero.",
                        "Define el tono de tu nueva edición.",
                        "Définis l’ambiance de ton nouveau numéro."
                    ))
                    .font(.system(size: 28, weight: .light, design: .serif))
                    .padding(.top, 10)
                    
                    Divider()
                    
                    Text(t(
                        "What do you want to include?",
                        "Was möchtest du einbauen?",
                        "Cosa vuoi includere?",
                        "¿Qué quieres incluir?",
                        "Que veux-tu inclure ?"
                    ))
                    .font(.headline)
                    
                    VStack(spacing: 12) {
                        ForEach(sections) { section in
                            NavigationLink {
                                SectionDetailView(section: section)
                            } label: {
                                SectionButtonView(section: section)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    Text(t(
                        "Create your own topic",
                        "Eigenes Thema erstellen",
                        "Crea il tuo argomento",
                        "Crea tu propio tema",
                        "Crée ton propre sujet"
                    ))
                    .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 14) {
                        
                        TextField(
                            t(
                                "Write your own section title...",
                                "Schreibe deinen eigenen Abschnittstitel...",
                                "Scrivi il titolo della tua sezione...",
                                "Escribe tu propio título de sección...",
                                "Écris ton propre titre de section..."
                            ),
                            text: $customTopic
                        )
                        .padding()
                        .background(Color.gray.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        
                        if !customTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            
                            NavigationLink {
                                SectionDetailView(
                                    section: IssueSection(title: customTopic)
                                )
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(customTopic)
                                            .font(.system(size: 16))
                                            .foregroundStyle(.primary)
                                        
                                        Text(t(
                                            "Custom section",
                                            "Eigener Abschnitt",
                                            "Sezione personalizzata",
                                            "Sección personalizada",
                                            "Section personnalisée"
                                        ))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "arrow.right")
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                                .background(Color.black.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationTitle(t(
                "Build Issue",
                "Ausgabe erstellen",
                "Crea numero",
                "Crear edición",
                "Créer le numéro"
            ))
        }
    }
    
    private func t(_ en: String, _ de: String, _ it: String, _ es: String, _ fr: String) -> String {
        switch language {
        case .english:
            return en
        case .german:
            return de
        case .italian:
            return it
        case .spanish:
            return es
        case .french:
            return fr
        }
    }
}

struct SectionButtonView: View {
    
    let section: IssueSection
    
    var body: some View {
        HStack {
            Text(section.title)
                .font(.system(size: 16))
                .foregroundStyle(.primary)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .cornerRadius(12)
    }
}

#Preview {
    IssueBuilderView()
}
