import SwiftUI
import PhotosUI
import Combine
import UIKit
import FirebaseAuth

// Generated from the uploaded PenPal PowerPoint template.
// Layout positions use the same slide coordinate system scaled to 170 x 250.

struct IssueSection: Identifiable, Hashable {
    var id: IssueSectionType { type }
    var title: String
    var type: IssueSectionType
}

enum IssueSectionType: String, CaseIterable, Hashable, Identifiable {
    case monthlyReset, tinyWins, hobbies, relationships, playlist, cinema, reading, food, travel, favourites, affirmations
    var id: String { rawValue }
}

enum PenPalColourScheme: String, CaseIterable, Identifiable {
    case clean = "Clean Neutral"
    case blackWhite = "Black & White"
    case blush = "Soft Blush"
    case sage = "Quiet Sage"
    case atlantic = "Calm Atlantic"
    case marine = "Marine"
    var id: String { rawValue }
    var paper: UIColor {
        switch self {
        case .clean: return UIColor(red: 0.985, green: 0.970, blue: 0.935, alpha: 1)
        case .blackWhite: return UIColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 1)
        case .blush: return UIColor(red: 1.000, green: 0.945, blue: 0.935, alpha: 1)
        case .sage: return UIColor(red: 0.935, green: 0.950, blue: 0.900, alpha: 1)
        case .atlantic: return UIColor(red: 0.930, green: 0.955, blue: 0.965, alpha: 1)
        case .marine: return UIColor(red: 0.090, green: 0.145, blue: 0.215, alpha: 1)
        }
    }
    var ink: UIColor { self == .marine ? .white : UIColor(red: 0.105, green: 0.095, blue: 0.080, alpha: 1) }
    var mutedInk: UIColor { self == .marine ? UIColor.white.withAlphaComponent(0.55) : UIColor.black.withAlphaComponent(0.35) }
    var accent: UIColor {
        switch self {
        case .clean: return UIColor(red: 0.390, green: 0.350, blue: 0.285, alpha: 1)
        case .blackWhite: return UIColor(red: 0.000, green: 0.000, blue: 0.000, alpha: 1)
        case .blush: return UIColor(red: 0.665, green: 0.300, blue: 0.330, alpha: 1)
        case .sage: return UIColor(red: 0.305, green: 0.430, blue: 0.330, alpha: 1)
        case .atlantic: return UIColor(red: 0.165, green: 0.360, blue: 0.465, alpha: 1)
        case .marine: return .white
        }
    }
}

extension PenPalColourScheme {
    static func inferred(from pages: [MagazinePage]) -> PenPalColourScheme? {
        guard let first = pages.first else { return nil }
        return allCases.min { lhs, rhs in
            colorDistance(first.backgroundColor, lhs.paper)
                + colorDistance(first.titleColor, lhs.accent)
                + colorDistance(first.textColor, lhs.ink)
            <
            colorDistance(first.backgroundColor, rhs.paper)
                + colorDistance(first.titleColor, rhs.accent)
                + colorDistance(first.textColor, rhs.ink)
        }
    }

    private static func colorDistance(_ lhs: UIColor, _ rhs: UIColor) -> CGFloat {
        var lr: CGFloat = 0
        var lg: CGFloat = 0
        var lb: CGFloat = 0
        var la: CGFloat = 0
        var rr: CGFloat = 0
        var rg: CGFloat = 0
        var rb: CGFloat = 0
        var ra: CGFloat = 0
        lhs.getRed(&lr, green: &lg, blue: &lb, alpha: &la)
        rhs.getRed(&rr, green: &rg, blue: &rb, alpha: &ra)
        return abs(lr - rr) + abs(lg - rg) + abs(lb - rb) + abs(la - ra)
    }
}

final class IssueDraftStore: ObservableObject {
    static let shared = IssueDraftStore()
    @Published var pages: [MagazinePage] = []
    @Published var currentDraftID: String?
    @Published var currentDraftTitle: String?
    @Published var currentColourScheme: PenPalColourScheme?
    private init() {}
}

struct MagazinePage: Identifiable {
    let id = UUID()
    var title: String
    var sectionTitle: String
    var elements: [MagazineElement]
    var titleStyle: TitleStyle = .editorial
    var backgroundColor: UIColor
    var titleColor: UIColor
    var textColor: UIColor
    var layout: FreeMagazineLayout = .layout1
}

private let emptyMagazinePage = MagazinePage(
    title: "",
    sectionTitle: "",
    elements: [],
    backgroundColor: .white,
    titleColor: .black,
    textColor: .black
)

private let emptyMagazineElement = MagazineElement(
    type: .text,
    text: "",
    position: .zero,
    size: .zero
)

private var activeEditorSinglePageCanvasCount = 0

private struct EditorPageRoute: Identifiable, Hashable {
    let index: Int
    var id: Int { index }
}

private func safeCGFloat(_ value: CGFloat, fallback: CGFloat, min minimum: CGFloat? = nil, max maximum: CGFloat? = nil, context: String = "") -> CGFloat {
    guard value.isFinite else {
        if !context.isEmpty { print("LAYOUT_INVALID_CGFLOAT", context, value) }
        return fallback
    }
    var result = value
    if let minimum { result = Swift.max(minimum, result) }
    if let maximum { result = Swift.min(maximum, result) }
    return result
}

private func safeUnitScale(_ value: CGFloat, fallback: CGFloat = 1) -> CGFloat {
    safeCGFloat(value, fallback: fallback, min: 0.01, max: 8, context: "unitScale")
}

private func safePoint(_ point: CGPoint, fallback: CGPoint = .zero, context: String = "") -> CGPoint {
    CGPoint(
        x: safeCGFloat(point.x, fallback: fallback.x, context: "\(context).x"),
        y: safeCGFloat(point.y, fallback: fallback.y, context: "\(context).y")
    )
}

private func safeSize(_ size: CGSize, fallback: CGSize = CGSize(width: 1, height: 1), context: String = "") -> CGSize {
    CGSize(
        width: safeCGFloat(size.width, fallback: fallback.width, min: 0.1, context: "\(context).width"),
        height: safeCGFloat(size.height, fallback: fallback.height, min: 0.1, context: "\(context).height")
    )
}

@MainActor
private func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

private func normalizedTemplateMatchText(_ text: String) -> String {
    templateLogicText(text)
        .replacingOccurrences(of: "’", with: "'")
        .replacingOccurrences(of: "‘", with: "'")
        .replacingOccurrences(of: "—", with: "-")
        .replacingOccurrences(of: "–", with: "-")
        .lowercased()
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func compactTemplateMatchText(_ text: String) -> String {
    let normalized = normalizedTemplateMatchText(text)
        .replacingOccurrences(of: "i'm", with: "i am")
        .replacingOccurrences(of: "im", with: "i am")
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    let scalars = normalized.unicodeScalars.map { scalar -> Character in
        CharacterSet.alphanumerics.contains(scalar) || CharacterSet.whitespacesAndNewlines.contains(scalar)
            ? Character(scalar)
            : " "
    }
    return String(scalars)
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

private func templateTextMatches(_ text: String, _ phrases: [String]) -> Bool {
    let normalized = normalizedTemplateMatchText(text)
    let compact = compactTemplateMatchText(text)

    return phrases.contains { phrase in
        let phraseNormalized = normalizedTemplateMatchText(phrase)
        let phraseCompact = compactTemplateMatchText(phrase)
        return normalized == phraseNormalized
            || normalized.hasPrefix(phraseNormalized)
            || phraseNormalized.hasPrefix(normalized)
            || compact == phraseCompact
            || compact.hasPrefix(phraseCompact)
            || phraseCompact.hasPrefix(compact)
            || compact == "the \(phraseCompact)"
            || compact.hasPrefix("the \(phraseCompact)")
    }
}

func isDecorativeTemplateText(_ element: MagazineElement) -> Bool {
    let normalized = normalizedTemplateMatchText(element.text)
    let compact = compactTemplateMatchText(element.text)
    guard !normalized.isEmpty else { return true }

    let decorativeTexts: Set<String> = [
        "✦",
        "★",
        "☆",
        "→",
        "->",
        "name →",
        "name ->"
    ]

    if decorativeTexts.contains(normalized) { return true }
    if compact == "name" && normalized.contains("→") { return true }

    let decorativeScalars = CharacterSet(charactersIn: "✦★☆→←↑↓↔︎↕︎•·-–—_.,:;!¡?¿/\\|()[]{}<>+*=~'\" ")
    let hasLetters = element.text.rangeOfCharacter(from: .letters) != nil
    let hasNumbers = element.text.rangeOfCharacter(from: .decimalDigits) != nil
    let isOnlyDecorativeScalars = element.text.unicodeScalars.allSatisfy { decorativeScalars.contains($0) }

    if isOnlyDecorativeScalars { return true }
    if !hasLetters && !hasNumbers { return true }
    if normalized.contains("___") || normalized.allSatisfy({ $0 == "_" || $0 == "/" || $0 == " " }) { return true }

    return false
}

private func isSectionCoverDescription(_ element: MagazineElement, page: MagazinePage) -> Bool {
    guard element.type == .text,
          Int(page.title) != nil,
          !["Cover", "Contents", "Back"].contains(page.sectionTitle) else {
        return false
    }

    return element.fontName == "Georgia"
        && element.size.height >= 18
        && element.position.y > 145
        && element.position.y < 205
        && element.text.rangeOfCharacter(from: .letters) != nil
}

func isUnlockableTemplateText(_ element: MagazineElement, page: MagazinePage) -> Bool {
    guard (element.type == .text || element.type == .title), !element.isEditableText else { return false }
    if element.isTextLocked && element.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return true
    }
    guard !isDecorativeTemplateText(element) else { return false }
    if element.isTextLocked { return true }
    if isSectionCoverDescription(element, page: page) { return true }

    let pageTitle = page.title.uppercased()
    let text = normalizedTemplateMatchText(element.text)

    switch pageTitle {
    case "MONTHLY RESET · DAILY REFLECTI":
        return templateTextMatches(text, [
            "one good thing",
            "one hard thing",
            "one thing i learned",
            "one thing i am grateful for",
            "one thing i'm grateful for"
        ])

    case "MONTHLY RESET · GRATITUDE":
        return templateTextMatches(text, [
            "small things",
            "people",
            "moments",
            "health & wellness"
        ])

    case "MONTHLY RESET · LETTER":
        return templateTextMatches(text, [
            "first thing i want to remember",
            "what i learned about myself",
            "what i am ready to change"
        ])

    case "MONTHLY RESET · GROW TRACKER":
        return templateTextMatches(text, ["mind", "body", "love", "rest"])

    case "HOBBIES · A NEW TRY":
        return templateTextMatches(text, ["effort", "cost", "difficulty", "reward"])

    case "HOBBIES · PROGRESS":
        return templateTextMatches(text, ["technique", "speed", "consistency", "theory", "creativity", "confidence"])

    case "RELATIONSHIPS · DATE REVIEW":
        return templateTextMatches(text, ["conversation", "chemistry", "humor", "looks", "presence", "manners", "overall"])

    case "RELATIONSHIPS · IN LOVE WITH L":
        return templateTextMatches(text, ["things you gave me this month"])

    case "RELATIONSHIPS · NEWEST OBSESSI":
        return templateTextMatches(text, [
            "first noticed",
            "why they're hot",
            "what i already know about them"
        ])
        
    case "PLAYLIST & MUSIC · MIXTAPE":
        return templateTextMatches(text, [
            "when I am in my feelings",
            "when I am happy",
            "when I am in love"
        ])
        
    case "READING · BOOKPLATE":
        return templateLogicText(element.text).trimmingCharacters(in: .whitespacesAndNewlines) == "EX LIBRIS"
        
    case "READING · MARGIN NOTES":
        return templateTextMatches(text, [
            "writing",
            "characters",
            "plot",
            "feeling"
        ])
        
    case "TRAVEL · POSTCARD":
        return templateTextMatches(text, [
            "Greetings from"
        ])
        
    case "GOALS · OUTLOOK":
        return templateTextMatches(text, [
            "work",
            "health",
            "craft",
            "love",
            "money",
            "rest"
        ])
        
    case "GOALS · VISION BOARD":
        return templateTextMatches(text, [
            "become",
            "the feeling",
            "dream",
            "wear",
            "places",
            "read",
            "make",
            "do"
        ])
        
    default:
        return false
    }
}

func templateTextCharacterLimit(for element: MagazineElement, page: MagazinePage) -> Int? {
    guard isUnlockableTemplateText(element, page: page) || element.isTextLocked else { return nil }
    if isSectionCoverDescription(element, page: page) { return 90 }

    switch page.title.uppercased() {
    case "MONTHLY RESET · DAILY REFLECTI":
        return 30
    case "MONTHLY RESET · GRATITUDE":
        return 20
    case "MONTHLY RESET · LETTER":
        return 30
    case "MONTHLY RESET · GROW TRACKER":
        return 15
    case "HOBBIES · A NEW TRY":
        return 15
    case "HOBBIES · PROGRESS":
        return 15
    case "RELATIONSHIPS · DATE REVIEW":
        return 15
    case "RELATIONSHIPS · IN LOVE WITH L":
        return 25
    case "RELATIONSHIPS · NEWEST OBSESSI":
        return 30
    default:
        return nil
    }
}

struct MagazineElement: Identifiable {
    let id = UUID()
    var type: MagazineElementType
    var text: String = ""
    var image: UIImage? = nil
    var imageData: String? = nil
    var localImagePath: String? = nil
    var imageStoragePath: String? = nil
    var position: CGPoint
    var size: CGSize
    var fontSize: CGFloat = 8
    var fontName: String = "Helvetica"
    var isBold: Bool = false
    var isEditableText: Bool = false
    var imageZoom: CGFloat = 1
    var imageOffset: CGSize = .zero
    var textBackgroundColor: UIColor = .clear
    var isTextLocked: Bool = false
    var imageFit: MagazineImageFit = .fill
    var textAlignment: PPTTextHorizontalAlignment = .left
    var verticalAlignment: PPTTextVerticalAlignment = .top
    var textInset: CGSize = CGSize(width: 3.09, height: 1.47)

    // Interactive state for tappable boxes, ratings, choices and sliders
    var isMarked: Bool = false
    var interactionValue: Double = 0
}

enum MagazineElementType { case title, text, image, line, box }
enum MagazineImageFit { case fit, fill }

enum PPTTextHorizontalAlignment {
    case left, center, right

    var swiftUITextAlignment: TextAlignment {
        switch self {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }

    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }
}

enum PPTTextVerticalAlignment { case top, middle, bottom }

enum FreeMagazineLayout: String, CaseIterable, Identifiable { case layout1 = "PowerPoint Template"; var id: String { rawValue } }
enum TitleStyle: String, CaseIterable, Identifiable {
    case editorial = "Editorial"
    case brutalist = "Brutalist"
    case handwriting = "Handwriting"
    case futuristic = "Futuristic"

    var id: String { rawValue }

    var font: Font {
        switch self {
        case .editorial:
            return .custom("Georgia", size: 18)
        case .brutalist:
            return .custom("Helvetica-Bold", size: 18)
        case .handwriting:
            return .system(size: 18, weight: .regular, design: .rounded)
        case .futuristic:
            return .system(size: 18, weight: .medium, design: .monospaced)
        }
    }
}

private var didLogTextFontConsistency = false
private var didLogHelloTextFontConsistency = false

struct ContinuousColumnTextLayout {
    let fontName: String
    let fontSize: CGFloat
    let lineHeight: CGFloat
    let textInset: CGSize
    let verticalOffset: CGFloat
}

private func continuousColumnTextLayout(for pageTitle: String) -> ContinuousColumnTextLayout {
    if pageTitle == "TINY WINS · TROPHY CABINET" {
        return ContinuousColumnTextLayout(
            fontName: "Helvetica",
            fontSize: 5.2,
            lineHeight: 8.6,
            textInset: .zero,
            verticalOffset: 0
        )
    }

    return ContinuousColumnTextLayout(
        fontName: "Helvetica",
        fontSize: 5.65,
        lineHeight: 9.2,
        textInset: .zero,
        verticalOffset: 0
    )
}

private func isMagazineContinuousColumnLine(_ line: MagazineElement, pageTitle: String) -> Bool {
    guard line.type == .line else { return false }

    if pageTitle == "MONTHLY RESET" {
        let isHighsColumn = abs(line.position.x - 46.36) < 2 || abs(line.position.x - 49.46) < 2
        let isLowsColumn = abs(line.position.x - 123.64) < 2 || abs(line.position.x - 126.73) < 2
        return (isHighsColumn || isLowsColumn) && line.position.y >= 74.5 && line.position.y <= 120
    }

    if pageTitle == "TINY WINS · TROPHY CABINET" {
        return abs(line.position.x - 96.0) < 2
            && [96.5, 106.5, 135.0, 145.0, 174.0, 184.0, 213.0, 223.0].contains { abs(line.position.y - $0) < 1.0 }
    }

    return false
}

private func editableLineResolvedFontSize(_ fontSize: CGFloat, scaleY: CGFloat) -> CGFloat {
    fontSize * scaleY * (fontSize <= 4.0 ? 0.74 : 0.82)
}

struct IssueBuilderView: View {
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    @StateObject private var issueStore = IssueDraftStore.shared
    @State private var selectedSectionIDs: Set<IssueSectionType> = []
    @State private var selectedScheme: PenPalColourScheme = .clean
    @State private var generated = false
    private var language: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .english }

    private var sections: [IssueSection] {
        [
            .init(title: t("Monthly Reset", "Monatsreset", "Reset mensile", "Reinicio mensual", "Reset mensuel"), type: .monthlyReset),
            .init(title: t("Tiny Wins", "Kleine Siege", "Piccole vittorie", "Pequeñas victorias", "Petites victoires"), type: .tinyWins),
            .init(title: t("Hobbies", "Hobbys", "Hobby", "Aficiones", "Loisirs"), type: .hobbies),
            .init(title: t("Relationships", "Beziehungen", "Relazioni", "Relaciones", "Relations"), type: .relationships),
            .init(title: t("Playlist & Music", "Playlist & Musik", "Playlist & musica", "Playlist y música", "Playlist & musique"), type: .playlist),
            .init(title: t("Cinema", "Filme & Serien", "Cinema", "Cine", "Cinéma"), type: .cinema),
            .init(title: t("Reading", "Lesen", "Letture", "Lectura", "Lecture"), type: .reading),
            .init(title: t("Food & Recipes", "Essen & Rezepte", "Cibo & ricette", "Comida y recetas", "Cuisine & recettes"), type: .food),
            .init(title: t("Travel & Places", "Reisen & Orte", "Viaggi & luoghi", "Viajes y lugares", "Voyages & lieux"), type: .travel),
            .init(title: t("Favourites", "Favoriten", "Preferiti", "Favoritos", "Favoris"), type: .favourites),
            .init(title: t("Affirmations & Goals", "Affirmationen & Ziele", "Affermazioni & obiettivi", "Afirmaciones y metas", "Affirmations & objectifs"), type: .affirmations)
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(t("Create a new issue", "Neue Ausgabe erstellen", "Crea un nuovo numero", "Crear nueva edición", "Créer un nouveau numéro"))
                        .font(.custom("Georgia", size: 32))
                    Text(t("Tick the sections you want to include this month.", "Wähle die Kapitel aus, die du diesen Monat einschließen willst.", "Seleziona le sezioni che vuoi includere questo mese.", "Marca las secciones que quieres incluir este mes.", "Coche les sections que tu veux inclure ce mois-ci."))
                        .foregroundStyle(.secondary)
                    Divider()
                    Text(t("Colour scheme", "Farbschema", "Schema colori", "Esquema de color", "Palette couleur")).font(.headline)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(PenPalColourScheme.allCases) { scheme in
                            SchemeCard(scheme: scheme, isSelected: selectedScheme == scheme)
                                .onTapGesture { selectedScheme = scheme }
                        }
                    }
                    Divider()
                    Text(t("Sections", "Kapitel", "Sezioni", "Secciones", "Sections")).font(.headline)
                    VStack(spacing: 10) {
                        ForEach(sections) { section in
                            SelectableSectionRow(section: section, isSelected: selectedSectionIDs.contains(section.type)) { toggle(section) }
                        }
                    }
                    Button { generateIssue() } label: {
                        Text(t("Generate full magazine", "Ganzes Magazin erstellen", "Genera magazine completo", "Generar revista completa", "Générer le magazine complet"))
                            .font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity).padding()
                            .background(selectedSectionIDs.isEmpty ? Color.gray : Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }.disabled(selectedSectionIDs.isEmpty)
                    NavigationLink("", destination: GeneratedIssueReviewView(colourScheme: selectedScheme), isActive: $generated).hidden()
                }.padding()
            }
            .background(PenPalStyle.background.ignoresSafeArea())
            .navigationTitle(t("Build Issue", "Ausgabe erstellen", "Crea numero", "Crear edición", "Créer le numéro"))
        }
    }
    private func toggle(_ section: IssueSection) {
        if selectedSectionIDs.contains(section.type) { selectedSectionIDs.remove(section.type) } else { selectedSectionIDs.insert(section.type) }
    }
    private func generateIssue() {
        let chosen = sections.filter { selectedSectionIDs.contains($0.type) }
        issueStore.pages = MagazineTemplateFactory.makeIssue(sections: chosen, scheme: selectedScheme)
        issueStore.currentDraftID = nil
        issueStore.currentDraftTitle = nil
        issueStore.currentColourScheme = selectedScheme
        MagazineTemplateFactory.renumberPages(&issueStore.pages)
        MagazineTemplateLocalization.localizePages(&issueStore.pages, language: language)
        generated = true
    }
    private func t(_ en: String, _ de: String, _ it: String, _ es: String, _ fr: String) -> String {
        switch language { case .english: return en; case .german: return de; case .italian: return it; case .spanish: return es; case .french: return fr }
    }
}

struct SchemeCard: View {
    let scheme: PenPalColourScheme; let isSelected: Bool
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) { Circle().fill(Color(uiColor: scheme.paper)).frame(width: 18, height: 18); Circle().fill(Color(uiColor: scheme.accent)).frame(width: 18, height: 18); Circle().fill(Color(uiColor: scheme.ink)).frame(width: 18, height: 18) }
            Text(appText(scheme.rawValue, languageRaw)).font(.caption.weight(.semibold))
        }.frame(maxWidth: .infinity, alignment: .leading).padding().background(Color(uiColor: scheme.paper)).clipShape(RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(isSelected ? Color.black : Color.clear, lineWidth: 2))
    }
}

struct SelectableSectionRow: View {
    let section: IssueSection; let isSelected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square").font(.title2).foregroundStyle(isSelected ? .black : .secondary)
                Text(section.title).font(.system(size: 18)).foregroundStyle(.primary)
                Spacer()
            }.padding().frame(maxWidth: .infinity, minHeight: 64, alignment: .leading).background(isSelected ? Color.black.opacity(0.08) : Color.gray.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 16)).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

struct GeneratedIssueReviewView: View {
    @StateObject private var issueStore = IssueDraftStore.shared
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    let colourScheme: PenPalColourScheme
    @State private var showEditor = false
    
    private var pageCount: Int { issueStore.pages.count }
    private var isOverPageLimit: Bool { pageCount > 30 }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(appText("Preprint review", languageRaw)).font(.custom("Georgia", size: 30))
                Text(appText("Delete any pages you don't want to include. Magazines can contain up to 30 pages.", languageRaw)).foregroundStyle(.secondary)
                Text("\(pageCount) / 30 \(appText("pages", languageRaw))")
                    .font(.headline)
                    .foregroundStyle(isOverPageLimit ? .red : PenPalStyle.ink)
                
                if isOverPageLimit {
                    Text(appText("Your magazine has more than 30 pages. Delete pages before publishing.", languageRaw))
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 14)], spacing: 14) {
                    ForEach(Array(issueStore.pages.enumerated()), id: \.element.id) { index, page in
                        VStack(spacing: 8) {
                            ZStack(alignment: .topTrailing) {
                                SinglePageCanvas(page: binding(for: index), editable: false)
                                    .aspectRatio(170.0 / 250.0, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .shadow(color: .black.opacity(0.12), radius: 5, x: 0, y: 3)

                                Button {
                                    removePage(at: index)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 24, height: 24)
                                        .background(Color.black.opacity(0.72))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .padding(6)
                            }

                            Text("\(appText("Page", languageRaw)) \(index + 1) / 30")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(index >= 30 ? .red : PenPalStyle.ink)
                        }
                        .padding(10)
                        .background(Color.gray.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                Button {
                    showEditor = true
                } label: {
                    Text(appText("Edit selected pages", languageRaw))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }.padding()
        }
        .background(PenPalStyle.background.ignoresSafeArea())
        .navigationTitle(appText("Generated issue", languageRaw))
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showEditor) {
            NavigationStack {
                LockedMagazineEditorView(colourScheme: colourScheme)
            }
        }
    }
    private func binding(for index: Int) -> Binding<MagazinePage> {
        Binding(
            get: {
                guard issueStore.pages.indices.contains(index) else { return emptyMagazinePage }
                return issueStore.pages[index]
            },
            set: { page in
                guard issueStore.pages.indices.contains(index) else { return }
                issueStore.pages[index] = page
            }
        )
    }

    private func removePage(at index: Int) {
        guard issueStore.pages.indices.contains(index) else { return }
        issueStore.pages.remove(at: index)
        MagazineTemplateFactory.renumberPages(&issueStore.pages)
    }
}

private struct LightweightPagePreview: View {
    let page: MagazinePage
    let pageNumber: Int

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let scaleX = width / 170.0
            let scaleY = height / 250.0

            ZStack {
                Color(uiColor: page.backgroundColor)

                ForEach(page.elements.prefix(36)) { element in
                    previewElement(element, scaleX: scaleX, scaleY: scaleY)
                }

                Text("\(pageNumber)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(5)
                    .background(Color.white.opacity(0.75))
                    .clipShape(Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.08), lineWidth: 1))
        }
        .aspectRatio(170.0 / 250.0, contentMode: .fit)
    }

    @ViewBuilder
    private func previewElement(_ element: MagazineElement, scaleX: CGFloat, scaleY: CGFloat) -> some View {
        let frameWidth = max(1, element.size.width * scaleX)
        let frameHeight = max(1, element.size.height * scaleY)
        let x = element.position.x * scaleX
        let y = element.position.y * scaleY

        switch element.type {
        case .image:
            if let image = element.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: frameWidth, height: frameHeight)
                    .clipped()
                    .position(x: x, y: y)
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.black.opacity(0.08))
                    .frame(width: frameWidth, height: frameHeight)
                    .position(x: x, y: y)
            }
        case .line:
            Rectangle()
                .fill(Color(uiColor: page.textColor).opacity(0.35))
                .frame(width: frameWidth, height: max(0.5, min(1.2, frameHeight)))
                .position(x: x, y: y)
        case .box:
            RoundedRectangle(cornerRadius: 1.5)
                .stroke(Color(uiColor: page.textColor).opacity(0.25), lineWidth: 0.8)
                .frame(width: frameWidth, height: frameHeight)
                .position(x: x, y: y)
        case .title, .text:
            if !element.text.isEmpty {
                Text(String(element.text.prefix(18)))
                    .font(.system(size: max(3.5, min(9, element.fontSize * scaleY)), weight: element.isBold ? .bold : .regular))
                    .foregroundStyle(Color(uiColor: page.textColor).opacity(0.75))
                    .lineLimit(2)
                    .frame(width: frameWidth, height: frameHeight, alignment: .leading)
                    .position(x: x, y: y)
            }
        }
    }
}

struct LockedMagazineEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var issueStore = IssueDraftStore.shared
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    @AppStorage("displayName") private var displayName: String = ""
    let colourScheme: PenPalColourScheme
    @State private var currentPageIndex = 0
    @State private var selectedElementID: UUID?
    @State private var messageText = ""
    @State private var isSavingDraft = false
    @State private var resetPageZoomID = UUID()
    @State private var focusResetID = UUID()
    @State private var keyboardHeight: CGFloat = 0
    @State private var loadingImagePaths: Set<String> = []
    @State private var showFinishedPreview = false
    @State private var templateTextUnlocked = false

    init(colourScheme: PenPalColourScheme, initialPageIndex: Int = 0) {
        self.colourScheme = colourScheme
        _currentPageIndex = State(initialValue: initialPageIndex)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack {
                    Button {
                        clearEditorFocus()
                        dismiss()
                    } label: {
                        Label(appText("Back", languageRaw), systemImage: "chevron.left")
                            .labelStyle(.titleAndIcon)
                    }

                    Spacer()
                }

                HStack {
                    Button {
                        clearEditorFocus()
                        currentPageIndex = max(0, currentPageIndex - 1)
                        clampCurrentPageIndex()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(currentPageIndex == 0)

                    Spacer()

                    Text("\(appText("Page", languageRaw)) \(min(currentPageIndex + 1, issueStore.pages.count)) / \(issueStore.pages.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if currentPageHasUnlockableTemplateText {
                        if templateTextUnlocked {
                            Text(appText("Tap highlighted text to edit", languageRaw))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Button {
                            clearEditorFocus()
                            templateTextUnlocked.toggle()
                        } label: {
                            Image(systemName: templateTextUnlocked ? "lock.open" : "lock")
                        }
                        .accessibilityLabel(templateTextUnlocked ? "Lock template text" : "Unlock template text")
                    }

                    Button {
                        clearEditorFocus()
                        currentPageIndex = min(max(issueStore.pages.count - 1, 0), currentPageIndex + 1)
                        clampCurrentPageIndex()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(currentPageIndex >= issueStore.pages.count - 1)
                }
            }
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 8)
            .background(.ultraThinMaterial)

            GeometryReader { geo in
                VStack(spacing: 12) {
                        if issueStore.pages.indices.contains(currentPageIndex) {
                            let pageWidth = min(geo.size.width - 16, 386)
                            let safePageWidth = max(260, pageWidth)
                            let pageHeight = safePageWidth * 250 / 170

                            ZoomableEditorPageCanvas(
                                page: binding(for: currentPageIndex),
                                selectedElementID: $selectedElementID,
                                pageSize: CGSize(width: safePageWidth, height: pageHeight),
                                isPhotoSelected: isSelectedImageElement,
                                resetZoomID: resetPageZoomID,
                                focusResetID: focusResetID,
                                templateTextUnlocked: templateTextUnlocked,
                                keyboardBottomInset: keyboardHeight
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: max(260, geo.size.height - (keyboardHeight > 0 ? 16 : 96)))
                            .shadow(radius: 3)
                        }
                        
                        if issueStore.pages.isEmpty {
                            Text(appText("No pages to edit.", languageRaw))
                                .foregroundStyle(.secondary)
                                .padding(.top, 40)
                        }

                        Button {
                            clearEditorFocus()
                            showFinishedPreview = true
                        } label: {
                            Text(appText("Preview finished magazine", languageRaw))
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.black)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)

                        if !messageText.isEmpty {
                            Text(messageText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                        }
                    }
                    .frame(minWidth: geo.size.width, maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
        .background(PenPalStyle.background.ignoresSafeArea())
        .navigationTitle(appText("Edit magazine", languageRaw))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            MagazineTemplateFactory.renumberPages(&issueStore.pages)
            clampCurrentPageIndex()
            hydrateCurrentPageImagesIfNeeded()
        }
        .onChange(of: issueStore.pages.count) { _, _ in
            clampCurrentPageIndex()
            hydrateCurrentPageImagesIfNeeded()
        }
        .onChange(of: currentPageIndex) { _, _ in
            clearEditorFocus()
            if !currentPageHasUnlockableTemplateText {
                templateTextUnlocked = false
            }
            hydrateCurrentPageImagesIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            keyboardHeight = keyboardHeight(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
        .sheet(isPresented: $showFinishedPreview) {
            NavigationStack {
                FinishedMagazinePreviewView(colourScheme: colourScheme)
            }
        }
    }

    private func binding(for index: Int) -> Binding<MagazinePage> {
        Binding(
            get: {
                guard issueStore.pages.indices.contains(index) else { return emptyMagazinePage }
                return issueStore.pages[index]
            },
            set: { page in
                guard issueStore.pages.indices.contains(index) else { return }
                issueStore.pages[index] = page
            }
        )
    }

    private func clampCurrentPageIndex() {
        currentPageIndex = min(max(currentPageIndex, 0), max(issueStore.pages.count - 1, 0))
                if issueStore.pages.isEmpty {
                    currentPageIndex = 0
                    selectedElementID = nil
                }
        if issueStore.currentColourScheme == nil {
            issueStore.currentColourScheme = PenPalColourScheme.inferred(from: issueStore.pages) ?? colourScheme
        }
    }

    private func clearEditorFocus() {
        dismissKeyboard()
        selectedElementID = nil
        focusResetID = UUID()
    }

    private func keyboardHeight(from notification: Notification) -> CGFloat {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return 0 }
        return max(0, frame.height)
    }

    private var isSelectedImageElement: Bool {
        guard let selectedElementID,
              issueStore.pages.indices.contains(currentPageIndex),
              let element = issueStore.pages[currentPageIndex].elements.first(where: { $0.id == selectedElementID })
        else { return false }
        return element.type == .image && element.image != nil
    }

    private var currentPageHasUnlockableTemplateText: Bool {
        guard issueStore.pages.indices.contains(currentPageIndex) else { return false }
        return issueStore.pages[currentPageIndex].elements.contains {
            isUnlockableTemplateText($0, page: issueStore.pages[currentPageIndex])
        }
    }

    private func hydrateCurrentPageImagesIfNeeded() {
        guard issueStore.pages.indices.contains(currentPageIndex) else { return }
        print("EDITOR_VISIBLE_PAGE_RENDER page", currentPageIndex, "pageCount", issueStore.pages.count, "elements", issueStore.pages[currentPageIndex].elements.count)
        for index in issueStore.pages[currentPageIndex].elements.indices {
            guard issueStore.pages[currentPageIndex].elements[index].type == .image,
                  issueStore.pages[currentPageIndex].elements[index].image == nil else { continue }

            let elementID = issueStore.pages[currentPageIndex].elements[index].id

            if let localPath = issueStore.pages[currentPageIndex].elements[index].localImagePath,
               !localPath.isEmpty {
                let start = CFAbsoluteTimeGetCurrent()
                DispatchQueue.global(qos: .userInitiated).async {
                    let image = downsampledImageFromFile(path: localPath, maxPixelSize: 850)
                    DispatchQueue.main.async {
                        let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                        guard issueStore.pages.indices.contains(currentPageIndex),
                              let currentIndex = issueStore.pages[currentPageIndex].elements.firstIndex(where: { $0.id == elementID }) else { return }
                        if let image {
                            issueStore.pages[currentPageIndex].elements[currentIndex].image = image
                            print("VISIBLE_IMAGE_LOCAL_LOAD_END page", currentPageIndex, "element", elementID, "elapsedMs", elapsed)
                        } else {
                            print("VISIBLE_IMAGE_LOCAL_LOAD_FAILED page", currentPageIndex, "element", elementID, "elapsedMs", elapsed)
                        }
                    }
                }
                continue
            }

            if let path = issueStore.pages[currentPageIndex].elements[index].imageStoragePath, !path.isEmpty {
                guard !loadingImagePaths.contains(path) else { continue }
                loadingImagePaths.insert(path)
                let start = CFAbsoluteTimeGetCurrent()
                print("VISIBLE_IMAGE_STORAGE_LOAD_START page", currentPageIndex, "element", elementID, "path", path)
                FirestoreManager.shared.loadStoredUIImage(path: path, maxPixelSize: 850) { image in
                    let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                    loadingImagePaths.remove(path)
                    guard issueStore.pages.indices.contains(currentPageIndex),
                          let currentIndex = issueStore.pages[currentPageIndex].elements.firstIndex(where: { $0.id == elementID }) else { return }
                    if let image {
                        issueStore.pages[currentPageIndex].elements[currentIndex].image = image
                        print("VISIBLE_IMAGE_STORAGE_LOAD_END page", currentPageIndex, "element", elementID, "elapsedMs", elapsed)
                    } else {
                        print("VISIBLE_IMAGE_STORAGE_LOAD_FAILED page", currentPageIndex, "element", elementID, "elapsedMs", elapsed)
                    }
                }
                continue
            }

            if let imageData = issueStore.pages[currentPageIndex].elements[index].imageData, !imageData.isEmpty {
                let start = CFAbsoluteTimeGetCurrent()
                DispatchQueue.global(qos: .userInitiated).async {
                    let image = downsampledImageFromBase64(imageData, maxPixelSize: 850)
                    DispatchQueue.main.async {
                        let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                        guard issueStore.pages.indices.contains(currentPageIndex),
                              let currentIndex = issueStore.pages[currentPageIndex].elements.firstIndex(where: { $0.id == elementID }) else { return }
                        if let image {
                            issueStore.pages[currentPageIndex].elements[currentIndex].image = image
                            print("VISIBLE_IMAGE_BASE64_DECODE_END page", currentPageIndex, "element", elementID, "elapsedMs", elapsed)
                        } else {
                            print("VISIBLE_IMAGE_BASE64_DECODE_FAILED page", currentPageIndex, "element", elementID, "elapsedMs", elapsed)
                        }
                    }
                }
            }
        }
    }

    private func saveDraft() {
        guard !issueStore.pages.isEmpty else {
            messageText = appText("Create at least one page first.", languageRaw)
            return
        }

        isSavingDraft = true
        messageText = ""

        let title = issueStore.currentDraftTitle ?? "\(displayName)'s Draft Issue"
        let draftID = issueStore.currentDraftID ?? UUID().uuidString

        let scheme = issueStore.currentColourScheme ?? PenPalColourScheme.inferred(from: issueStore.pages) ?? colourScheme
        let pagesSnapshot = issueStore.pages
        let previewImageData = pagesSnapshot.first.flatMap { thumbnailSnapshotMagazinePage($0) }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try LocalIssueDraftStore.save(pages: pagesSnapshot, title: title, draftID: draftID, colourScheme: scheme, previewImageData: previewImageData)
                DispatchQueue.main.async {
                    issueStore.currentDraftID = draftID
                    issueStore.currentDraftTitle = title
                    issueStore.currentColourScheme = scheme
                    isSavingDraft = false
                    messageText = appText("Draft saved locally. Syncing backup...", languageRaw)
                    syncDraftBackup(draftID: draftID, title: title, colourScheme: scheme)
                }
            } catch {
                DispatchQueue.main.async {
                    isSavingDraft = false
                    messageText = "\(appText("Draft could not be saved:", languageRaw)) \(error.localizedDescription)"
                }
            }
        }
    }

    private func syncDraftBackup(draftID: String, title: String, colourScheme: PenPalColourScheme) {
        guard let localPages = try? LocalIssueDraftStore.loadPages(id: draftID) else { return }
        FirestoreManager.shared.uploadMagazineImages(
            in: localPages,
            basePath: "issueDrafts/\(Auth.auth().currentUser?.uid ?? "unknown")/\(draftID)/images"
        ) { result in
            guard case .success(let preparedPages) = result,
                  let pageDraftData = MagazineDraftCodec.encode(preparedPages) else {
                print("DRAFT_BACKUP_SYNC_FAILED", draftID)
                return
            }

            FirestoreManager.shared.saveIssueDraft(
                title: title,
                pageImageData: [],
                pageDraftData: pageDraftData,
                draftID: draftID,
                colourScheme: colourScheme
            ) { error in
                DispatchQueue.main.async {
                    if let error {
                        print("DRAFT_BACKUP_SYNC_FAILED", draftID, error)
                        messageText = appText("Draft saved locally. Cloud backup failed.", languageRaw)
                    } else {
                        _ = try? LocalIssueDraftStore.save(pages: preparedPages, title: title, draftID: draftID, colourScheme: colourScheme)
                        messageText = appText("Draft saved locally and synced.", languageRaw)
                    }
                }
            }
        }
    }
}

struct ZoomableEditorPageCanvas: UIViewRepresentable {
    @Binding var page: MagazinePage
    @Binding var selectedElementID: UUID?
    let pageSize: CGSize
    let isPhotoSelected: Bool
    let resetZoomID: UUID
    let focusResetID: UUID
    let templateTextUnlocked: Bool
    let keyboardBottomInset: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.panGestureRecognizer.cancelsTouchesInView = true

        let hosting = UIHostingController(rootView: hostedPage)
        hosting.view.backgroundColor = .clear
        hosting.view.frame = CGRect(origin: .zero, size: pageSize)
        scrollView.addSubview(hosting.view)

        context.coordinator.hostingController = hosting
        context.coordinator.hostedView = hosting.view
        context.coordinator.lastResetZoomID = resetZoomID
        context.coordinator.centerContent(in: scrollView, pageSize: pageSize)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.resetZoomFromTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        context.coordinator.scrollView = scrollView

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.hostingController?.rootView = hostedPage
        context.coordinator.hostedView?.frame = CGRect(origin: .zero, size: pageSize)
        scrollView.contentSize = pageSize
        scrollView.contentInset.bottom = keyboardBottomInset
        scrollView.verticalScrollIndicatorInsets.bottom = keyboardBottomInset
        scrollView.isScrollEnabled = !isPhotoSelected
        scrollView.pinchGestureRecognizer?.isEnabled = !isPhotoSelected

        if context.coordinator.lastResetZoomID != resetZoomID {
            context.coordinator.lastResetZoomID = resetZoomID
            scrollView.setZoomScale(1, animated: true)
        }

        context.coordinator.centerContent(in: scrollView, pageSize: pageSize)
    }

    private var hostedPage: AnyView {
        AnyView(SinglePageCanvas(
            page: $page,
            editable: true,
            selectedElementID: $selectedElementID,
            focusResetID: focusResetID,
            templateTextUnlocked: templateTextUnlocked
        )
        .frame(width: pageSize.width, height: pageSize.height))
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var hostingController: UIHostingController<AnyView>?
        weak var hostedView: UIView?
        weak var scrollView: UIScrollView?
        var lastResetZoomID: UUID?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            hostedView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContent(in: scrollView, pageSize: scrollView.contentSize)
        }

        func centerContent(in scrollView: UIScrollView, pageSize: CGSize) {
            guard let hostedView else { return }
            let horizontalInset = max(0, (scrollView.bounds.width - hostedView.frame.width) / 2)
            let verticalInset = max(0, (scrollView.bounds.height - hostedView.frame.height) / 2)
            scrollView.contentInset = UIEdgeInsets(top: verticalInset, left: horizontalInset, bottom: verticalInset, right: horizontalInset)
            if scrollView.contentSize != pageSize {
                scrollView.contentSize = pageSize
            }
        }

        @objc func resetZoomFromTap(_ recognizer: UITapGestureRecognizer) {
            scrollView?.setZoomScale(1, animated: true)
        }
    }
}

struct FinishedMagazinePreviewView: View {
    @StateObject private var issueStore = IssueDraftStore.shared
    @StateObject private var groupStore = PenpalGroupStore.shared
    @AppStorage("homeResetID") private var homeResetID: String = UUID().uuidString
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    @AppStorage("displayName") private var displayName: String = ""
    let colourScheme: PenPalColourScheme
    @State private var currentPageIndex = 0
    @State private var selectedGroupIDs: Set<String> = []
    @State private var selectedSectionIDsToAdd: Set<IssueSectionType> = []
    @State private var showPublishOptions = false
    @State private var showAddSections = false
    @State private var isPublishing = false
    @State private var isSavingDraft = false
    @State private var messageText = ""
    @State private var loadingImagePaths: Set<String> = []
    @State private var editorRoute: EditorPageRoute?
    @Environment(\.dismiss) private var dismiss

    init(colourScheme: PenPalColourScheme, showAddSectionsOnAppear: Bool = false) {
        self.colourScheme = colourScheme
        _showAddSections = State(initialValue: showAddSectionsOnAppear)
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .english
    }

    private var sectionStartIndices: [(title: String, index: Int)] {
        var seen: Set<String> = []
        return issueStore.pages.indices.compactMap { index in
            let title = issueStore.pages[index].sectionTitle
            guard !seen.contains(title) else { return nil }
            seen.insert(title)
            return (title, index)
        }
    }

    private var sections: [IssueSection] {
        [
            .init(title: t("Monthly Reset", "Monatsreset", "Reset mensile", "Reinicio mensual", "Reset mensuel"), type: .monthlyReset),
            .init(title: t("Tiny Wins", "Kleine Siege", "Piccole vittorie", "Pequeñas victorias", "Petites victoires"), type: .tinyWins),
            .init(title: t("Hobbies", "Hobbys", "Hobby", "Aficiones", "Loisirs"), type: .hobbies),
            .init(title: t("Relationships", "Beziehungen", "Relazioni", "Relaciones", "Relations"), type: .relationships),
            .init(title: t("Playlist & Music", "Playlist & Musik", "Playlist & musica", "Playlist y música", "Playlist & musique"), type: .playlist),
            .init(title: t("Cinema", "Filme & Serien", "Cinema", "Cine", "Cinéma"), type: .cinema),
            .init(title: t("Reading", "Lesen", "Letture", "Lectura", "Lecture"), type: .reading),
            .init(title: t("Food & Recipes", "Essen & Rezepte", "Cibo & ricette", "Comida y recetas", "Cuisine & recettes"), type: .food),
            .init(title: t("Travel & Places", "Reisen & Orte", "Viaggi & luoghi", "Viajes y lugares", "Voyages & lieux"), type: .travel),
            .init(title: t("Favourites", "Favoriten", "Preferiti", "Favoritos", "Favoris"), type: .favourites),
            .init(title: t("Affirmations & Goals", "Affirmationen & Ziele", "Affermazioni & obiettivi", "Afirmaciones y metas", "Affirmations & objectifs"), type: .affirmations)
        ]
    }

    private var addableSections: [IssueSection] {
        let existingTitles = Set(issueStore.pages.map { $0.sectionTitle })
        return sections.filter { !existingTitles.contains($0.title) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sectionStartIndices, id: \.index) { section in
                        Button {
                            editorRoute = EditorPageRoute(index: section.index)
                        } label: {
                            HStack(spacing: 6) {
                                Text(section.title)
                                    .lineLimit(1)
                                Image(systemName: "pencil")
                                    .font(.caption2.weight(.bold))
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.gray.opacity(0.12))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
            .background(.ultraThinMaterial)

            ScrollView {
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appText("Finished magazine preview", languageRaw))
                            .font(.custom("Georgia", size: 30))
                        Text(currentSectionSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if issueStore.pages.indices.contains(currentPageIndex) {
                        GeometryReader { geo in
                            let pageWidth = min(272, max(210, geo.size.width - 120))
                            let pageHeight = pageWidth * 250 / 170

                            HStack(spacing: 10) {
                                Button {
                                    goToPreviousPage()
                                } label: {
                                    Image(systemName: "chevron.left")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .frame(width: 44, height: 44)
                                        .background(Color.gray.opacity(0.12))
                                        .clipShape(Circle())
                                }
                                .disabled(currentPageIndex == 0)
                                .opacity(currentPageIndex == 0 ? 0.35 : 1)

                                SinglePageCanvas(page: binding(for: currentPageIndex), editable: false)
                                    .frame(width: pageWidth, height: pageHeight)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .shadow(radius: 3)

                                Button {
                                    goToNextPage()
                                } label: {
                                    Image(systemName: "chevron.right")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .frame(width: 44, height: 44)
                                        .background(Color.gray.opacity(0.12))
                                        .clipShape(Circle())
                                }
                                .disabled(currentPageIndex >= issueStore.pages.count - 1)
                                .opacity(currentPageIndex >= issueStore.pages.count - 1 ? 0.35 : 1)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .frame(height: 410)

                        HStack {
                            Text("\(appText("Page", languageRaw)) \(currentPageIndex + 1) \(appText("of", languageRaw)) \(issueStore.pages.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button {
                                editorRoute = EditorPageRoute(index: currentPageIndex)
                            } label: {
                                Label(appText("Edit this page", languageRaw), systemImage: "pencil")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.black)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)

                            Button {
                                deleteCurrentPage()
                            } label: {
                                Label(appText("Delete page", languageRaw), systemImage: "trash")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.red.opacity(0.9))
                                    .clipShape(Capsule())
                            }
                        }
                    } else {
                        Text(appText("No pages to preview.", languageRaw))
                            .foregroundStyle(.secondary)
                    }

                    saveAndPublishControls
                }
                .padding()
            }
        }
        .navigationTitle(appText("Preview", languageRaw))
        .navigationBarTitleDisplayMode(.inline)
        .background(PenPalStyle.background.ignoresSafeArea())
        .onAppear {
            MagazineTemplateFactory.renumberPages(&issueStore.pages)
            clampCurrentPageIndex()
            hydrateCurrentPageImagesIfNeeded()
            groupStore.loadGroups()
        }
        .onChange(of: issueStore.pages.count) { _, _ in
            clampCurrentPageIndex()
            hydrateCurrentPageImagesIfNeeded()
        }
        .onChange(of: currentPageIndex) { _, _ in
            hydrateCurrentPageImagesIfNeeded()
        }
        .fullScreenCover(item: $editorRoute) { route in
            NavigationStack {
                LockedMagazineEditorView(colourScheme: colourScheme, initialPageIndex: route.index)
            }
        }
    }

    private var currentSectionSummary: String {
        guard issueStore.pages.indices.contains(currentPageIndex) else { return "" }
        return issueStore.pages[currentPageIndex].sectionTitle
    }

    private func hydrateCurrentPageImagesIfNeeded() {
        guard issueStore.pages.indices.contains(currentPageIndex) else { return }
        for index in issueStore.pages[currentPageIndex].elements.indices {
            guard issueStore.pages[currentPageIndex].elements[index].type == .image,
                  issueStore.pages[currentPageIndex].elements[index].image == nil else { continue }
            let elementID = issueStore.pages[currentPageIndex].elements[index].id

            if let localPath = issueStore.pages[currentPageIndex].elements[index].localImagePath,
               !localPath.isEmpty {
                DispatchQueue.global(qos: .userInitiated).async {
                    let image = downsampledImageFromFile(path: localPath, maxPixelSize: 850)
                    DispatchQueue.main.async {
                        guard issueStore.pages.indices.contains(currentPageIndex),
                              let currentIndex = issueStore.pages[currentPageIndex].elements.firstIndex(where: { $0.id == elementID }) else { return }
                        if let image {
                            issueStore.pages[currentPageIndex].elements[currentIndex].image = image
                        } else {
                            print("PREVIEW_VISIBLE_IMAGE_LOCAL_LOAD_FAILED page", currentPageIndex, "element", elementID)
                        }
                    }
                }
                continue
            }

            if let path = issueStore.pages[currentPageIndex].elements[index].imageStoragePath, !path.isEmpty {
                guard !loadingImagePaths.contains(path) else { continue }
                loadingImagePaths.insert(path)
                FirestoreManager.shared.loadStoredUIImage(path: path, maxPixelSize: 850) { image in
                    loadingImagePaths.remove(path)
                    guard issueStore.pages.indices.contains(currentPageIndex),
                          let currentIndex = issueStore.pages[currentPageIndex].elements.firstIndex(where: { $0.id == elementID }) else { return }
                    if let image {
                        issueStore.pages[currentPageIndex].elements[currentIndex].image = image
                    } else {
                        print("PREVIEW_VISIBLE_IMAGE_LOAD_FAILED page", currentPageIndex, "element", elementID)
                    }
                }
                continue
            }

            if let imageData = issueStore.pages[currentPageIndex].elements[index].imageData, !imageData.isEmpty {
                DispatchQueue.global(qos: .userInitiated).async {
                    let image = downsampledImageFromBase64(imageData, maxPixelSize: 850)
                    DispatchQueue.main.async {
                        guard issueStore.pages.indices.contains(currentPageIndex),
                              let currentIndex = issueStore.pages[currentPageIndex].elements.firstIndex(where: { $0.id == elementID }) else { return }
                        if let image {
                            issueStore.pages[currentPageIndex].elements[currentIndex].image = image
                        } else {
                            print("PREVIEW_VISIBLE_IMAGE_DECODE_FAILED page", currentPageIndex, "element", elementID)
                        }
                    }
                }
            }
        }
    }

    private var saveAndPublishControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showAddSections.toggle()
                }
            } label: {
                HStack {
                    Text(appText("Add sections or pages", languageRaw))
                        .font(.headline)
                    Spacer()
                    Image(systemName: showAddSections ? "chevron.up" : "chevron.down")
                }
                .foregroundStyle(.primary)
                .padding()
                .background(Color.gray.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            if showAddSections {
                VStack(alignment: .leading, spacing: 10) {
                    if addableSections.isEmpty {
                        Text(appText("All sections are already in this issue.", languageRaw))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(addableSections) { section in
                            Button {
                                toggleSectionToAdd(section.type)
                            } label: {
                                HStack {
                                    Image(systemName: selectedSectionIDsToAdd.contains(section.type) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedSectionIDsToAdd.contains(section.type) ? .black : .secondary)
                                    Text(section.title)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .padding()
                                .background(Color.gray.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            addSelectedSections()
                        } label: {
                            Text(appText("Add selected", languageRaw))
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(selectedSectionIDsToAdd.isEmpty ? Color.gray : Color.black)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(selectedSectionIDsToAdd.isEmpty)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            Button {
                saveDraft()
            } label: {
                HStack {
                    if isSavingDraft {
                        ProgressView()
                            .tint(.white)
                    }

                    Text(isSavingDraft ? appText("Saving...", languageRaw) : appText("Save for later", languageRaw))
                        .font(.headline)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isPublishing || isSavingDraft || issueStore.pages.isEmpty)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showPublishOptions.toggle()
                }
            } label: {
                HStack {
                    Text(appText("Finish issue", languageRaw))
                        .font(.headline)
                    Spacer()
                    Image(systemName: showPublishOptions ? "chevron.up" : "chevron.down")
                }
                .foregroundStyle(.white)
                .padding()
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isPublishing || isSavingDraft || issueStore.pages.isEmpty || issueStore.pages.count > 30)
            
            if issueStore.pages.count > 30 {
                Text(appText("Your magazine has more than 30 pages. Delete pages before publishing.", languageRaw))
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if showPublishOptions {
                VStack(alignment: .leading, spacing: 10) {
                    Text(appText("Publish to groups", languageRaw))
                        .font(.headline)

                    if groupStore.groups.isEmpty {
                        Text(appText("You are not in any groups yet.", languageRaw))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(groupStore.groups) { group in
                            Button {
                                toggleGroup(group.id)
                            } label: {
                                HStack {
                                    Image(systemName: selectedGroupIDs.contains(group.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedGroupIDs.contains(group.id) ? .black : .secondary)
                                    Text(group.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .padding()
                                .background(Color.gray.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        publishIssue()
                    } label: {
                        HStack {
                            if isPublishing {
                                ProgressView()
                                    .tint(.white)
                            }

                            Text(isPublishing ? appText("Publishing...", languageRaw) : appText("Publish selected groups", languageRaw))
                                .font(.headline)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedGroupIDs.isEmpty ? Color.gray : Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isPublishing || isSavingDraft || selectedGroupIDs.isEmpty || issueStore.pages.count > 30)
                }
                .padding()
                .background(Color.gray.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            if !messageText.isEmpty {
                Text(messageText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func binding(for index: Int) -> Binding<MagazinePage> {
        Binding(
            get: {
                guard issueStore.pages.indices.contains(index) else { return emptyMagazinePage }
                return issueStore.pages[index]
            },
            set: { page in
                guard issueStore.pages.indices.contains(index) else { return }
                issueStore.pages[index] = page
            }
        )
    }

    private func goToPreviousPage() {
        currentPageIndex = max(0, currentPageIndex - 1)
        clampCurrentPageIndex()
    }

    private func goToNextPage() {
        currentPageIndex = min(max(issueStore.pages.count - 1, 0), currentPageIndex + 1)
        clampCurrentPageIndex()
    }

    private func clampCurrentPageIndex() {
        currentPageIndex = min(max(currentPageIndex, 0), max(issueStore.pages.count - 1, 0))
        if issueStore.pages.isEmpty {
            currentPageIndex = 0
        }
    }

    private func toggleGroup(_ id: String) {
        if selectedGroupIDs.contains(id) {
            selectedGroupIDs.remove(id)
        } else {
            selectedGroupIDs.insert(id)
        }
    }

    private func toggleSectionToAdd(_ id: IssueSectionType) {
        if selectedSectionIDsToAdd.contains(id) {
            selectedSectionIDsToAdd.remove(id)
        } else {
            selectedSectionIDsToAdd.insert(id)
        }
    }

    private func addSelectedSections() {
        let chosen = sections.filter { selectedSectionIDsToAdd.contains($0.type) }
        guard !chosen.isEmpty else { return }

        let activeScheme = issueStore.currentColourScheme ?? PenPalColourScheme.inferred(from: issueStore.pages) ?? colourScheme
        issueStore.currentColourScheme = activeScheme
        var generatedPages = MagazineTemplateFactory.makeIssue(sections: chosen, scheme: activeScheme)
        MagazineTemplateFactory.renumberPages(&generatedPages)
        MagazineTemplateLocalization.localizePages(&generatedPages, language: language)
        generatedPages = generatedPages
            .filter { !["Cover", "Contents", "Back"].contains($0.sectionTitle) }

        let backPage = issueStore.pages.last { $0.sectionTitle == "Back" }
        issueStore.pages.removeAll { $0.sectionTitle == "Back" }
        issueStore.pages.append(contentsOf: generatedPages)
        if let backPage {
            issueStore.pages.append(backPage)
        }

        MagazineTemplateFactory.renumberPages(&issueStore.pages)
        selectedSectionIDsToAdd.removeAll()
        showAddSections = false
        messageText = appText("Sections added. Save the draft to keep these changes.", languageRaw)
    }

    private func deleteCurrentPage() {
        guard issueStore.pages.indices.contains(currentPageIndex) else { return }
        issueStore.pages.remove(at: currentPageIndex)
        MagazineTemplateFactory.renumberPages(&issueStore.pages)
        clampCurrentPageIndex()
        messageText = appText("Page deleted. Save the draft to keep this change.", languageRaw)
    }

    private func saveDraft() {
        guard !issueStore.pages.isEmpty else {
            messageText = appText("Create at least one page first.", languageRaw)
            return
        }

        isSavingDraft = true
        messageText = ""

        let title = issueStore.currentDraftTitle ?? "\(displayName)'s Draft Issue"
        let draftID = issueStore.currentDraftID ?? UUID().uuidString

        let scheme = issueStore.currentColourScheme ?? PenPalColourScheme.inferred(from: issueStore.pages) ?? colourScheme
        let pagesSnapshot = issueStore.pages
        let previewImageData = pagesSnapshot.first.flatMap { thumbnailSnapshotMagazinePage($0) }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try LocalIssueDraftStore.save(pages: pagesSnapshot, title: title, draftID: draftID, colourScheme: scheme, previewImageData: previewImageData)
                DispatchQueue.main.async {
                    issueStore.currentDraftID = draftID
                    issueStore.currentDraftTitle = title
                    issueStore.currentColourScheme = scheme
                    isSavingDraft = false
                    messageText = appText("Draft saved locally. Syncing backup...", languageRaw)
                    syncDraftBackup(draftID: draftID, title: title, colourScheme: scheme)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                        dismiss()
                        issueStore.pages.removeAll()
                        issueStore.currentDraftID = nil
                        issueStore.currentDraftTitle = nil
                        issueStore.currentColourScheme = nil
                        homeResetID = UUID().uuidString
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    isSavingDraft = false
                    messageText = "\(appText("Draft could not be saved:", languageRaw)) \(error.localizedDescription)"
                }
            }
        }
    }

    private func syncDraftBackup(draftID: String, title: String, colourScheme: PenPalColourScheme) {
        guard let localPages = try? LocalIssueDraftStore.loadPages(id: draftID) else { return }
        FirestoreManager.shared.uploadMagazineImages(
            in: localPages,
            basePath: "issueDrafts/\(Auth.auth().currentUser?.uid ?? "unknown")/\(draftID)/images"
        ) { result in
            guard case .success(let preparedPages) = result,
                  let pageDraftData = MagazineDraftCodec.encode(preparedPages) else {
                print("DRAFT_BACKUP_SYNC_FAILED", draftID)
                return
            }

            FirestoreManager.shared.saveIssueDraft(
                title: title,
                pageImageData: [],
                pageDraftData: pageDraftData,
                draftID: draftID,
                colourScheme: colourScheme
            ) { error in
                if let error {
                    print("DRAFT_BACKUP_SYNC_FAILED", draftID, error)
                } else {
                    _ = try? LocalIssueDraftStore.save(pages: preparedPages, title: title, draftID: draftID, colourScheme: colourScheme)
                    print("DRAFT_BACKUP_SYNC_SUCCESS", draftID)
                }
            }
        }
    }

    private func publishIssue() {
        guard !issueStore.pages.isEmpty else {
            messageText = appText("Create at least one page first.", languageRaw)
            return
        }

        guard !selectedGroupIDs.isEmpty else {
            messageText = appText("Select at least one group.", languageRaw)
            return
        }

        guard issueStore.pages.count <= 30 else {
            messageText = appText("An issue can contain up to 30 pages.", languageRaw)
            return
        }

        let photoCount = issueStore.pages.reduce(0) { total, page in
            total + page.elements.filter { $0.type == .image }.count
        }

        guard photoCount <= 50 else {
            messageText = appText("Your issue has too many photos. Please keep it under 50 photos.", languageRaw)
            return
        }

        isPublishing = true
        messageText = ""

        let selectedGroups = groupStore.groups.filter {
            selectedGroupIDs.contains($0.id)
        }
        let title = localizedIssueTitle(owner: displayName, month: Calendar.current.component(.month, from: Date()), languageRaw: languageRaw)

        let issueID = UUID().uuidString
        FirestoreManager.shared.uploadMagazineImages(
            in: issueStore.pages,
            basePath: "publishedIssues/\(issueID)/images"
        ) { result in
            switch result {
            case .failure(let error):
                isPublishing = false
                messageText = "\(appText("Issue could not be published:", languageRaw)) \(error.localizedDescription)"

            case .success(let preparedPages):
                issueStore.pages = preparedPages
                guard let pageDraftData = MagazineDraftCodec.encode(preparedPages) else {
                    isPublishing = false
                    messageText = appText("Issue could not be prepared for publishing.", languageRaw)
                    return
                }

                FirestoreManager.shared.publishIssueToGroups(
                    title: title,
                    groups: selectedGroups,
                    pageImageData: [],
                    pageDraftData: pageDraftData,
                    issueID: issueID,
                    colourScheme: issueStore.currentColourScheme ?? PenPalColourScheme.inferred(from: preparedPages) ?? colourScheme
                ) { error in
                    DispatchQueue.main.async {
                        isPublishing = false
                        if let error {
                            messageText = "\(appText("Issue could not be published:", languageRaw)) \(error)"
                            return
                        }

                        if let draftID = issueStore.currentDraftID {
                            FirestoreManager.shared.deleteIssueDraft(id: draftID)
                        }

                        messageText = appText("Issue published. You can find it in old magazines.", languageRaw)

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            dismiss()
                            issueStore.pages.removeAll()
                            issueStore.currentDraftID = nil
                            issueStore.currentDraftTitle = nil
                            issueStore.currentColourScheme = nil
                            homeResetID = UUID().uuidString
                        }
                    }
                }
            }
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


struct SinglePageCanvas: View {
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    @Binding var page: MagazinePage
    let editable: Bool
    var selectedElementID: Binding<UUID?>? = nil
    var focusResetID: UUID? = nil
    var templateTextUnlocked: Bool = false
    @State private var focusedLineID: UUID?

    var body: some View {
        GeometryReader { geo in
            let safeCanvasSize = safeSize(geo.size, fallback: CGSize(width: 170, height: 250), context: "SinglePageCanvas.canvas")
            let scaleX = safeCGFloat(safeCanvasSize.width / 170, fallback: 1, min: 0.01, max: 20, context: "SinglePageCanvas.scaleX")
            let scaleY = safeCGFloat(safeCanvasSize.height / 250, fallback: 1, min: 0.01, max: 20, context: "SinglePageCanvas.scaleY")

            ZStack(alignment: .topLeading) {
                Color(uiColor: page.backgroundColor)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedElementID?.wrappedValue = nil
                        focusedLineID = nil
                        dismissKeyboard()
                    }

                ForEach(Array(page.elements.enumerated()), id: \.element.id) { index, element in
                    let selectableText = editable
                        && (element.type == .text || element.type == .title)
                        && isCanvasEditableText(element)
                        && (!isStaticPromptLabel(element) || isUnlockedTemplateText(element))
                    let displayFrame = displayUsesEditableBox(element) ? editableTextFrame(for: element) : nil
                    let displaySize = safeSize(displayFrame?.size ?? element.size, context: "elementSize.\(element.id)")
                    let displayPosition = safePoint(displayFrame?.position ?? self.displayPosition(for: element), context: "elementPosition.\(element.id)")

                    PowerPointElementView(
                        element: elementBinding(for: index),
                        page: page,
                        editable: editable,
                        isSelected: selectedElementID?.wrappedValue == element.id,
                        scaleX: scaleX,
                        scaleY: scaleY,
                        suppressLineText: !editable && isEditableWritingLine(element)
                    )
                    .frame(width: safeCGFloat(displaySize.width * scaleX, fallback: 1, min: 0.1, context: "elementFrameW.\(element.id)"), height: safeCGFloat(displaySize.height * scaleY, fallback: 1, min: 0.1, context: "elementFrameH.\(element.id)"))
                    .position(x: displayPosition.x * scaleX, y: displayPosition.y * scaleY)
                    .zIndex(baseElementZIndex(for: element))
                    .contentShape(Rectangle())
                    .allowsHitTesting(selectableText)
                    .onTapGesture {
                        if selectableText {
                            beginEditingText(at: index)
                        }
                    }
                }

                if !editable {
                    ForEach(Array(page.elements.enumerated()).filter { isEditableWritingLine($0.element) && !isContinuousColumnLine($0.element) }, id: \.element.id) { index, element in
                        let style = lineTextStyle(for: element)
                        let lineFrame = writingLineOverlayFrame(for: element)

                        EditableLineOverlay(
                            element: elementBinding(for: index),
                            page: page,
                            scaleX: scaleX,
                            scaleY: scaleY,
                            characterLimit: lineCharacterLimit(for: element),
                            fontName: style.fontName,
                            fontSize: style.fontSize,
                            isBold: style.isBold,
                            isFocused: false,
                            allowsWrapping: lineWrappingAllowed(element),
                            maximumNumberOfLines: lineMaximumNumberOfLines(element),
                            lineHeight: editableLineTextLineHeight(for: element, styleFontSize: style.fontSize, scaleY: scaleY),
                            isReadOnly: true,
                            onFocus: {},
                            onDismiss: {},
                            onOverflow: { _ in }
                        )
                            .frame(width: lineFrame.size.width * scaleX, height: editableLineOverlayHeight(for: element, styleFontSize: style.fontSize, scaleY: scaleY))
                            .position(x: lineFrame.position.x * scaleX, y: lineFrame.position.y * scaleY)
                            .zIndex(801)
                    }

                    ForEach(continuousColumnRootIndices(), id: \.self) { index in
                        if page.elements.indices.contains(index) {
                        let frame = continuousColumnRect(for: page.elements[index])

                        ContinuousColumnTextOverlay(
                            element: elementBinding(for: index),
                            page: page,
                            scaleX: scaleX,
                            scaleY: scaleY,
                            layout: continuousColumnLayout,
                            characterLimit: continuousColumnCharacterLimit(for: frame.size),
                            isFocused: false,
                            isReadOnly: true,
                            onFocus: {},
                            onDismiss: {}
                        )
                            .frame(width: frame.size.width * scaleX, height: frame.size.height * scaleY)
                            .position(x: frame.midX * scaleX, y: frame.midY * scaleY)
                            .zIndex(800)
                        }
                    }
                }

                if editable {
                    if templateTextUnlocked {
                        ForEach(Array(page.elements.enumerated()).filter { isUnlockableTemplateText($0.element, page: page) }, id: \.element.id) { _, element in
                            let highlightSize = unlockableTemplateHighlightSize(for: element, scaleX: scaleX, scaleY: scaleY)
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color(uiColor: page.titleColor).opacity(0.045))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(
                                            Color(uiColor: page.titleColor).opacity(0.34),
                                            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                                        )
                                )
                                .frame(width: highlightSize.width, height: highlightSize.height)
                                .position(x: element.position.x * scaleX, y: element.position.y * scaleY)
                                .zIndex(1390)
                                .allowsHitTesting(false)
                        }
                    }

                    ForEach(Array(page.elements.enumerated()).filter { editableTextIndex(in: $0.element) != nil }, id: \.element.id) { index, element in
                        Button {
                            if let textIndex = editableTextIndex(in: element) {
                                beginEditingText(at: textIndex)
                            }
                        } label: {
                            Color.clear.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(width: element.size.width * scaleX, height: element.size.height * scaleY)
                        .position(x: element.position.x * scaleX, y: element.position.y * scaleY)
                        .zIndex(isCinemaHighlightsOneLineBox(element) ? 1700 : 895)
                        .allowsHitTesting(editableTextIndex(in: element).map { page.elements[$0].id != selectedElementID?.wrappedValue } ?? true)
                    }



                    // Standalone editable labels/fields such as DATE, MOOD, FEELING and your name.
                    ForEach(Array(page.elements.enumerated()).filter { isStandaloneEditableText($0.element) }, id: \.element.id) { index, element in
                        Button {
                            beginEditingText(at: index)
                        } label: {
                            Color.clear.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(width: standaloneEditableHitSize(for: element, scaleX: scaleX, scaleY: scaleY).width, height: standaloneEditableHitSize(for: element, scaleX: scaleX, scaleY: scaleY).height)
                        .position(x: element.position.x * scaleX, y: element.position.y * scaleY)
                        .zIndex(isCinemaRowSeatField(element) ? 1700 : 1400)
                        .allowsHitTesting(element.id != selectedElementID?.wrappedValue)
                    }

                    // Template text stays locked by default. When unlocked, these larger
                    // hit areas make selected prompt labels editable even beside sliders.
                    ForEach(Array(page.elements.enumerated()).filter { isUnlockedTemplateText($0.element) }, id: \.element.id) { index, element in
                        let hitSize = unlockableTemplateHitSize(for: element, scaleX: scaleX, scaleY: scaleY)
                        Button {
                            beginEditingText(at: index)
                        } label: {
                            Color.clear.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(width: hitSize.width, height: hitSize.height)
                        .position(x: element.position.x * scaleX, y: element.position.y * scaleY)
                        .zIndex(1780)
                        .allowsHitTesting(element.id != selectedElementID?.wrappedValue)
                    }

                    ForEach(Array(page.elements.enumerated()).filter { isEditableWritingLine($0.element) }, id: \.element.id) { index, element in
                        let style = lineTextStyle(for: element)
                        let lineFrame = writingLineOverlayFrame(for: element)
                        EditableLineOverlay(
                            element: elementBinding(for: index),
                            page: page,
                            scaleX: scaleX,
                            scaleY: scaleY,
                            characterLimit: lineCharacterLimit(for: element),
                            fontName: style.fontName,
                            fontSize: style.fontSize,
                            isBold: style.isBold,
                            isFocused: focusedLineID == element.id,
                            allowsWrapping: lineWrappingAllowed(element),
                            maximumNumberOfLines: lineMaximumNumberOfLines(element),
                            lineHeight: editableLineTextLineHeight(for: element, styleFontSize: style.fontSize, scaleY: scaleY),
                            onFocus: {
                                selectedElementID?.wrappedValue = nil
                                focusedLineID = element.id
                            },
                            onDismiss: {
                                focusedLineID = nil
                            },
                            onOverflow: { overflow in
                                if lineAllowsOverflow(element) {
                                    moveOverflow(overflow, from: index)
                                }
                            }
                        )
                            .frame(width: lineFrame.size.width * scaleX, height: editableLineOverlayHeight(for: element, styleFontSize: style.fontSize, scaleY: scaleY))
                            .position(x: lineFrame.position.x * scaleX, y: lineFrame.position.y * scaleY)
                            .zIndex(1500)
                    }

                    // PenPalooza: the "a line about why →" labels sit on the left side of
                    // the printed line. This hit layer keeps the editable text starting
                    // after the arrow, but lets a tap anywhere on that printed line focus it.
                    ForEach(Array(page.elements.enumerated()).filter { isPlaylistFestivalWhyLine($0.element) }, id: \.element.id) { _, element in
                        Button {
                            selectedElementID?.wrappedValue = nil
                            focusedLineID = element.id
                        } label: {
                            Color.clear.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(width: element.size.width * scaleX, height: max(18, element.size.height * scaleY * 3.2))
                        .position(x: element.position.x * scaleX, y: element.position.y * scaleY)
                        .zIndex(1499)
                    }

                    // Highs/Lows columns are continuous writing areas, not separate one-line fields.
                    // The text wraps inside its own column and never flows into the opposite column.
                    ForEach(continuousColumnRootIndices(), id: \.self) { index in
                        if page.elements.indices.contains(index) {
                        let frame = continuousColumnRect(for: page.elements[index])
                        ContinuousColumnTextOverlay(
                            element: elementBinding(for: index),
                            page: page,
                            scaleX: scaleX,
                            scaleY: scaleY,
                            layout: continuousColumnLayout,
                            characterLimit: continuousColumnCharacterLimit(for: frame.size),
                            isFocused: focusedLineID == page.elements[index].id,
                            onFocus: {
                                selectedElementID?.wrappedValue = nil
                                focusedLineID = page.elements[index].id
                            },
                            onDismiss: {
                                focusedLineID = nil
                            }
                        )
                        .frame(width: frame.size.width * scaleX, height: frame.size.height * scaleY)
                        .position(x: frame.midX * scaleX, y: frame.midY * scaleY)
                        .zIndex(1550)
                        }
                    }

                    // People I love: the six "why I love them" rectangles are editable text boxes.
                    ForEach(Array(page.elements.enumerated()).filter { isAppreciationLoveTextBox($0.element) }, id: \.element.id) { index, element in
                        AppreciationTextBoxOverlay(
                            element: elementBinding(for: index),
                            page: page,
                            scaleX: scaleX,
                            scaleY: scaleY,
                            isFocused: focusedLineID == element.id,
                            onFocus: {
                                selectedElementID?.wrappedValue = nil
                                focusedLineID = element.id
                            },
                            onDismiss: {
                                focusedLineID = nil
                            }
                        )
                        .frame(width: element.size.width * scaleX, height: element.size.height * scaleY)
                        .position(x: element.position.x * scaleX, y: element.position.y * scaleY)
                        .zIndex(1560)
                    }

                    // Favourites: reusable text boxes such as WHY I LOVE IT and WHAT IT’S ABOUT.
                    ForEach(Array(page.elements.enumerated()).filter { isFavouritesEditableTextBox($0.element) }, id: \.element.id) { index, element in
                        AppreciationTextBoxOverlay(
                            element: elementBinding(for: index),
                            page: page,
                            scaleX: scaleX,
                            scaleY: scaleY,
                            isFocused: focusedLineID == element.id,
                            onFocus: {
                                selectedElementID?.wrappedValue = nil
                                focusedLineID = element.id
                            },
                            onDismiss: {
                                focusedLineID = nil
                            }
                        )
                        .frame(width: element.size.width * scaleX, height: element.size.height * scaleY)
                        .position(x: element.position.x * scaleX, y: element.position.y * scaleY)
                        .zIndex(1561)
                    }

                    if let selectedID = selectedElementID?.wrappedValue,
                       let selectedIndex = page.elements.firstIndex(where: { $0.id == selectedID }),
                       (page.elements[selectedIndex].type == .text || page.elements[selectedIndex].type == .title),
                       (isCanvasEditableText(page.elements[selectedIndex]) || page.elements[selectedIndex].isTextLocked) {
                        let element = page.elements[selectedIndex]
                        let editingFrame = editableTextFrame(for: element)
                        EditableTextOverlay(
                            element: elementBinding(for: selectedIndex),
                            page: page,
                            scaleX: scaleX,
                            scaleY: scaleY,
                            characterLimit: characterLimit(for: element),
                            visibleLineLimit: visibleLineLimit(for: element),
                            onDismiss: {
                                selectedElementID?.wrappedValue = nil
                            }
                        )
                        .frame(width: editingFrame.size.width * scaleX, height: editingFrame.size.height * scaleY)
                        .position(x: editingFrame.position.x * scaleX, y: editingFrame.position.y * scaleY)
                        .zIndex(1600)
                    }

                    // Photos are always the top interactive layer so decorative labels can never block photo gestures.
                    ForEach(Array(page.elements.enumerated()).filter { $0.element.type == .image }, id: \.element.id) { index, element in
                        PhotoUploadTapLayer(
                            element: elementBinding(for: index),
                            page: page,
                            scaleX: scaleX,
                            scaleY: scaleY,
                            selectedElementID: selectedElementID,
                            onInteraction: {
                                focusedLineID = nil
                            }
                        )
                            .frame(width: element.size.width * scaleX, height: element.size.height * scaleY)
                            .position(x: displayPosition(for: element).x * scaleX, y: displayPosition(for: element).y * scaleY)
                            .zIndex(2200)
                    }

                    // Streak calendar: tap the large day cells, not the tiny inner boxes.
                    if isStreakPage {
                        ForEach(Array(page.elements.enumerated()).filter { isStreakOuterCell($0.element) }, id: \.element.id) { index, element in
                            Button {
                                guard page.elements.indices.contains(index) else { return }
                                page.elements[index].isMarked.toggle()
                            } label: {
                                Color.clear.contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .frame(width: element.size.width * scaleX, height: element.size.height * scaleY)
                            .position(x: element.position.x * scaleX, y: element.position.y * scaleY)
                            .zIndex(1000)
                        }
                    }

                    // Generic small rating/check boxes throughout the magazine.
                    ForEach(Array(page.elements.enumerated()).filter { isFillableSmallBox($0.element) }, id: \.element.id) { index, element in
                        Button {
                            guard page.elements.indices.contains(index) else { return }
                            page.elements[index].isMarked.toggle()
                        } label: {
                            Color.clear.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(width: max(18, element.size.width * scaleX * 2.6), height: max(18, element.size.height * scaleY * 2.2))
                        .position(x: element.position.x * scaleX, y: element.position.y * scaleY)
                        .zIndex(1100)
                    }

                    // Hearts / star rating rows: tap position decides how many are filled.
                    ForEach(Array(page.elements.enumerated()).filter { isRatingText($0.element) }, id: \.element.id) { index, element in
                        RatingTapLayer(element: elementBinding(for: index), scaleX: scaleX, rowWidth: ratingRowWidth(for: element), textInset: element.textInset, textAlignment: element.textAlignment)
                            .frame(width: element.size.width * scaleX, height: max(14, element.size.height * scaleY * 1.15))
                            .position(x: element.position.x * scaleX, y: element.position.y * scaleY)
                            .zIndex(1300)
                    }

                    // YES / NO / MAYBE / NEVER / Y / N choices.
                    ForEach(Array(page.elements.enumerated()).filter { isChoiceText($0.element) }, id: \.element.id) { index, element in
                        Button {
                            selectChoice(at: index)
                        } label: {
                            Color.clear.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(width: choiceHitWidth(for: element, scaleX: scaleX), height: choiceHitHeight(for: element, scaleY: scaleY))
                        .position(x: element.position.x * scaleX, y: element.position.y * scaleY)
                        .zIndex(1120)
                    }

                    // Slidable progress bars.
                    ForEach(Array(page.elements.enumerated()).filter { isSliderBox($0.element) }, id: \.element.id) { index, element in
                        SliderTapLayer(element: elementBinding(for: index), scaleX: scaleX, scaleY: scaleY)
                            .frame(width: element.size.width * scaleX, height: max(34, element.size.height * scaleY * 5.0))
                            .position(x: element.position.x * scaleX, y: element.position.y * scaleY)
                            .zIndex(1090)
                    }
                }
            }
        }
        .onAppear {
            if editable {
                activeEditorSinglePageCanvasCount += 1
                print("SINGLE_PAGE_CANVAS_RENDER count", activeEditorSinglePageCanvasCount, "mode", "editor", "title", page.title, "elements", page.elements.count)
                if activeEditorSinglePageCanvasCount > 1 {
                    print("WARNING_MULTIPLE_EDITOR_CANVASES", activeEditorSinglePageCanvasCount)
                }
            } else {
                print("SINGLE_PAGE_CANVAS_RENDER mode", "static", "title", page.title, "elements", page.elements.count)
            }
        }
        .onDisappear {
            if editable {
                activeEditorSinglePageCanvasCount = max(0, activeEditorSinglePageCanvasCount - 1)
            }
        }
        .onChange(of: focusResetID) { _, _ in
            focusedLineID = nil
        }
    }


    private func elementBinding(for index: Int) -> Binding<MagazineElement> {
        Binding(
            get: {
                guard page.elements.indices.contains(index) else { return emptyMagazineElement }
                return page.elements[index]
            },
            set: { element in
                guard page.elements.indices.contains(index) else { return }
                page.elements[index] = element
            }
        )
    }

    private var continuousColumnLayout: ContinuousColumnTextLayout {
        continuousColumnTextLayout(for: page.title)
    }

    private func isUnlockedTemplateText(_ element: MagazineElement) -> Bool {
        templateTextUnlocked && isUnlockableTemplateText(element, page: page)
    }

    private func isCanvasEditableText(_ element: MagazineElement) -> Bool {
        element.isEditableText || isUnlockedTemplateText(element)
    }

    private func isStandaloneEditableText(_ element: MagazineElement) -> Bool {
        guard (element.type == .text || element.type == .title), element.isEditableText else { return false }
        if isCinemaRowSeatField(element) { return true }
        if isCinemaWatchLogDateField(element) { return true }
        if isTravelItineraryFromToField(element) { return true }
        if enclosingEditableBox(for: element) != nil { return false }
        let trimmed = templateLogicText(element.text).lowercased()
        return trimmed.contains("__ / __ / __")
            || trimmed == "___"
            || trimmed.contains("one word")
            || trimmed == "no. ___"
            || trimmed.hasPrefix("date")
    }

    private func isCinemaRowSeatField(_ element: MagazineElement) -> Bool {
        guard page.title == "CINEMA · TICKET STUB", element.type == .text, element.isEditableText else { return false }
        return abs(element.position.y - 137.0) < 2
            && (abs(element.position.x - 117.2) < 5 || abs(element.position.x - 144.8) < 5)
    }

    private func isCinemaHighlightsOneLineBox(_ element: MagazineElement) -> Bool {
        page.title == "CINEMA · HIGHLIGHTS"
            && element.type == .box
            && abs(element.position.x - 117.14) < 2
            && (abs(element.position.y - 139.7) < 2 || abs(element.position.y - 226.47) < 2)
    }

    private func isCinemaHighlightsOneLinePrompt(_ element: MagazineElement) -> Bool {
        guard page.title == "CINEMA · HIGHLIGHTS", element.type == .text, element.isEditableText else { return false }
        // Keep these editable even after the placeholder is cleared.
        return abs(element.position.x - 117.14) < 2
            && (abs(element.position.y - 139.7) < 2 || abs(element.position.y - 226.47) < 2)
    }

    private var isStreakPage: Bool {
        page.elements.contains { templateLogicText($0.text) == "Streak." }
    }

    private var coverHasUploadedPhoto: Bool {
        page.sectionTitle == "Cover" && page.elements.contains { $0.type == .image && $0.image != nil }
    }

    private func baseElementZIndex(for element: MagazineElement) -> Double {
        if element.type == .image, element.image != nil {
            return 700
        }

        return 0
    }

    private func editableTextIndex(in box: MagazineElement) -> Int? {
        guard box.type == .box, box.size.width > 18, box.size.height > 10 else { return nil }
        let candidates = page.elements.indices.filter { index in
            let element = page.elements[index]
            return (element.type == .text || element.type == .title)
                && !isCinemaRowSeatField(element)
                && (element.isEditableText || isEditableBoxPrompt(element))
                && !isStaticPromptLabel(element)
                && abs(element.position.x - box.position.x) <= box.size.width / 2
                && abs(element.position.y - box.position.y) <= box.size.height / 2
        }
        return candidates.first {
            templateLogicText(page.elements[$0].text).lowercased().contains("write here")
        } ?? candidates.first
    }

    private func beginEditingText(at index: Int) {
        guard page.elements.indices.contains(index), isCanvasEditableText(page.elements[index]) else { return }
        let isTemplateLabel = isUnlockedTemplateText(page.elements[index])
        if isTemplateLabel {
            page.elements[index].isTextLocked = true
        }
        if isEditableBoxPrompt(page.elements[index]) {
            page.elements[index].isEditableText = true
            page.elements[index].verticalAlignment = .top
            page.elements[index].textAlignment = .left
        }
        if !isTemplateLabel && !shouldPreserveOriginalEditableStyle(page.elements[index]) {
            applyEditableStyle(at: index)
        }
        if !isTemplateLabel, isEditablePlaceholder(page.elements[index].text), !isScoreText(page.elements[index]), !isCinemaWatchLogDateField(page.elements[index]) {
            page.elements[index].text = ""
        }
        focusedLineID = nil
        selectedElementID?.wrappedValue = page.elements[index].id
    }

    private func applyEditableStyle(at index: Int) {
        guard page.elements.indices.contains(index), isCanvasEditableText(page.elements[index]) else { return }
        // Keep user-entered text consistent before, during and after editing.
        // Do not inherit the larger Georgia prompt style, because that makes saved text jump larger.
        if isCinemaWatchLogDateField(page.elements[index]) {
            page.elements[index].fontName = "Helvetica"
            page.elements[index].fontSize = 6.04
        } else {
            page.elements[index].fontName = "Georgia"
            page.elements[index].fontSize = editableBodyFontSize(for: page.elements[index])
        }
        page.elements[index].isBold = false
    }

    private func editableBodyFontSize(for element: MagazineElement) -> CGFloat {
        if isScoreText(element) { return element.fontSize }
        if isCinemaWatchLogDateField(element) { return 6.04 }
        if page.title == "MONTHLY RESET · LETTER" && templateLogicText(element.text).lowercased().contains("your name") { return element.fontSize }
        if page.title == "TINY WINS · TROPHY CABINET" { return 4.55 }
        if page.title == "TINY WINS · THE DAILY ME", enclosingEditableBox(for: element) != nil { return 6.4 }
        if page.title == "TINY WINS · WIN OF THE MONTH", enclosingEditableBox(for: element) != nil { return 8.2 }
        if page.title == "HOBBIES · A NEW TRY", enclosingEditableBox(for: element) != nil { return 6.55 }
        if page.title == "MONTHLY RESET · DAILY REFLECTI", enclosingEditableBox(for: element) != nil { return 7.2 }
        if page.elements.contains(where: { templateLogicText($0.text) == "How I grew." }) { return 4.3 }
        if enclosingEditableBox(for: element) != nil { return 5.04 }
        return min(element.fontSize, 5.04)
    }

    private func shouldPreserveOriginalEditableStyle(_ element: MagazineElement) -> Bool {
        let trimmed = templateLogicText(element.text).lowercased()
        return isScoreText(element)
            || isAffirmationsWordField(element)
            || isCinemaRowSeatField(element)
            || isCinemaWatchLogDateField(element)
            || isTravelItineraryFromToField(element)
            || trimmed.contains("one word")
            || trimmed.contains("__ / __ / __")
            || trimmed.contains("date")
            || trimmed == "no. ___"
            || trimmed.hasPrefix("date")
    }

    private func nearestPromptStyleAbove(_ element: MagazineElement) -> MagazineElement? {
        page.elements
            .filter { candidate in
                candidate.type == .text
                    && !candidate.isEditableText
                    && candidate.position.y < element.position.y
                    && element.position.y - candidate.position.y < 16
                    && abs(candidate.position.x - element.position.x) < max(8, element.size.width * 0.25)
                    && candidate.text.rangeOfCharacter(from: .letters) != nil
                    && candidate.text != candidate.text.uppercased()
            }
            .min { abs($0.position.y - element.position.y) < abs($1.position.y - element.position.y) }
    }

    private func isEditablePlaceholder(_ text: String) -> Bool {
        let normalized = templateLogicText(text).lowercased()
        return normalized == "write here..."
            || normalized == "write here…"
            || normalized == "__/__"
            || normalized == "__ / __ / __"
            || normalized == "write one word here"
            || normalized == "one word"
            || normalized == "write your word"
            || normalized == "a few lines from you..."
            || normalized == "a few lines from you…"
            || normalized.contains("___")
    }

    private func isEditableBoxPrompt(_ element: MagazineElement) -> Bool {
        let normalized = templateLogicText(element.text).lowercased()
        return normalized == "a few lines from you..."
            || normalized == "a few lines from you…"
            || normalized == "in one sentence..."
            || normalized == "in one sentence…"
    }

    private func isScoreText(_ element: MagazineElement) -> Bool {
        element.text.trimmingCharacters(in: .whitespacesAndNewlines).contains("/ 10")
            || element.text.trimmingCharacters(in: .whitespacesAndNewlines).contains("/10")
    }

    private func editableTextFrame(for element: MagazineElement) -> (position: CGPoint, size: CGSize) {
        if isCinemaRowSeatField(element) {
            return (CGPoint(x: element.position.x, y: element.position.y + 1.0), CGSize(width: element.size.width, height: 8.4))
        }
        if isTravelItineraryFromToField(element) {
            return (CGPoint(x: element.position.x, y: element.position.y - 0.7), CGSize(width: element.size.width, height: 8.2))
        }
        guard let box = enclosingEditableBox(for: element) else {
            return (element.position, element.size)
        }
        return (box.position, box.size)
    }

    private func displayUsesEditableBox(_ element: MagazineElement) -> Bool {
        element.isEditableText && !isCinemaRowSeatField(element) && enclosingEditableBox(for: element) != nil
    }

    private func standaloneEditableHitSize(for element: MagazineElement, scaleX: CGFloat, scaleY: CGFloat) -> CGSize {
        if isCinemaRowSeatField(element) {
            return CGSize(width: max(36, element.size.width * scaleX * 3.0), height: max(22, element.size.height * scaleY * 2.6))
        }
        if isTravelItineraryFromToField(element) {
            return CGSize(width: max(44, element.size.width * scaleX * 1.3), height: max(22, element.size.height * scaleY * 3.0))
        }
        return CGSize(width: max(28, element.size.width * scaleX * 1.4), height: max(18, element.size.height * scaleY * 2.2))
    }

    private func unlockableTemplateHitSize(for element: MagazineElement, scaleX: CGFloat, scaleY: CGFloat) -> CGSize {
        if isSectionCoverDescription(element, page: page) {
            return CGSize(
                width: max(80, element.size.width * scaleX),
                height: max(44, element.size.height * scaleY * 1.25)
            )
        }

        return CGSize(
            width: max(54, element.size.width * scaleX * 1.85),
            height: max(28, element.size.height * scaleY * 3.0)
        )
    }

    private func unlockableTemplateHighlightSize(for element: MagazineElement, scaleX: CGFloat, scaleY: CGFloat) -> CGSize {
        if isSectionCoverDescription(element, page: page) {
            return CGSize(
                width: max(80, element.size.width * scaleX),
                height: max(30, element.size.height * scaleY)
            )
        }

        return CGSize(
            width: max(34, element.size.width * scaleX * 1.12),
            height: max(16, element.size.height * scaleY * 1.55)
        )
    }

    private func enclosingEditableBox(for element: MagazineElement) -> MagazineElement? {
        page.elements
            .filter { box in
                box.type == .box
                    && box.size.width > element.size.width * 0.65
                    && box.size.height > element.size.height
                    && abs(element.position.x - box.position.x) <= box.size.width / 2
                    && abs(element.position.y - box.position.y) <= box.size.height / 2
            }
            .min { $0.size.width * $0.size.height < $1.size.width * $1.size.height }
    }

    private func characterLimit(for element: MagazineElement) -> Int {
        if let limit = templateTextCharacterLimit(for: element, page: page) { return limit }
        if isCinemaRowSeatField(element) { return 4 }
        if isCinemaTicketShortField(element) { return 4 }
        if isCinemaWatchLogDateField(element) { return 8 }
        if isAffirmationsWordField(element) { return 24 }
        let availableSize = enclosingEditableBox(for: element)?.size ?? element.size
        let fontSize = editableBodyFontSize(for: element)
        let averageCharacterWidth = max(0.86, fontSize * 0.30)
        let lineHeight = max(3.1, fontSize * 1.02)
        let charactersPerLine = max(1, Int((availableSize.width - element.textInset.width * 2) / averageCharacterWidth))
        let lineCount = max(1, Int((availableSize.height - element.textInset.height * 2) / lineHeight))
        let baseLimit = max(1, charactersPerLine * lineCount)
        if page.title == "MONTHLY RESET · LOOKING BACK" { return baseLimit + 18 }
        return baseLimit
    }

    private func visibleLineLimit(for element: MagazineElement) -> Int {
        let availableSize = enclosingEditableBox(for: element)?.size ?? element.size
        let fontSize = element.type == .title ? element.fontSize * 0.56 : editableBodyFontSize(for: element)
        let contentHeight = max(1, availableSize.height - (element.textInset.height * 2))
        return max(1, Int(contentHeight / max(1, fontSize * 1.18)))
    }

    private func isEndMonthDateMoodFeelingLine(_ line: MagazineElement) -> Bool {
        guard page.title == "MONTHLY RESET · DAILY REFLECTI", line.type == .line else { return false }
        return abs(line.position.y - 80.2) < 1.2
            && (abs(line.position.x - 37.09) < 2 || abs(line.position.x - 38.64) < 2 || abs(line.position.x - 108.0) < 2)
    }

    private func isDearMonthLoveLine(_ line: MagazineElement) -> Bool {
        guard page.title == "MONTHLY RESET · LETTER", line.type == .line else { return false }
        return abs(line.position.y - 233.71) < 1.5 && line.size.width > 60
    }

    private func isHowIGrewNoteLine(_ line: MagazineElement) -> Bool {
        guard page.title == "MONTHLY RESET · GROW TRACKER", line.type == .line else { return false }
        return (abs(line.position.x - 47.2) < 2 || abs(line.position.x - 122.8) < 2)
            && (abs(line.position.y - 134.0) < 1.8 || abs(line.position.y - 142.5) < 1.8 || abs(line.position.y - 215.0) < 1.8 || abs(line.position.y - 223.5) < 1.8)
    }

    private func isGratitudeListLine(_ line: MagazineElement) -> Bool {
        guard page.title == "MONTHLY RESET · GRATITUDE", line.type == .line else { return false }
        guard line.size.width >= 50, line.size.width <= 70 else { return false }
        let headerUnderlineYs: [CGFloat] = [79.41, 163.24]
        guard !headerUnderlineYs.contains(where: { abs(line.position.y - $0) < 1.4 }) else { return false }
        return line.position.y > 85 && line.position.y < 222
    }

    private func isEditableWritingLine(_ element: MagazineElement) -> Bool {
        // Food table title line sits above y=70, so allow it before the general writing-line guard.
        if isFoodTableForNumberLine(element) { return true }
        if isPlaylistMusicWritingLine(element) { return true }
        guard element.type == .line, element.position.y > 70, element.position.y < 235 else { return false }
        if isRankingOccupationOrAgeLine(element) { return true }
        if isEndMonthDateMoodFeelingLine(element) { return true }
        if isDearMonthLoveLine(element) { return true }
        if isHowIGrewNoteLine(element) { return true }
        if isGratitudeListLine(element) { return true }
        if isHobbyTrackerNameLine(element) { return true }
        if isNewHobbyNameLine(element) { return true }
        if isCrushDiaryWritingLine(element) { return true }
        if isPlaylistMusicWritingLine(element) { return true }
        if isCinemaTicketWritingLine(element) { return true }
        if isCinemaWatchLogTitleLine(element) { return true }
        if isCinemaWatchLogDateLine(element) { return true }
        if isCinemaWatchLogDateLine(element) { return true }
        if isCinemaHighlightsWritingLine(element) { return true }
        if isSceneTitleWritingLine(element) { return true }
        if isReadingWritingLine(element) { return true }
        if isFoodRecipeWritingLine(element) { return true }
        if isTravelWritingLine(element) { return true }
        if isFavouritesWritingLine(element) { return true }
        if isAffirmationsWritingLine(element) { return true }
        if isPeopleLoveNameLine(element) { return true }
        guard element.size.width >= 20, element.size.width <= 130 else { return false }
        if isTrophyCabinetWritingLine(element) { return false }
        if isDateReviewInfoLine(element) { return true }
        if isCrushDiaryWritingLine(element) { return true }
        if isPeopleLoveNameLine(element) { return true }
        if isPeopleLoveHowWeMetLine(element) { return true }
        if isInLoveWithLifeLine(element) { return true }
        if isInLoveSignatureLine(element) { return true }
        if isRankingOccupationOrAgeLine(element) { return true }
        if hasNamePromptAbove(element) { return true }
        if hasAllCapsHeaderDirectlyAbove(element) { return false }
        return isNoteWritingLine(element)
            || hasHelperTextBelow(element)
            || hasBulletPromptBeside(element)
            || hasNumberPromptBeside(element)
    }

    private func writingLineOverlayFrame(for line: MagazineElement) -> (position: CGPoint, size: CGSize) {
        if isSceneTitleWritingLine(line) {
            return (CGPoint(x: line.position.x, y: line.position.y - 2.4), line.size)
        }
        if isHobbyTrackerNameLine(line) {
            return (CGPoint(x: line.position.x, y: line.position.y - 1.8), line.size)
        }
        if isNewHobbyNameLine(line) {
            return (CGPoint(x: line.position.x, y: line.position.y - 1.1), line.size)
        }
        if isEndMonthDateMoodFeelingLine(line) {
            return (CGPoint(x: line.position.x, y: line.position.y - 1.0), line.size)
        }
        if isGratitudeListLine(line) {
            return (CGPoint(x: line.position.x, y: line.position.y - 1.7), line.size)
        }
        if isHowIGrewNoteLine(line) {
            return (CGPoint(x: line.position.x, y: line.position.y - 1.3), line.size)
        }
        if isDearMonthLoveLine(line) {
            return (CGPoint(x: line.position.x, y: line.position.y - 1.2), line.size)
        }
        if isDateReviewInfoLine(line) {
            return (CGPoint(x: line.position.x, y: line.position.y - 1.4), line.size)
        }
        if isRankingOccupationOrAgeLine(line) {
            return (CGPoint(x: line.position.x, y: line.position.y - 1.35), line.size)
        }
        if isPeopleLoveNameLine(line) {
            return (CGPoint(x: line.position.x, y: line.position.y - 1.6), line.size)
        }
        if isInLoveSignatureLine(line) {
            return (CGPoint(x: line.position.x, y: line.position.y - 1.4), line.size)
        }
        if isCrushDiaryNameLine(line) {
            return (CGPoint(x: line.position.x, y: line.position.y - 0.4), line.size)
        }
        if isPlaylistFestivalWhyLine(line) {
            let left = line.position.x - line.size.width / 2
            let right = line.position.x + line.size.width / 2
            let isFirstPrintedLine = [105.0, 166.0, 227.0].contains { abs(line.position.y - $0) < 1.4 }
            let inputLeft = isFirstPrintedLine ? left + 42.0 : left
            let inputWidth = max(20, right - inputLeft)
            // Start after “a line about why →” on the first line; overflow continues on the next printed line.
            return (CGPoint(x: inputLeft + inputWidth / 2, y: line.position.y - 2.4), CGSize(width: inputWidth, height: line.size.height))
        }
        if isPlaylistMusicWritingLine(line) {
            return (CGPoint(x: line.position.x, y: line.position.y - 2.4), line.size)
        }
        if isCinemaTicketWritingLine(line) {
            return cinemaTicketOverlayFrame(for: line)
        }
        if isCinemaHighlightsWritingLine(line) {
            return (CGPoint(x: line.position.x, y: line.position.y - 2.0), line.size)
        }
        if isCinemaWatchLogTitleLine(line) {
            return (CGPoint(x: line.position.x, y: line.position.y - 2.1), line.size)
        }
        if isCinemaWatchLogDateLine(line) {
            return (CGPoint(x: line.position.x, y: line.position.y - 2.1), line.size)
        }
        if isReadingTBRWritingLine(line) {
            return (CGPoint(x: line.position.x, y: line.position.y - 0.9), line.size)
        }
        if isReadingWritingLine(line) {
            return (CGPoint(x: line.position.x, y: line.position.y - 1.8), line.size)
        }
        if isFavouritesWritingLine(line) {
            return (CGPoint(x: line.position.x, y: line.position.y - 1.4), line.size)
        }
        if isTravelPostcardAddressLine(line) {
            return (CGPoint(x: line.position.x, y: line.position.y - 1.4), line.size)
        }
        if isTravelItineraryFirstDayLine(line) {
            // One editable two-line block per day. Keep both written rows above the two printed lines.
            return (CGPoint(x: line.position.x, y: line.position.y - 1.2), line.size)
        }
        if isTravelPlacesTwoLine(line) {
            // Place / memory cells use two written rows above the visible line.
            return (CGPoint(x: line.position.x, y: line.position.y - 5.0), line.size)
        }
        if isTravelItineraryDayLine(line) {
            return (line.position, line.size)
        }
        if isTwoLineFoodLine(line) {
            return (CGPoint(x: line.position.x, y: line.position.y - 4.0), line.size)
        }
        if isFoodTableForNumberLine(line) {
            return (CGPoint(x: line.position.x + 2.2, y: line.position.y - 3.0), line.size)
        }
        if page.title == "FOOD & RECIPES · TABLE FOR ONE", isFoodRecipeWritingLine(line) {
            return (CGPoint(x: line.position.x, y: line.position.y - 1.5), line.size)
        }
        return (line.position, line.size)
    }

    private func hasHelperTextBelow(_ line: MagazineElement) -> Bool {
        page.elements.contains { element in
            guard element.type == .text else { return false }
            let dy = element.position.y - line.position.y
            return dy > 1.5
                && dy < 4.5
                && abs(element.position.x - line.position.x) < max(4, line.size.width * 0.2)
                && element.size.width <= line.size.width + 8
                && element.fontSize <= 5.2
        }
    }

    private func hasNamePromptAbove(_ line: MagazineElement) -> Bool {
        page.elements.contains { element in
            guard element.type == .text else { return false }
            let trimmed = templateLogicText(element.text).lowercased()
            let dy = line.position.y - element.position.y
            return (trimmed == "name" || trimmed == "name →" || trimmed == "name ->")
                && dy > 1.0
                && dy < 10.0
                && abs(element.position.x - line.position.x) < max(8, line.size.width * 0.45)
                && element.fontSize <= 5.2
        }
    }

    private func isHobbyTrackerNameLine(_ line: MagazineElement) -> Bool {
        guard page.title == "HOBBIES · TRACKER", line.type == .line else { return false }
        let isNameGuide = abs(line.position.x - 85.0) < 2
            && [84.0, 120.5, 157.0, 193.5].contains { abs(line.position.y - $0) < 1.2 }
        return isNameGuide || (hasHelperTextBelow(line) && line.size.width > 80 && line.position.y > 70 && line.position.y < 220)
    }

    private func isNewHobbyNameLine(_ line: MagazineElement) -> Bool {
        guard page.title == "HOBBIES · A NEW TRY" else { return false }
        let isTemplateNameLine = abs(line.position.x - 124.41) < 2
            && abs(line.position.y - 88.0) < 1.4
            && line.size.width > 60
        return isTemplateNameLine || (hasNamePromptAbove(line) && line.size.width > 45 && line.position.y > 80 && line.position.y < 115)
    }

    private func hasSideLabelBeside(_ line: MagazineElement, labels: Set<String>) -> Bool {
        page.elements.contains { element in
            guard element.type == .text else { return false }
            let trimmed = templateLogicText(element.text).uppercased()
            guard labels.contains(trimmed) else { return false }
            return abs(element.position.y - line.position.y) < 9.5
                && element.position.x < line.position.x
                && line.position.x - element.position.x < max(80, line.size.width * 0.8)
        }
    }

    private func isDateReviewInfoLine(_ line: MagazineElement) -> Bool {
        guard page.title == "RELATIONSHIPS · DATE REVIEW", line.type == .line else { return false }
        // The WITH / WHERE / WHEN writing lines are the three long lines beside those labels.
        // Use their template geometry directly so the editable layer is always present.
        return line.size.width > 100
            && abs(line.position.x - 94.28) < 3
            && line.position.y >= 76
            && line.position.y <= 99
    }

    private func isCrushDiaryWritingLine(_ line: MagazineElement) -> Bool {
        guard page.title == "RELATIONSHIPS · NEWEST OBSESSI", line.type == .line else { return false }
        let y = line.position.y
        let isNameLine = abs(y - 80.0) < 1.8 || abs(y - 81.4) < 1.8
        let isFirstNoticedLine = abs(y - 115.5) < 1.8 || abs(y - 131.2) < 1.8
        let isHotLine = abs(y - 166.7) < 1.8 || abs(y - 182.4) < 1.8
        let isKnownLine = abs(y - 213.8) < 1.8 || abs(y - 229.5) < 1.8
        return isNameLine || isFirstNoticedLine || isHotLine || isKnownLine
    }

    private func isCrushDiaryNameLine(_ line: MagazineElement) -> Bool {
        isCrushDiaryWritingLine(line) && (abs(line.position.y - 80.0) < 1.8 || abs(line.position.y - 81.4) < 1.8)
    }

    private func isCrushDiaryFirstNoticedLine(_ line: MagazineElement) -> Bool {
        isCrushDiaryWritingLine(line) && (abs(line.position.y - 115.5) < 1.8 || abs(line.position.y - 131.2) < 1.8)
    }

    private func isCrushDiaryHotLine(_ line: MagazineElement) -> Bool {
        isCrushDiaryWritingLine(line) && (abs(line.position.y - 166.7) < 1.8 || abs(line.position.y - 182.4) < 1.8)
    }

    private func isCrushDiaryKnownLine(_ line: MagazineElement) -> Bool {
        isCrushDiaryWritingLine(line) && (abs(line.position.y - 213.8) < 1.8 || abs(line.position.y - 229.5) < 1.8)
    }

    private func isStaticPromptLabel(_ element: MagazineElement) -> Bool {
        let trimmed = templateLogicText(element.text).uppercased()
        return (page.title == "RELATIONSHIPS · APPRECIATION" && trimmed == "THEIR NAME")
            || (page.title == "RELATIONSHIPS · PEOPLE I LOVE" && trimmed == "NAME")
    }

    private func isPeopleLoveNameLine(_ line: MagazineElement) -> Bool {
        if page.title == "RELATIONSHIPS · PEOPLE I LOVE", line.type == .line {
            let isTemplateNameLine = abs(line.position.x - 59.0) < 2
                && line.size.width > 75
                && [91.0, 175.0].contains { abs(line.position.y - $0) < 1.4 }
            let isBelowNameLabel = page.elements.contains { element in
                guard element.type == .text else { return false }
                let dy = line.position.y - element.position.y
                return templateLogicText(element.text).uppercased() == "NAME"
                    && dy > 6.0
                    && dy < 12.0
                    && abs(element.position.x - line.position.x) < 3
            }
            return isTemplateNameLine || isBelowNameLabel
        }
        guard page.title == "RELATIONSHIPS · APPRECIATION" else { return false }
        return page.elements.contains { element in
            guard element.type == .text else { return false }
            let trimmed = templateLogicText(element.text).uppercased()
            let dy = line.position.y - element.position.y
            return trimmed == "THEIR NAME"
                && dy > 5.0
                && dy < 10.5
                && abs(element.position.x - line.position.x) < 4
        }
    }

    private func isPeopleLoveHowWeMetLine(_ line: MagazineElement) -> Bool {
        guard page.title == "RELATIONSHIPS · PEOPLE I LOVE", line.type == .line else { return false }
        let inColumn = abs(line.position.x - 46.36) < 3 || abs(line.position.x - 123.64) < 3
        let isTopCardLine = abs(line.position.y - 135.82) < 1.5 || abs(line.position.y - 145.15) < 1.5
        let isBottomCardLine = abs(line.position.y - 218.46) < 1.5 || abs(line.position.y - 229.02) < 1.5
        return inColumn && (isTopCardLine || isBottomCardLine)
    }

    private func isAppreciationLoveTextBox(_ element: MagazineElement) -> Bool {
        guard page.title == "RELATIONSHIPS · APPRECIATION", element.type == .box else { return false }
        return element.size.width > 55
            && element.size.height > 20
            && element.position.y > 90
            && element.position.y < 225
    }

    private func isInLoveWithLifeLine(_ line: MagazineElement) -> Bool {
        guard page.title == "RELATIONSHIPS · IN LOVE WITH L" else { return false }
        return line.position.y >= 108
            && line.position.y <= 166
            && line.size.width > 60
    }

    private func isInLoveSignatureLine(_ line: MagazineElement) -> Bool {
        guard page.title == "RELATIONSHIPS · IN LOVE WITH L" else { return false }
        return abs(line.position.x - 130.89) < 2
            && abs(line.position.y - 184.0) < 3
    }

    private func isRankingOccupationOrAgeLine(_ line: MagazineElement) -> Bool {
        guard page.title == "RELATIONSHIPS · THE RANKING", line.type == .line else { return false }
        let isNameOrOccupation = abs(line.position.x - 96.0) < 2
            && line.size.width > 50
            && [108.0, 127.0, 184.0, 203.0].contains { abs(line.position.y - $0) < 1.4 }
        let isAge = abs(line.position.x - 143.0) < 2
            && line.size.width > 10
            && line.size.width < 25
            && [127.0, 203.0].contains { abs(line.position.y - $0) < 1.4 }
        return isNameOrOccupation || isAge
    }

    private func isPlaylistMusicWritingLine(_ line: MagazineElement) -> Bool {
        guard line.type == .line else { return false }

        switch page.title {
        case "PLAYLIST & MUSIC · WRAPPED":
            // Top artist/song/mood lines and one combined Top 5 line per row.
            let isTopSummary = abs(line.position.x - 117.14) < 3
                && line.size.width > 70
                && [93.0, 112.0, 131.0].contains { abs(line.position.y - $0) < 1.4 }
            let isCombinedSongArtist = abs(line.position.x - 93.5) < 3
                && line.size.width > 120
                && [156.4, 177.4, 198.4, 219.4].contains { abs(line.position.y - $0) < 1.4 }
            return isTopSummary || isCombinedSongArtist

        case "PLAYLIST & MUSIC · FESTIVAL":
            // Each festival entry has two editable lines: artist/song and why.
            return abs(line.position.x - 85.0) < 3
                && line.size.width > 135
                && [84.5, 105.0, 114.0, 145.5, 166.0, 175.0, 206.5, 227.0, 236.0].contains { abs(line.position.y - $0) < 1.4 }

        case "PLAYLIST & MUSIC · LINER NOTES":
            // Album, artist, year, genre, and favourite track. The large text box is already editable separately.
            let isAlbumInfo = (abs(line.position.x - 124.41) < 3 && line.size.width > 60 && [88.2, 102.8].contains { abs(line.position.y - $0) < 1.4 })
                || (abs(line.position.x - 107.02) < 3 && line.size.width > 25 && abs(line.position.y - 119.2) < 1.4)
                || (abs(line.position.x - 141.79) < 3 && line.size.width > 25 && abs(line.position.y - 119.2) < 1.4)
            let isFavouriteTrack = abs(line.position.x - 85.0) < 3
                && line.size.width > 135
                && abs(line.position.y - 218.0) < 1.4
            return isAlbumInfo || isFavouriteTrack

        case "PLAYLIST & MUSIC · MIXTAPE":
            // Artist, song and feeling lines beside each cover. Exclude the little cover-image bottom lines.
            return (abs(line.position.x - 103.0) < 4 || abs(line.position.x - 99.5) < 4)
                && line.size.width > 95
                && [101.0, 102.3, 115.0, 116.3, 154.0, 155.3, 168.0, 169.3, 207.0, 208.3, 221.0, 222.3].contains { abs(line.position.y - $0) < 1.4 }

        default:
            return false
        }
    }



    private func isPlaylistFestivalWhyLine(_ line: MagazineElement) -> Bool {
        guard page.title == "PLAYLIST & MUSIC · FESTIVAL", line.type == .line else { return false }
        return abs(line.position.x - 85.0) < 3
            && line.size.width > 135
            && [105.0, 114.0, 166.0, 175.0, 227.0, 236.0].contains { abs(line.position.y - $0) < 1.4 }
    }

    private func isCinemaTicketWritingLine(_ line: MagazineElement) -> Bool {
        guard page.title == "CINEMA · TICKET STUB", line.type == .line else { return false }
        let isMovieTitle = abs(line.position.x - 85.0) < 3 && line.size.width > 120 && abs(line.position.y - 108.0) < 1.4
        let isDirectedBy = abs(line.position.x - 85.0) < 3 && line.size.width > 120 && abs(line.position.y - 126.0) < 1.4
        return isMovieTitle || isDirectedBy
    }

    private func cinemaTicketOverlayFrame(for line: MagazineElement) -> (position: CGPoint, size: CGSize) {
        return (CGPoint(x: line.position.x, y: line.position.y - 2.0), line.size)
    }

    private func isCinemaTicketShortField(_ element: MagazineElement) -> Bool {
        guard page.title == "CINEMA · TICKET STUB", element.type == .text, element.isEditableText else { return false }
        return abs(element.position.y - 137.0) < 2
            && (abs(element.position.x - 117.2) < 5 || abs(element.position.x - 144.8) < 5)
    }

    private func isCinemaWatchLogDateField(_ element: MagazineElement) -> Bool {
        // Watch-log date inputs should behave like normal writing lines, not special standalone fields.
        return false
    }

    private func isCinemaWatchLogTitleLine(_ line: MagazineElement) -> Bool {
        guard page.title == "CINEMA · WATCH LOG", line.type == .line else { return false }
        return abs(line.position.x - 78.0) < 2
            && abs(line.size.width - 72.0) < 2
            && line.position.y >= 86
            && line.position.y <= 220.5
    }

    private func isCinemaWatchLogDateLine(_ line: MagazineElement) -> Bool {
        guard page.title == "CINEMA · WATCH LOG", line.type == .line else { return false }
        return abs(line.position.x - 25.0) < 2
            && abs(line.size.width - 18.0) < 2
            && line.position.y >= 86
            && line.position.y <= 220.5
    }

    private func isCinemaHighlightsWritingLine(_ line: MagazineElement) -> Bool {
        guard page.title == "CINEMA · HIGHLIGHTS", line.type == .line else { return false }
        let isTitleOrDirector = abs(line.position.x - 117.14) < 2
            && abs(line.size.width - 80.98) < 2
            && [92.06, 178.82].contains { abs(line.position.y - $0) < 1.4 }
        let isYearOrRuntime = (abs(line.position.x - 96.12) < 2 || abs(line.position.x - 138.16) < 2)
            && abs(line.size.width - 38.95) < 2
            && [112.06, 198.82].contains { abs(line.position.y - $0) < 1.4 }
        return isTitleOrDirector || isYearOrRuntime
    }

    private func isReadingWritingLine(_ line: MagazineElement) -> Bool {
        guard line.type == .line else { return false }

        switch page.title {
        case "READING · BOOKPLATE":
            // title and author
            return abs(line.position.x - 85.0) < 2
                && line.size.width > 100
                && [123.0, 145.0].contains { abs(line.position.y - $0) < 1.4 }

        case "READING · MARGIN NOTES":
            // Book of the Month: title, author, genre
            return abs(line.position.x - 117.14) < 2
                && line.size.width > 75
                && [88.0, 106.0, 124.0].contains { abs(line.position.y - $0) < 1.4 }

        case "READING · MINI REVIEWS":
            // Three mini-review cards: title line, author line, genre line
            let isTitle = abs(line.position.x - 108.19) < 2
                && line.size.width > 90
                && [81.76, 136.18, 190.59].contains { abs(line.position.y - $0) < 1.4 }
            let isAuthor = abs(line.position.x - 82.69) < 2
                && line.size.width > 40
                && [97.94, 152.35, 206.76].contains { abs(line.position.y - $0) < 1.4 }
            let isGenre = abs(line.position.x - 133.69) < 2
                && line.size.width > 40
                && [97.94, 152.35, 206.76].contains { abs(line.position.y - $0) < 1.4 }
            return isTitle || isAuthor || isGenre

        case "READING · TBR STACK":
            return abs(line.position.x - 108.0) < 3
                && line.size.width > 70
                && [101.0, 119.0, 153.0, 171.0, 205.0, 223.0].contains { abs(line.position.y - $0) < 1.8 }

        default:
            return false
        }
    }

    private func isReadingTBRWritingLine(_ line: MagazineElement) -> Bool {
        guard page.title == "READING · TBR STACK", line.type == .line else { return false }
        return abs(line.position.x - 108.0) < 3
            && line.size.width > 70
            && [101.0, 119.0, 153.0, 171.0, 205.0, 223.0].contains { abs(line.position.y - $0) < 1.8 }
    }



    private func isTravelItineraryFromToField(_ element: MagazineElement) -> Bool {
        guard page.title == "TRAVEL · ITINERARY", element.type == .text, element.isEditableText else { return false }
        return abs(element.position.y - 97.08) < 2
            && (abs(element.position.x - 46.95) < 3 || abs(element.position.x - 125.18) < 3)
    }

    private func isTravelWritingLine(_ line: MagazineElement) -> Bool {
        guard line.type == .line else { return false }

        switch page.title {
        case "TRAVEL · POSTCARD":
            // Greetings from: left flowing note column and right "TO" column.
            let isLeft = abs(line.position.x - 48.69) < 2
                && [168.5, 184.0, 199.5, 215.0].contains { abs(line.position.y - $0) < 1.4 }
            let isRight = abs(line.position.x - 121.32) < 2
                && [184.0, 199.5, 215.0].contains { abs(line.position.y - $0) < 1.4 }
            return isLeft || isRight

        case "TRAVEL · ITINERARY":
            let isDestination = abs(line.position.x - 85.0) < 2
                && line.size.width > 130
                && abs(line.position.y - 80.29) < 1.4
            let isDayLine = abs(line.position.x - 100.45) < 2
                && line.size.width > 100
                && [108.82, 133.82, 158.82, 183.82, 208.82].contains { abs(line.position.y - $0) < 1.4 }
            return isDestination || isDayLine

        case "TRAVEL · PLACES SEEN":
            let rowYs: [CGFloat] = [89.12, 103.82, 118.53, 133.24, 147.94, 162.65, 177.35, 192.06, 206.76, 221.47]
            let isPlace = abs(line.position.x - 44.81) < 2 && line.size.width > 55
            let isWhen = abs(line.position.x - 97.36) < 2 && line.size.width > 25
            let isMemory = abs(line.position.x - 137.54) < 2 && line.size.width > 35
            return (isPlace || isWhen || isMemory) && rowYs.contains { abs(line.position.y - $0) < 1.4 }

        default:
            return false
        }
    }

    private func isTravelPostcardAddressLine(_ line: MagazineElement) -> Bool {
        guard page.title == "TRAVEL · POSTCARD", line.type == .line else { return false }
        return (abs(line.position.x - 48.69) < 2 && [168.5, 184.0, 199.5, 215.0].contains { abs(line.position.y - $0) < 1.4 })
            || (abs(line.position.x - 121.32) < 2 && [184.0, 199.5, 215.0].contains { abs(line.position.y - $0) < 1.4 })
    }

    private func isTravelItineraryDayLine(_ line: MagazineElement) -> Bool {
        guard page.title == "TRAVEL · ITINERARY", line.type == .line else { return false }
        return abs(line.position.x - 100.45) < 2
            && line.size.width > 100
            && [108.82, 121.47, 133.82, 146.47, 158.82, 171.47, 183.82, 196.47, 208.82, 221.47].contains { abs(line.position.y - $0) < 1.4 }
    }

    private func isTravelItineraryFirstDayLine(_ line: MagazineElement) -> Bool {
        isTravelItineraryDayLine(line)
            && [108.82, 133.82, 158.82, 183.82, 208.82].contains { abs(line.position.y - $0) < 1.4 }
    }

    private func isTravelPlacesPlaceLine(_ line: MagazineElement) -> Bool {
        guard page.title == "TRAVEL · PLACES SEEN", line.type == .line else { return false }
        return abs(line.position.x - 44.81) < 2
            && [89.12, 103.82, 118.53, 133.24, 147.94, 162.65, 177.35, 192.06, 206.76, 221.47].contains { abs(line.position.y - $0) < 1.4 }
    }

    private func isTravelPlacesMemoryLine(_ line: MagazineElement) -> Bool {
        guard page.title == "TRAVEL · PLACES SEEN", line.type == .line else { return false }
        return abs(line.position.x - 137.54) < 2
            && [89.12, 103.82, 118.53, 133.24, 147.94, 162.65, 177.35, 192.06, 206.76, 221.47].contains { abs(line.position.y - $0) < 1.4 }
    }

    private func isTravelPlacesTwoLine(_ line: MagazineElement) -> Bool {
        isTravelPlacesPlaceLine(line) || isTravelPlacesMemoryLine(line)
    }


    private func isFavouritesWritingLine(_ line: MagazineElement) -> Bool {
        guard line.type == .line else { return false }
        switch page.title {
        case "FAVOURITES · BEAUTY SHELF":
            return abs(line.position.x - 111.28) < 2
                && line.size.width > 85
                && [83.5, 170.5].contains { abs(line.position.y - $0) < 1.4 }

        case "FAVOURITES · EDIBLE":
            let inColumn = abs(line.position.x - 46.36) < 2 || abs(line.position.x - 123.64) < 2
            return inColumn
                && line.size.width > 60
                && [148.0, 164.0, 181.0, 194.0, 207.0].contains { abs(line.position.y - $0) < 1.4 }

        case "FAVOURITES · APPS & INTERNET":
            let topName = (abs(line.position.x - 46.36) < 2 || abs(line.position.x - 123.64) < 2)
                && abs(line.position.y - 93.5) < 1.4
            let bottomName = (abs(line.position.x - 47.59) < 2 || abs(line.position.x - 124.86) < 2)
                && abs(line.position.y - 167.6) < 1.4
            return (topName || bottomName) && line.size.width > 50

        default:
            return false
        }
    }

    private func isFavouritesEdibleOrderLine(_ line: MagazineElement) -> Bool {
        guard page.title == "FAVOURITES · EDIBLE", line.type == .line else { return false }
        let inColumn = abs(line.position.x - 46.36) < 2 || abs(line.position.x - 123.64) < 2
        return inColumn
            && line.size.width > 60
            && [181.0, 194.0, 207.0].contains { abs(line.position.y - $0) < 1.4 }
    }

    private func isFavouritesEditableTextBox(_ element: MagazineElement) -> Bool {
        guard element.type == .box else { return false }
        switch page.title {
        case "FAVOURITES · BEAUTY SHELF":
            return element.size.width > 85
                && element.size.height > 10
                && [109.0, 196.0].contains { abs(element.position.y - $0) < 2.0 }
        case "FAVOURITES · APPS & INTERNET":
            return element.size.width > 60
                && element.size.height > 20
                && [128.5, 202.5].contains { abs(element.position.y - $0) < 2.0 }
        default:
            return false
        }
    }

    private func isAffirmationsWritingLine(_ line: MagazineElement) -> Bool {
        guard line.type == .line else { return false }
        switch page.title {
        case "GOALS · OUTLOOK":
            return isAffirmationsOutlookGoalLine(line)
        case "GOALS · AFFIRMATIONS":
            return isAffirmationsIntentionsLine(line)
        default:
            return false
        }
    }

    private func isAffirmationsOutlookGoalLine(_ line: MagazineElement) -> Bool {
        guard page.title == "GOALS · OUTLOOK", line.type == .line else { return false }
        let inBoxColumn = abs(line.position.x - 34.52) < 2 || abs(line.position.x - 85.0) < 2 || abs(line.position.x - 135.49) < 2
        let upperRows: [CGFloat] = [136.18, 144.41, 152.65, 160.88]
        let lowerRows: [CGFloat] = [195.0, 203.24, 211.47, 219.71]
        return inBoxColumn
            && line.size.width > 28
            && (upperRows + lowerRows).contains { abs(line.position.y - $0) < 1.4 }
    }

    private func isAffirmationsWordField(_ element: MagazineElement) -> Bool {
        guard element.type == .title, element.isEditableText else { return false }
        return (page.title == "GOALS · OUTLOOK" && abs(element.position.x - 85.0) < 2 && abs(element.position.y - 91.17) < 2)
            || (page.title == "GOALS · AFFIRMATIONS" && abs(element.position.x - 85.0) < 2 && abs(element.position.y - 158.82) < 2)
    }

    private func isAffirmationsIntentionsLine(_ line: MagazineElement) -> Bool {
        guard page.title == "GOALS · AFFIRMATIONS", line.type == .line else { return false }
        return abs(line.position.x - 85.0) < 2
            && line.size.width > 120
            && [190.59, 200.0, 209.41, 218.82, 228.24].contains { abs(line.position.y - $0) < 1.4 }
    }

    private func isFoodRecipeWritingLine(_ line: MagazineElement) -> Bool {
        guard line.type == .line else { return false }

        switch page.title {
        case "FOOD & RECIPES · RECIPE CARD":
            let isDish = abs(line.position.x - 85.0) < 2
                && line.size.width > 130
                && abs(line.position.y - 145.0) < 1.4
            let isServes = abs(line.position.x - 35.54) < 2
                && line.size.width > 35
                && abs(line.position.y - 161.18) < 1.4
            let isTime = abs(line.position.x - 88.09) < 2
                && line.size.width > 35
                && abs(line.position.y - 161.18) < 1.4
            let isNotes = abs(line.position.x - 137.54) < 2
                && line.size.width > 30
                && abs(line.position.y - 161.18) < 1.4
            let isIngredients = abs(line.position.x - 39.87) < 2
                && line.size.width > 45
                && [173.53, 184.20, 194.80, 205.40, 216.00, 226.60, 237.20].contains { abs(line.position.y - $0) < 1.4 }
            let isMethod = abs(line.position.x - 120.24) < 2
                && line.size.width > 60
                && [184.20, 194.80, 205.40, 216.00, 226.60, 237.20].contains { abs(line.position.y - $0) < 1.4 }
            return isDish || isServes || isTime || isNotes || isIngredients || isMethod

        case "FOOD & RECIPES · WEEK ON A PLA":
            // Breakfast, lunch and dinner stay as three separate fields for each day.
            let isBreakfast = abs(line.position.x - 52.8) < 2 && line.size.width > 30
            let isLunch = abs(line.position.x - 93.5) < 2 && line.size.width > 30
            let isDinner = abs(line.position.x - 134.19) < 2 && line.size.width > 30
            return (isBreakfast || isLunch || isDinner)
                && [90.59, 111.18, 131.76, 152.35, 172.94, 193.53, 214.12].contains { abs(line.position.y - $0) < 1.4 }

        case "FOOD & RECIPES · TABLE FOR ONE":
            let isTableForNumber = isFoodTableForNumberLine(line)
            let isPlace = abs(line.position.x - 85.0) < 2
                && line.size.width > 130
                && [81.76, 83.2].contains { abs(line.position.y - $0) < 1.4 }
            let isDate = abs(line.position.x - 48.68) < 2
                && line.size.width > 60
                && [97.94, 101.0].contains { abs(line.position.y - $0) < 1.4 }
            let isOccasion = abs(line.position.x - 126.73) < 2
                && line.size.width > 50
                && [97.94, 101.0].contains { abs(line.position.y - $0) < 1.4 }
            return isTableForNumber || isPlace || isDate || isOccasion

        default:
            return false
        }
    }

    private func isFoodRecipeIngredientsLine(_ line: MagazineElement) -> Bool {
        page.title == "FOOD & RECIPES · RECIPE CARD"
            && abs(line.position.x - 39.87) < 2
            && [173.53, 184.20, 194.80, 205.40, 216.00, 226.60, 237.20].contains { abs(line.position.y - $0) < 1.4 }
    }

    private func isFoodRecipeMethodLine(_ line: MagazineElement) -> Bool {
        page.title == "FOOD & RECIPES · RECIPE CARD"
            && abs(line.position.x - 120.24) < 2
            && [184.20, 194.80, 205.40, 216.00, 226.60, 237.20].contains { abs(line.position.y - $0) < 1.4 }
    }

    private func isFoodWeekMealLine(_ line: MagazineElement) -> Bool {
        guard page.title == "FOOD & RECIPES · WEEK ON A PLA", line.type == .line else { return false }
        let isBreakfast = abs(line.position.x - 52.8) < 2 && line.size.width > 30
        let isLunch = abs(line.position.x - 93.5) < 2 && line.size.width > 30
        let isDinner = abs(line.position.x - 134.19) < 2 && line.size.width > 30
        return (isBreakfast || isLunch || isDinner)
            && [90.59, 111.18, 131.76, 152.35, 172.94, 193.53, 214.12].contains { abs(line.position.y - $0) < 1.4 }
    }

    private func isTwoLineFoodLine(_ line: MagazineElement) -> Bool {
        isFoodRecipeMethodLine(line) || isFoodWeekMealLine(line)
    }

    private func isFoodTableForNumberLine(_ line: MagazineElement) -> Bool {
        page.title == "FOOD & RECIPES · TABLE FOR ONE"
            && line.type == .line
            && abs(line.position.x - 55.0) < 2
            && abs(line.position.y - 57.8) < 2
            && line.size.width > 18
    }

    private func isFoodTableInfoLine(_ line: MagazineElement) -> Bool {
        guard page.title == "FOOD & RECIPES · TABLE FOR ONE", line.type == .line else { return false }
        let isPlace = abs(line.position.x - 85.0) < 2 && line.size.width > 130 && [81.76, 83.2].contains { abs(line.position.y - $0) < 1.4 }
        let isDate = abs(line.position.x - 48.68) < 2 && line.size.width > 60 && [97.94, 101.0].contains { abs(line.position.y - $0) < 1.4 }
        let isOccasion = abs(line.position.x - 126.73) < 2 && line.size.width > 50 && [97.94, 101.0].contains { abs(line.position.y - $0) < 1.4 }
        return isPlace || isDate || isOccasion
    }

    private func hasNotePromptAbove(_ line: MagazineElement) -> Bool {
        page.elements.contains { element in
            guard element.type == .text else { return false }
            let trimmed = templateLogicText(element.text).lowercased()
            let dy = line.position.y - element.position.y
            return trimmed.contains("a note")
                && dy > 1.5
                && dy < 6.5
                && abs(element.position.x - line.position.x) < max(4, line.size.width * 0.25)
                && element.fontSize <= 5.2
        }
    }

    private func isNoteWritingLine(_ line: MagazineElement) -> Bool {
        page.elements.contains { element in
            guard element.type == .text else { return false }
            let trimmed = templateLogicText(element.text).lowercased()
            let dy = line.position.y - element.position.y
            return trimmed.contains("a note")
                && dy > 1.5
                && dy < 15
                && abs(element.position.x - line.position.x) < max(4, line.size.width * 0.25)
                && element.fontSize <= 5.2
        }
    }

    private func isContinuousColumnLine(_ line: MagazineElement) -> Bool {
        isMagazineContinuousColumnLine(line, pageTitle: page.title)
    }

    private func continuousColumnRootIndices() -> [Int] {
        if page.title == "TINY WINS · TROPHY CABINET" {
            return page.elements.indices.filter { idx in
                isContinuousColumnLine(page.elements[idx])
                    && [96.5, 135.0, 174.0, 213.0].contains { abs(page.elements[idx].position.y - $0) < 1.0 }
            }
            .sorted { page.elements[$0].position.y < page.elements[$1].position.y }
        }

        var roots: [Int] = []
        let columnXs = page.elements.filter { isContinuousColumnLine($0) }.map { $0.position.x }
        for columnX in columnXs {
            let candidates = page.elements.indices.filter { idx in
                isContinuousColumnLine(page.elements[idx]) && abs(page.elements[idx].position.x - columnX) < 2
            }
            if let first = candidates.min(by: { page.elements[$0].position.y < page.elements[$1].position.y }), !roots.contains(first) {
                roots.append(first)
            }
        }
        return roots.sorted { page.elements[$0].position.x < page.elements[$1].position.x }
    }

    private func continuousColumnRect(for line: MagazineElement) -> CGRect {
        let sameColumnLines: [MagazineElement]
        if page.title == "TINY WINS · TROPHY CABINET" {
            sameColumnLines = page.elements.filter { other in
                isContinuousColumnLine(other)
                    && abs(other.position.x - line.position.x) < 2
                    && abs(other.position.y - line.position.y) <= 11.0
            }
        } else {
            sameColumnLines = page.elements.filter { other in
                isContinuousColumnLine(other) && abs(other.position.x - line.position.x) < 2
            }
        }
        guard let firstY = sameColumnLines.map(\.position.y).min(), let lastY = sameColumnLines.map(\.position.y).max() else {
            return CGRect(
                x: line.position.x - line.size.width / 2,
                y: line.position.y - 21,
                width: line.size.width,
                height: 42
            )
        }
        let top: CGFloat
        let bottom: CGFloat
        if page.title == "MONTHLY RESET" {
            top = firstY - 3.0
            bottom = lastY + 4.8
        } else if page.title == "TINY WINS · TROPHY CABINET" {
            top = firstY - 7.0
            bottom = lastY + 4.2
        } else {
            top = firstY - 1.1
            bottom = lastY + 5.4
        }
        let yOffset: CGFloat = page.title == "MONTHLY RESET" ? 1.6 : (page.title == "TINY WINS · TROPHY CABINET" ? -1.0 : 0)
        return CGRect(
            x: line.position.x - line.size.width / 2,
            y: top + yOffset,
            width: line.size.width,
            height: bottom - top
        )
    }

    private func continuousColumnCharacterLimit(for size: CGSize) -> Int {
        // Continuous text: one flowing column/card aligned to the visible template lines.
        let averageCharacterWidth: CGFloat = page.title == "TINY WINS · TROPHY CABINET" ? 2.35 : 2.45
        let lineHeight = continuousColumnLayout.lineHeight
        let charactersPerLine = max(1, Int((size.width - 3) / averageCharacterWidth))
        let lines = max(1, Int(size.height / lineHeight))
        let baseLimit = charactersPerLine * lines
        if page.title == "TINY WINS · TROPHY CABINET" { return max(1, baseLimit + 1) }
        if page.title == "MONTHLY RESET" { return max(1, baseLimit) }
        return baseLimit
    }

    private func isTrophyCabinetWritingLine(_ line: MagazineElement) -> Bool {
        guard page.title == "TINY WINS · TROPHY CABINET" else { return false }
        return abs(line.position.x - 96.0) < 2
            && [96.5, 106.5, 135.0, 145.0, 174.0, 184.0, 213.0, 223.0].contains { abs(line.position.y - $0) < 1.0 }
    }

    private func lineAllowsOverflow(_ line: MagazineElement) -> Bool {
        // These may move overflow to the next printed line in the same column/card.
        isContinuousColumnLine(line) || isHowIGrewNoteLine(line) || isInLoveWithLifeLine(line) || isPeopleLoveHowWeMetLine(line) || isCrushDiaryOverflowLine(line) || isPlaylistFestivalWhyLine(line) || isNoteWritingLine(line) || isTrophyCabinetWritingLine(line) || isFoodRecipeIngredientsLine(line) || isFavouritesEdibleOrderLine(line) || isTravelPostcardAddressLine(line) || isAffirmationsOutlookGoalLine(line) || isAffirmationsIntentionsLine(line) || (page.title == "READING · TBR STACK" && isReadingWritingLine(line))
    }

    private func isCrushDiaryOverflowLine(_ line: MagazineElement) -> Bool {
        isCrushDiaryWritingLine(line) && abs(line.position.y - 79.41) >= 1.5
    }

    private func lineWrappingAllowed(_ line: MagazineElement) -> Bool {
        // Highs/Lows must never wrap inside one overlay; overflow moves to the next printed line.
        // Notes and trophy awards may use their two-line card area.
        isNoteWritingLine(line) || isTrophyCabinetWritingLine(line) || isPlaylistFestivalWhyLine(line) || isFoodRecipeMethodLine(line) || isFoodWeekMealLine(line) || isTravelItineraryFirstDayLine(line) || isTravelPlacesTwoLine(line)
    }

    private func lineMaximumNumberOfLines(_ line: MagazineElement) -> Int {
        if isTravelItineraryFirstDayLine(line) { return 2 }
        if isTravelPlacesTwoLine(line) { return 2 }
        if isPlaylistFestivalWhyLine(line) { return 1 }
        if isFavouritesEdibleOrderLine(line) { return 1 }
        return lineWrappingAllowed(line) ? 0 : 1
    }

    private func editableLineOverlayHeight(for line: MagazineElement, styleFontSize: CGFloat, scaleY: CGFloat) -> CGFloat {
        if isTravelItineraryFirstDayLine(line) {
            return max(10, 25.3 * scaleY)
        }
        if page.title == "TRAVEL · PLACES SEEN", isTravelPlacesTwoLine(line) {
            return max(10, styleFontSize * scaleY * 2.70)
        }
        if isTwoLineFoodLine(line) {
            return max(10, styleFontSize * scaleY * 2.55)
        }
        if lineAllowsOverflow(line) {
            return max(10, styleFontSize * scaleY * 2.35)
        }
        return max(10, styleFontSize * scaleY * 1.55)
    }

    private func editableLineTextLineHeight(for line: MagazineElement, styleFontSize: CGFloat, scaleY: CGFloat) -> CGFloat? {
        if isTravelItineraryFirstDayLine(line) {
            return 12.65 * scaleY
        }
        if isPlaylistFestivalWhyLine(line) {
            return 9.0 * scaleY
        }
        if page.title == "TRAVEL · PLACES SEEN", isTravelPlacesTwoLine(line) {
            return max(1, styleFontSize * scaleY * 1.30)
        }
        return nil
    }

    private func hasBulletPromptBeside(_ line: MagazineElement) -> Bool {
        page.elements.contains { element in
            let trimmed = templateLogicText(element.text)
            let lineLeft = line.position.x - line.size.width / 2
            return trimmed == "✦"
                && abs(element.position.y - line.position.y) < 5.5
                && abs(element.position.x - lineLeft) < 7
        }
    }

    private func hasNumberPromptBeside(_ line: MagazineElement) -> Bool {
        page.elements.contains { element in
            let trimmed = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let lineLeft = line.position.x - line.size.width / 2
            return trimmed.range(of: #"^\d+\.$"#, options: .regularExpression) != nil
                && abs(element.position.y - line.position.y) < 5.5
                && element.position.x < lineLeft
                && lineLeft - element.position.x < 18
        }
    }

    private func hasAllCapsHeaderDirectlyAbove(_ line: MagazineElement) -> Bool {
        page.elements.contains { element in
            guard element.type == .text else { return false }
            let trimmed = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed == trimmed.uppercased(), trimmed.rangeOfCharacter(from: .letters) != nil else { return false }
            return abs(element.position.x - line.position.x) < 4
                && line.position.y - element.position.y > 1.5
                && line.position.y - element.position.y < 5
        }
    }

    private func isNameWritingLine(_ line: MagazineElement) -> Bool {
        page.elements.contains { element in
            guard element.type == .text else { return false }
            let trimmed = templateLogicText(element.text).lowercased()
            let dy = element.position.y - line.position.y
            return trimmed == "your name"
                && dy > 1.0
                && dy < 4.8
                && abs(element.position.x - line.position.x) < max(6, line.size.width * 0.25)
        }
    }

    private func isSceneTitleWritingLine(_ line: MagazineElement) -> Bool {
        if page.title == "TINY WINS · HIGHLIGHT REEL", line.type == .line {
            let isSceneTitleGuide = (abs(line.position.x - 47.0) < 2 || abs(line.position.x - 123.0) < 2)
                && [134.0, 209.5].contains { abs(line.position.y - $0) < 1.2 }
            if isSceneTitleGuide { return true }
        }
        return page.elements.contains { element in
            guard element.type == .text else { return false }
            let trimmed = templateLogicText(element.text).lowercased()
            let dy = element.position.y - line.position.y
            return trimmed == "title"
                && dy > 1.0
                && dy < 4.8
                && abs(element.position.x - line.position.x) < max(6, line.size.width * 0.25)
        }
    }

    private func lineCharacterLimit(for element: MagazineElement) -> Int {
        if isNameWritingLine(element) { return max(8, Int(element.size.width / 2.85)) }
        if isEndMonthDateMoodFeelingLine(element) { return max(10, Int(element.size.width / 1.75)) }
        if isDearMonthLoveLine(element) { return max(12, Int(element.size.width / 1.60)) }
        if isHowIGrewNoteLine(element) { return max(10, Int(element.size.width / 1.55)) }
        if isGratitudeListLine(element) { return max(10, Int(element.size.width / 1.55)) }
        if isHobbyTrackerNameLine(element) { return max(10, Int(element.size.width / 1.65)) }
        if isNewHobbyNameLine(element) { return max(10, Int(element.size.width / 1.95)) }
        if isCinemaRowSeatField(element) { return 4 }
        if isCinemaTicketShortField(element) { return 4 }
        if isCinemaWatchLogTitleLine(element) { return max(12, Int(element.size.width / 1.65)) }
        if isCinemaWatchLogDateLine(element) { return max(4, Int(element.size.width / 2.1)) }
        if isCinemaHighlightsWritingLine(element) { return max(8, Int(element.size.width / 1.70)) }
        if isReadingWritingLine(element) { return page.title == "READING · TBR STACK" ? max(10, Int(element.size.width / 1.65)) : max(8, Int(element.size.width / 1.55)) }
        if isTravelItineraryFromToField(element) { return max(8, Int(element.size.width / 1.35)) }
        if isTravelWritingLine(element) {
            if isTravelPlacesMemoryLine(element) { return max(28, Int(element.size.width / 0.88)) }
            if isTravelPlacesPlaceLine(element) { return max(40, Int(element.size.width / 0.88)) }
            if isTravelItineraryDayLine(element) { return max(34, Int(element.size.width / 1.05)) }
            return max(8, Int(element.size.width / 1.55))
        }
        if isFavouritesWritingLine(element) { return max(8, Int(element.size.width / 1.45)) }
        if isAffirmationsOutlookGoalLine(element) { return max(8, Int(element.size.width / 1.70)) }
        if isAffirmationsIntentionsLine(element) { return max(22, Int(element.size.width / 1.40)) }
        if isFoodTableForNumberLine(element) { return 4 }
        if isFoodRecipeWritingLine(element) {
            if isFoodRecipeMethodLine(element) || isFoodWeekMealLine(element) { return max(18, Int(element.size.width / 1.05)) }
            return max(8, Int(element.size.width / 1.55))
        }
        if isDateReviewInfoLine(element) { return max(18, Int(element.size.width / 1.45)) }
        if isCinemaTicketWritingLine(element) { return max(6, Int(writingLineOverlayFrame(for: element).size.width / 1.55)) }
        if isPlaylistFestivalWhyLine(element) {
            let divisor: CGFloat = [105.0, 166.0, 227.0].contains { abs(element.position.y - $0) < 1.4 } ? 1.9 : 1.65
            return max(8, Int(writingLineOverlayFrame(for: element).size.width / divisor))
        }
        if isPlaylistMusicWritingLine(element) { return max(8, Int(element.size.width / 1.50)) }
        if isCrushDiaryNameLine(element) { return 16 }
        if isCrushDiaryWritingLine(element) { return max(8, Int(element.size.width / 1.55)) }
        if isRankingOccupationOrAgeLine(element) { return max(4, Int(element.size.width / 1.55)) }
        if isPeopleLoveNameLine(element) { return max(10, Int(element.size.width / 1.45)) }
        if isPeopleLoveHowWeMetLine(element) { return max(12, Int(element.size.width / 1.55)) }
        if isInLoveWithLifeLine(element) { return max(14, Int(element.size.width / 1.55)) }
        if isInLoveSignatureLine(element) { return max(8, Int(element.size.width / 1.35)) }
        if isSceneTitleWritingLine(element) { return max(8, Int(element.size.width / 1.45)) }
        if isContinuousColumnLine(element) { return max(12, Int(element.size.width / 1.50)) }
        if isTrophyCabinetWritingLine(element) { return max(14, Int(element.size.width / 1.65)) }
        if isNoteWritingLine(element) { return max(12, Int(element.size.width / 1.65)) }
        if hasNumberPromptBeside(element) || hasBulletPromptBeside(element) { return max(6, Int(element.size.width / 2.05)) }
        return max(8, Int(element.size.width / 1.85))
    }

    private func moveOverflow(_ overflow: String, from index: Int) {
        guard !overflow.isEmpty, let nextIndex = nextEditableWritingLineIndex(after: index) else { return }
        guard page.elements.indices.contains(nextIndex) else { return }
        let nextElement = page.elements[nextIndex]
        let style = lineTextStyle(for: nextElement)
        let combined = overflow + page.elements[nextIndex].text
        let limit = lineCharacterLimit(for: nextElement)
        page.elements[nextIndex].fontName = style.fontName
        page.elements[nextIndex].fontSize = style.fontSize
        page.elements[nextIndex].isBold = style.isBold
        page.elements[nextIndex].text = String(combined.prefix(limit))
        focusedLineID = page.elements[nextIndex].id
    }

    private func nextEditableWritingLineIndex(after index: Int) -> Int? {
        guard page.elements.indices.contains(index) else { return nil }
        let current = page.elements[index]

        if isCrushDiaryNameLine(current) {
            return nil
        }
        if page.title == "READING · TBR STACK" && isReadingWritingLine(current) {
            return nil
        }
        if isTravelItineraryDayLine(current) && !isTravelItineraryFirstDayLine(current) {
            return nil
        }

        let maxColumnDistance: CGFloat
        if isTrophyCabinetWritingLine(current) || isContinuousColumnLine(current) || isInLoveWithLifeLine(current) || isCrushDiaryWritingLine(current) || isPeopleLoveHowWeMetLine(current) || isFoodRecipeIngredientsLine(current) || isFoodRecipeMethodLine(current) || isFavouritesEdibleOrderLine(current) || isTravelPostcardAddressLine(current) || isTravelItineraryDayLine(current) || isAffirmationsOutlookGoalLine(current) || isAffirmationsIntentionsLine(current) {
            maxColumnDistance = max(4, current.size.width * 0.08)
        } else {
            maxColumnDistance = max(10, current.size.width * 0.35)
        }
        let maxVerticalDistance: CGFloat = lineAllowsOverflow(current) ? (isTravelItineraryDayLine(current) ? 14 : ((isTrophyCabinetWritingLine(current) || isInLoveWithLifeLine(current) || isCrushDiaryWritingLine(current) || isPeopleLoveHowWeMetLine(current) || isFoodRecipeIngredientsLine(current) || isFoodRecipeMethodLine(current) || isFavouritesEdibleOrderLine(current) || isTravelPostcardAddressLine(current) || isAffirmationsOutlookGoalLine(current) || isAffirmationsIntentionsLine(current)) ? 18 : 10)) : 0

        return page.elements.indices
            .filter {
                let candidate = page.elements[$0]
                let sameCrushGroup = !isCrushDiaryWritingLine(current)
                    || (isCrushDiaryFirstNoticedLine(current) && isCrushDiaryFirstNoticedLine(candidate))
                    || (isCrushDiaryHotLine(current) && isCrushDiaryHotLine(candidate))
                    || (isCrushDiaryKnownLine(current) && isCrushDiaryKnownLine(candidate))
                let samePeopleHowWeMetGroup = !isPeopleLoveHowWeMetLine(current)
                    || (isPeopleLoveHowWeMetLine(candidate) && abs(candidate.position.x - current.position.x) <= maxColumnDistance)
                let sameFoodGroup = !(isFoodRecipeIngredientsLine(current) || isFoodRecipeMethodLine(current))
                    || (isFoodRecipeIngredientsLine(current) && isFoodRecipeIngredientsLine(candidate))
                    || (isFoodRecipeMethodLine(current) && isFoodRecipeMethodLine(candidate))
                let sameFavouritesEdibleOrderGroup = !isFavouritesEdibleOrderLine(current)
                    || (isFavouritesEdibleOrderLine(candidate) && abs(candidate.position.x - current.position.x) <= maxColumnDistance)
                let sameTravelPostcardGroup = !isTravelPostcardAddressLine(current)
                    || (isTravelPostcardAddressLine(candidate) && abs(candidate.position.x - current.position.x) <= maxColumnDistance)
                let sameTravelDayGroup = !isTravelItineraryDayLine(current)
                    || (isTravelItineraryDayLine(candidate) && isTravelItineraryFirstDayLine(current) && abs(candidate.position.x - current.position.x) <= maxColumnDistance && candidate.position.y - current.position.y <= 14)
                let sameAffirmationOutlookGroup = !isAffirmationsOutlookGoalLine(current)
                    || (isAffirmationsOutlookGoalLine(candidate) && abs(candidate.position.x - current.position.x) <= maxColumnDistance)
                let sameAffirmationIntentionsGroup = !isAffirmationsIntentionsLine(current)
                    || isAffirmationsIntentionsLine(candidate)
                return $0 > index
                    && isEditableWritingLine(candidate)
                    && sameCrushGroup
                    && samePeopleHowWeMetGroup
                    && sameFoodGroup
                    && sameFavouritesEdibleOrderGroup
                    && sameTravelPostcardGroup
                    && sameTravelDayGroup
                    && sameAffirmationOutlookGroup
                    && sameAffirmationIntentionsGroup
                    && abs(candidate.position.x - current.position.x) <= maxColumnDistance
                    && candidate.position.y > current.position.y
                    && candidate.position.y - current.position.y <= maxVerticalDistance
            }
            .min()
    }

    private func lineTextStyle(for line: MagazineElement) -> (fontName: String, fontSize: CGFloat, isBold: Bool) {
        if isHobbyTrackerNameLine(line) { return ("Georgia", 7.2, false) }
        if isNewHobbyNameLine(line) { return ("Georgia", 5.7, false) }
        if isEndMonthDateMoodFeelingLine(line) { return ("Helvetica", 7.2, false) }
        if isDearMonthLoveLine(line) { return ("Georgia", 7.2, false) }
        if isHowIGrewNoteLine(line) { return ("Helvetica", 5.1, false) }
        if isGratitudeListLine(line) { return ("Helvetica", 5.0, false) }
        if isDateReviewInfoLine(line) { return ("Georgia", 6.2, false) }
        if isCinemaTicketWritingLine(line) { return ("Helvetica", abs(line.position.y - 105.29) < 1.4 ? 5.8 : 5.2, false) }
        if isCinemaWatchLogTitleLine(line) { return ("Helvetica", 6.04, false) }
        if isCinemaWatchLogDateLine(line) { return ("Helvetica", 6.04, false) }
        if isCinemaHighlightsWritingLine(line) { return ("Helvetica", 5.6, false) }
        if isReadingWritingLine(line) { return ("Helvetica", page.title == "READING · MARGIN NOTES" ? 6.0 : 5.4, false) }
        if isTravelItineraryFromToField(line) { return ("Helvetica", 5.0, false) }
        if isTravelItineraryDayLine(line) { return ("Helvetica", 4.8, false) }
        if isTravelPlacesTwoLine(line) { return ("Helvetica", 3.95, false) }
        if isTravelWritingLine(line) { return ("Helvetica", page.title == "TRAVEL · POSTCARD" ? 5.35 : 4.65, false) }
        if isFavouritesWritingLine(line) { return ("Helvetica", page.title == "FAVOURITES · EDIBLE" ? 5.35 : (page.title == "FAVOURITES · BEAUTY SHELF" ? 5.05 : (page.title == "FAVOURITES · APPS & INTERNET" ? 6.2 : 4.9)), false) }
        if isAffirmationsOutlookGoalLine(line) { return ("Helvetica", 4.45, false) }
        if isAffirmationsIntentionsLine(line) { return ("Helvetica", 5.2, false) }
        if isFoodTableForNumberLine(line) { return ("Georgia", 14.5, false) }
        if isFoodTableInfoLine(line) { return ("Georgia", 8.1, false) }
        if isFoodWeekMealLine(line) { return ("Helvetica", 4.55, false) }
        if isFoodRecipeMethodLine(line) { return ("Helvetica", 4.05, false) }
        if isFoodRecipeWritingLine(line) { return ("Helvetica", 5.0, false) }
        if isPlaylistMusicWritingLine(line) {
            switch page.title {
            case "PLAYLIST & MUSIC · FESTIVAL":
                return ("Helvetica", 6.2, false)
            case "PLAYLIST & MUSIC · LINER NOTES", "PLAYLIST & MUSIC · MIXTAPE":
                return ("Helvetica", 6.0, false)
            case "PLAYLIST & MUSIC · WRAPPED":
                return ("Helvetica", 5.5, false)
            default:
                return ("Helvetica", 4.9, false)
            }
        }
        if isCrushDiaryNameLine(line) { return ("Georgia", 7.3, false) }
        if isCrushDiaryWritingLine(line) { return ("Helvetica", 5.7, false) }
        if isRankingOccupationOrAgeLine(line) { return ("Helvetica", 5.15, false) }
        if isPeopleLoveNameLine(line) { return ("Georgia", 5.8, false) }
        if isPeopleLoveHowWeMetLine(line) { return ("Helvetica", 4.7, false) }
        if isInLoveWithLifeLine(line) { return ("Georgia", 6.6, false) }
        if isInLoveSignatureLine(line) { return ("Georgia", 7.2, false) }
        if isContinuousColumnLine(line) { return ("Georgia", 4.7, false) }
        if isSceneTitleWritingLine(line) { return ("Helvetica", 7.1, false) }
        if isTrophyCabinetWritingLine(line) { return ("Helvetica", 4.32, false) }
        if page.elements.contains(where: { $0.text == "How I grew." }) { return ("Helvetica", 4.05, false) }
        let labelAbove = page.elements
            .filter { element in
                element.type == .text
                    && !element.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && abs(element.position.x - line.position.x) < max(20, line.size.width * 0.8)
                    && line.position.y - element.position.y > 1.5
                    && line.position.y - element.position.y < 8
            }
            .min { abs($0.position.y - line.position.y) < abs($1.position.y - line.position.y) }
        if let labelAbove {
            return (labelAbove.fontName, labelAbove.fontSize, labelAbove.isBold)
        }

        let nearby = page.elements
            .filter { element in
                element.type == .text
                    && abs(element.position.y - line.position.y) < 5.5
                    && abs(element.position.x - line.position.x) < max(20, line.size.width * 0.8)
                    && !element.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .min { abs($0.position.y - line.position.y) < abs($1.position.y - line.position.y) }
        if let nearby {
            return (nearby.fontName, nearby.fontSize, nearby.isBold)
        }
        return ("Helvetica", 5.04, false)
    }

    private func displayPosition(for element: MagazineElement) -> CGPoint {
        if page.elements.contains(where: { templateLogicText($0.text) == "How I grew." }) && templateLogicText(element.text).lowercased().contains("a note") {
            return element.position
        }
        guard coverHasUploadedPhoto, page.sectionTitle == "Cover" else { return element.position }
        if element.text == "PenPal" { return CGPoint(x: element.position.x, y: 100) }
        if element.text.contains("THE EDITORIAL JOURNAL") { return CGPoint(x: element.position.x, y: 125) }
        if element.type == .image { return CGPoint(x: element.position.x, y: 177) }
        return element.position
    }

    private func isStreakOuterCell(_ element: MagazineElement) -> Bool {
        isStreakPage && element.type == .box && element.size.width > 12 && element.size.height > 10 && element.position.y > 70 && element.position.y < 160
    }

    private func isFillableSmallBox(_ element: MagazineElement) -> Bool {
        guard element.type == .box else { return false }
        if isStreakPage { return false }
        return element.size.width <= 9 && element.size.height <= 12
    }

    private func isRatingText(_ element: MagazineElement) -> Bool {
        let t = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.contains("♡") || t.contains("♥") || t.contains("☆") || t.contains("★ ★")
    }

    private func ratingRowWidth(for element: MagazineElement) -> CGFloat {
        let symbols = element.text.filter { $0 == "♡" || $0 == "♥" || $0 == "☆" || $0 == "★" }.count
        guard symbols > 0 else { return element.size.width }
        let availableWidth = max(1, element.size.width - element.textInset.width * 2)
        return min(availableWidth, max(availableWidth * 0.72, CGFloat(symbols) * element.fontSize * 0.9))
    }

    private func ratingRowOffsetX(for element: MagazineElement) -> CGFloat {
        let availableWidth = max(1, element.size.width - element.textInset.width * 2)
        let rowWidth = ratingRowWidth(for: element)
        switch element.textAlignment {
        case .left:
            return -availableWidth / 2 + rowWidth / 2 + element.textInset.width
        case .center:
            return 0
        case .right:
            return availableWidth / 2 - rowWidth / 2 - element.textInset.width
        }
    }

    private func selectChoice(at index: Int) {
        guard page.elements.indices.contains(index) else { return }
        let selected = page.elements[index]
        for candidateIndex in page.elements.indices where isChoiceText(page.elements[candidateIndex]) && abs(page.elements[candidateIndex].position.y - selected.position.y) < 3 {
            page.elements[candidateIndex].isMarked = candidateIndex == index
        }
    }

    private func isChoiceText(_ element: MagazineElement) -> Bool {
        let t = templateLogicText(element.text).uppercased()
        return ["YES", "NO", "MAYBE", "NEVER", "Y", "N"].contains(t)
    }

    private func isCompactChoiceText(_ element: MagazineElement) -> Bool {
        let t = templateLogicText(element.text).uppercased()
        return t == "Y" || t == "N"
    }

    private func choiceHitWidth(for element: MagazineElement, scaleX: CGFloat) -> CGFloat {
        let defaultWidth = isCompactChoiceText(element) ? max(22, element.size.width * scaleX * 1.35) : max(46, element.size.width * scaleX * 2.2)
        let sameRowDistances = page.elements
            .filter { isChoiceText($0) && $0.id != element.id && abs($0.position.y - element.position.y) < 3 }
            .map { abs($0.position.x - element.position.x) * scaleX }
        guard let nearest = sameRowDistances.min() else { return defaultWidth }
        return min(defaultWidth, max(element.size.width * scaleX, nearest * 0.9))
    }

    private func choiceHitHeight(for element: MagazineElement, scaleY: CGFloat) -> CGFloat {
        isCompactChoiceText(element) ? max(22, element.size.height * scaleY * 1.7) : max(34, element.size.height * scaleY * 2.6)
    }

    private func isSliderBox(_ element: MagazineElement) -> Bool {
        guard element.type == .box else { return false }
        if element.text == "__BLACK_FILL__" { return false }
        // Only the full-width progress bars are draggable. The shorter left boxes in the
        // PowerPoint template are static placeholders and must not capture the drag.
        if element.size.width > 95 && element.size.height <= 7 { return true }
        return false
    }
}

struct RatingTapLayer: View {
    @Binding var element: MagazineElement
    let scaleX: CGFloat
    let rowWidth: CGFloat
    let textInset: CGSize
    let textAlignment: PPTTextHorizontalAlignment
    @State private var gestureStartValue: Double?

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if gestureStartValue == nil {
                                gestureStartValue = element.interactionValue
                            }
                            setValue(value.location.x, width: geo.size.width, togglesMatchingValue: false)
                        }
                        .onEnded { value in
                            setValue(value.location.x, width: geo.size.width, togglesMatchingValue: true)
                            gestureStartValue = nil
                        }
                )
        }
    }

    private func setValue(_ x: CGFloat, width: CGFloat, togglesMatchingValue: Bool) {
        let scaledRowWidth = max(1, rowWidth * scaleX)
        let inset = textInset.width * scaleX
        let rowMinX: CGFloat
        switch textAlignment {
        case .left:
            rowMinX = inset
        case .center:
            rowMinX = (width - scaledRowWidth) / 2
        case .right:
            rowMinX = width - inset - scaledRowWidth
        }
        let rowMaxX = rowMinX + scaledRowWidth
        guard x >= rowMinX, x <= rowMaxX else { return }
        let slotWidth = scaledRowWidth / 5
        let value = Int(ceil((x - rowMinX) / max(1, slotWidth)))
        let clampedValue = min(5, max(1, value))
        if togglesMatchingValue, Int(gestureStartValue ?? element.interactionValue) == clampedValue {
            element.interactionValue = Double(max(0, clampedValue - 1))
        } else {
            element.interactionValue = Double(clampedValue)
        }
    }
}

struct SliderTapLayer: View {
    @Binding var element: MagazineElement
    let scaleX: CGFloat
    let scaleY: CGFloat

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in setValue(value.location.x, width: geo.size.width) }
                        .onEnded { value in setValue(value.location.x, width: geo.size.width) }
                )
        }
    }

    private func setValue(_ x: CGFloat, width: CGFloat) {
        let fraction = min(1, max(0, x / max(1, width)))
        element.interactionValue = Double(fraction)
    }
}

struct PhotoUploadTapLayer: View {
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    
    @Binding var element: MagazineElement
    let page: MagazinePage
    let scaleX: CGFloat
    let scaleY: CGFloat
    var selectedElementID: Binding<UUID?>?
    var onInteraction: (() -> Void)? = nil
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var lastDragOffset: CGSize = .zero
    @State private var lastZoom: CGFloat = 1
    @State private var showPhotoPicker = false
    @State private var showPhotoMenu = false
    @State private var showPhotoEditor = false

    private var isCoverPhoto: Bool { page.sectionTitle == "Cover" }
    private var isSelected: Bool { selectedElementID?.wrappedValue == element.id }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Rectangle().fill(Color.white.opacity(0.001))
                if let image = element.image {
                    GeometryReader { imageGeo in
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: element.imageFit == .fit ? .fit : .fill)
                            .frame(width: imageGeo.size.width, height: imageGeo.size.height)
                            .scaleEffect(element.imageZoom)
                            .offset(element.imageOffset)
                            .clipped()
                    }
                    .clipped()
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                            .font(isCoverPhoto ? .title2 : .body)
                        if !isCoverPhoto {
                            Text(appText("photo", languageRaw))
                                .font(.caption2)
                        }
                    }
                    .foregroundStyle(Color(uiColor: page.textColor).opacity(isCoverPhoto ? 0.45 : 0.6))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .overlay {
                if element.image != nil && isSelected {
                    Rectangle()
                        .stroke(Color.black.opacity(0.75), lineWidth: max(1, 0.7 * scaleY))
                        .allowsHitTesting(false)
                }
            }
            .highPriorityGesture(
                TapGesture().onEnded {
                    dismissKeyboard()
                    onInteraction?()
                    selectedElementID?.wrappedValue = nil
                    if element.image == nil {
                        showPhotoPicker = true
                    } else {
                        selectedElementID?.wrappedValue = element.id
                        lastDragOffset = element.imageOffset
                        lastZoom = element.imageZoom
                        showPhotoMenu = true
                    }
                }
            )
            .highPriorityGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        guard element.image != nil, isSelected else { return }
                        let baseOffset = lastDragOffset
                        let proposed = CGSize(width: baseOffset.width + value.translation.width, height: baseOffset.height + value.translation.height)
                        element.imageOffset = clampedOffset(proposed)
                    }
                    .onEnded { _ in
                        element.imageOffset = clampedOffset(element.imageOffset)
                        lastDragOffset = element.imageOffset
                    }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        guard element.image != nil, isSelected else { return }
                        element.imageZoom = min(6, max(1, safeUnitScale(lastZoom, fallback: 1) * pow(safeUnitScale(value, fallback: 1), 1.35)))
                        element.imageOffset = clampedOffset(element.imageOffset)
                    }
                    .onEnded { _ in
                        element.imageOffset = clampedOffset(element.imageOffset)
                        lastDragOffset = element.imageOffset
                        lastZoom = element.imageZoom
                    }
            )
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        element.image = image
                        element.imageData = nil
                        element.localImagePath = nil
                        element.imageStoragePath = nil
                        element.imageZoom = 1
                        element.imageOffset = .zero
                        lastDragOffset = .zero
                        lastZoom = 1
                        selectedElementID?.wrappedValue = element.id
                    }
                }
            }
            .confirmationDialog(appText("Photo", languageRaw), isPresented: $showPhotoMenu, titleVisibility: .visible) {
                Button(appText("Adjust photo", languageRaw)) {
                    showPhotoEditor = true
                }

                Button(appText("Change photo", languageRaw)) {
                    showPhotoPicker = true
                }

                Button(appText("Fit / Fill", languageRaw)) {
                    element.imageFit = element.imageFit == .fill ? .fit : .fill
                    element.imageZoom = 1
                    element.imageOffset = .zero
                    lastZoom = 1
                    lastDragOffset = .zero
                }

                Button(appText("Reset position", languageRaw)) {
                    element.imageZoom = 1
                    element.imageOffset = .zero
                    lastZoom = 1
                    lastDragOffset = .zero
                }

                Button(appText("Delete photo", languageRaw), role: .destructive) {
                    element.image = nil
                    element.imageData = nil
                    element.localImagePath = nil
                    element.imageStoragePath = nil
                    element.imageZoom = 1
                    element.imageOffset = .zero
                    selectedPhotoItem = nil
                    selectedElementID?.wrappedValue = nil
                    lastDragOffset = .zero
                    lastZoom = 1
                }

                Button(appText("Cancel", languageRaw), role: .cancel) {}
            }

            if let pastedImage = UIPasteboard.general.image, element.image == nil {
                Button {
                    element.image = pastedImage
                    element.imageData = nil
                    element.localImagePath = nil
                    element.imageStoragePath = nil
                    element.imageZoom = 1
                    element.imageOffset = .zero
                    lastDragOffset = .zero
                    lastZoom = 1
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: max(9, 5.5 * scaleY), weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(max(5, 3 * scaleY))
                        .background(Color.black.opacity(0.72))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(2)
                .accessibilityLabel(appText("Paste image", languageRaw))
            }
        }
        .clipped()
        .sheet(isPresented: $showPhotoEditor) {
            PhotoFrameAdjustmentView(element: $element, page: page)
        }
    }

    private func clampedOffset(_ proposed: CGSize) -> CGSize {
        guard let image = element.image else { return .zero }
        let frameSize = CGSize(width: max(1, element.size.width * scaleX), height: max(1, element.size.height * scaleY))
        guard frameSize.width > 1, frameSize.height > 1, image.size.width > 0, image.size.height > 0 else {
            return proposed
        }

        let baseScale: CGFloat
        if element.imageFit == .fit {
            baseScale = min(frameSize.width / image.size.width, frameSize.height / image.size.height)
        } else {
            baseScale = max(frameSize.width / image.size.width, frameSize.height / image.size.height)
        }

        let safeZoom = safeUnitScale(element.imageZoom, fallback: 1)
        let renderedWidth = image.size.width * baseScale * safeZoom
        let renderedHeight = image.size.height * baseScale * safeZoom
        let limitX = max(0, (renderedWidth - frameSize.width) / 2)
        let limitY = max(0, (renderedHeight - frameSize.height) / 2)

        return CGSize(
            width: min(limitX, max(-limitX, safeCGFloat(proposed.width, fallback: 0, context: "photoOffset.width"))),
            height: min(limitY, max(-limitY, safeCGFloat(proposed.height, fallback: 0, context: "photoOffset.height")))
        )
    }

    private func sanitizedOffset(_ offset: CGSize) -> CGSize {
        CGSize(
            width: safeCGFloat(offset.width, fallback: 0, context: "photoOffset.width"),
            height: safeCGFloat(offset.height, fallback: 0, context: "photoOffset.height")
        )
    }
}

struct PhotoFrameAdjustmentView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    @Binding var element: MagazineElement
    let page: MagazinePage
    @State private var displayOffset: CGSize = .zero
    @State private var dragStartOffset: CGSize = .zero
    @State private var displayZoom: CGFloat = 1
    @State private var zoomStart: CGFloat = 1

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let frameSize = editorFrameSize(in: proxy.size)
                let conversionScale = max(0.01, frameSize.width / max(1, element.size.width))

                VStack(spacing: 18) {
                    Spacer(minLength: 8)

                    ZStack {
                        Rectangle()
                            .fill(Color(uiColor: page.backgroundColor))
                        if let image = element.image {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: element.imageFit == .fit ? .fit : .fill)
                                .frame(width: frameSize.width, height: frameSize.height)
                                .scaleEffect(displayZoom)
                                .offset(displayOffset)
                                .clipped()
                        } else {
                            Text(appText("No photo selected.", languageRaw))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: frameSize.width, height: frameSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(uiColor: page.textColor).opacity(0.25), lineWidth: 1))
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let proposed = CGSize(width: dragStartOffset.width + value.translation.width, height: dragStartOffset.height + value.translation.height)
                                displayOffset = clampedDisplayOffset(proposed, frameSize: frameSize)
                                element.imageOffset = CGSize(width: displayOffset.width / conversionScale, height: displayOffset.height / conversionScale)
                            }
                            .onEnded { _ in
                                displayOffset = clampedDisplayOffset(displayOffset, frameSize: frameSize)
                                dragStartOffset = displayOffset
                                element.imageOffset = CGSize(width: displayOffset.width / conversionScale, height: displayOffset.height / conversionScale)
                            }
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                displayZoom = min(6, max(1, zoomStart * pow(safeUnitScale(value, fallback: 1), 1.2)))
                                element.imageZoom = displayZoom
                                displayOffset = clampedDisplayOffset(displayOffset, frameSize: frameSize)
                                element.imageOffset = CGSize(width: displayOffset.width / conversionScale, height: displayOffset.height / conversionScale)
                            }
                            .onEnded { _ in
                                displayZoom = safeUnitScale(displayZoom, fallback: 1)
                                zoomStart = displayZoom
                                displayOffset = clampedDisplayOffset(displayOffset, frameSize: frameSize)
                                dragStartOffset = displayOffset
                            }
                    )

                    HStack(spacing: 10) {
                        Button(appText("Fit / Fill", languageRaw)) {
                            element.imageFit = element.imageFit == .fill ? .fit : .fill
                            resetTransform(conversionScale: conversionScale)
                        }
                        .buttonStyle(.bordered)

                        Button(appText("Reset position", languageRaw)) {
                            resetTransform(conversionScale: conversionScale)
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer(minLength: 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(PenPalStyle.background.ignoresSafeArea())
                .onAppear {
                    displayZoom = safeUnitScale(element.imageZoom, fallback: 1)
                    zoomStart = displayZoom
                    displayOffset = CGSize(width: element.imageOffset.width * conversionScale, height: element.imageOffset.height * conversionScale)
                    displayOffset = clampedDisplayOffset(displayOffset, frameSize: frameSize)
                    dragStartOffset = displayOffset
                }
            }
            .navigationTitle(appText("Adjust photo", languageRaw))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(appText("Done", languageRaw)) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func editorFrameSize(in container: CGSize) -> CGSize {
        let baseAspect = max(0.2, min(4, element.size.height / max(1, element.size.width)))
        let maxWidth = max(220, container.width - 36)
        let maxHeight = max(260, container.height - 170)
        var width = min(390, maxWidth)
        var height = width * baseAspect
        if height > maxHeight {
            height = maxHeight
            width = height / baseAspect
        }
        return safeSize(CGSize(width: width, height: height), fallback: CGSize(width: 300, height: 360), context: "PhotoFrameAdjustment.frame")
    }

    private func resetTransform(conversionScale: CGFloat) {
        element.imageZoom = 1
        element.imageOffset = .zero
        displayZoom = 1
        zoomStart = 1
        displayOffset = .zero
        dragStartOffset = .zero
        _ = conversionScale
    }

    private func clampedDisplayOffset(_ proposed: CGSize, frameSize: CGSize) -> CGSize {
        guard let image = element.image, image.size.width > 0, image.size.height > 0 else { return .zero }
        let baseScale = element.imageFit == .fit
            ? min(frameSize.width / image.size.width, frameSize.height / image.size.height)
            : max(frameSize.width / image.size.width, frameSize.height / image.size.height)
        let renderedWidth = image.size.width * baseScale * max(1, displayZoom)
        let renderedHeight = image.size.height * baseScale * max(1, displayZoom)
        let limitX = max(0, (renderedWidth - frameSize.width) / 2)
        let limitY = max(0, (renderedHeight - frameSize.height) / 2)
        return CGSize(
            width: min(limitX, max(-limitX, safeCGFloat(proposed.width, fallback: 0, context: "photoEditorOffset.width"))),
            height: min(limitY, max(-limitY, safeCGFloat(proposed.height, fallback: 0, context: "photoEditorOffset.height")))
        )
    }
}

final class FixedCaretTextView: UITextView {
    override func caretRect(for position: UITextPosition) -> CGRect {
        var rect = super.caretRect(for: position)
        if let font {
            let targetHeight = font.lineHeight
            rect.origin.y += max(0, rect.height - targetHeight)
            rect.size.height = targetHeight
        }
        return rect
    }
}

private func editableOverlayLineSpacing(fontName: String, fontSize: CGFloat, lineHeight: CGFloat?) -> CGFloat {
    guard let lineHeight else { return 0 }
    let font = UIFont(name: fontName, size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
    return max(0, lineHeight - font.lineHeight)
}

struct LimitedTextView: UIViewRepresentable {
    @Binding var text: String
    let fontName: String
    let fontSize: CGFloat
    let color: UIColor
    let alignment: NSTextAlignment
    let characterLimit: Int
    let isFocused: Bool
    var lineHeight: CGFloat? = nil
    var maximumNumberOfLines: Int = 0
    var isEditable: Bool = true
    var onFocus: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil
    var onOverflow: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = FixedCaretTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isOpaque = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = maximumNumberOfLines != 1
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.autocorrectionType = .default
        textView.spellCheckingType = .no
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.autocapitalizationType = .none
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        textView.inputAccessoryView = context.coordinator.keyboardToolbar()
        applyStyle(to: textView)
        setText(text, in: textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        applyStyle(to: textView)

        if textView.text != text {
            let currentSelection = textView.selectedRange
            setText(text, in: textView)
            if currentSelection.location <= (textView.text as NSString).length {
                textView.selectedRange = currentSelection
            }
        }

        if isEditable && isFocused && !textView.isFirstResponder {
            DispatchQueue.main.async {
                textView.becomeFirstResponder()
            }
        } else if (!isEditable || !isFocused) && textView.isFirstResponder {
            DispatchQueue.main.async {
                textView.resignFirstResponder()
            }
        }
    }

    private func applyStyle(to textView: UITextView) {
        let font = resolvedUIFont
        textView.font = font
        textView.textColor = renderedTextColor
        textView.textAlignment = alignment
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.maximumNumberOfLines = maximumNumberOfLines
        textView.textContainer.lineBreakMode = maximumNumberOfLines == 1 ? .byClipping : .byWordWrapping
        textView.isScrollEnabled = maximumNumberOfLines != 1
        textView.isEditable = isEditable
        textView.isSelectable = isEditable
        textView.isUserInteractionEnabled = isEditable
        textView.autocorrectionType = .default
        textView.spellCheckingType = .no
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no

        textView.typingAttributes = textAttributes(font: font)
        refreshAttributedTextColorIfNeeded(in: textView)
    }

    private func setText(_ value: String, in textView: UITextView) {
        let font = resolvedUIFont
        if lineHeight != nil {
            textView.attributedText = NSAttributedString(
                string: value,
                attributes: textAttributes(font: font)
            )
        } else {
            textView.text = value
        }
        textView.font = font
        textView.textColor = renderedTextColor
        textView.textAlignment = alignment
        textView.typingAttributes = textAttributes(font: font)
    }

    private func textAttributes(font: UIFont) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: renderedTextColor
        ]

        if let lineHeight {
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = lineHeight
            paragraph.maximumLineHeight = lineHeight
            paragraph.alignment = alignment
            attributes[.paragraphStyle] = paragraph
        }

        return attributes
    }

    private var renderedTextColor: UIColor { color }

    private func refreshAttributedTextColorIfNeeded(in textView: UITextView) {
        guard lineHeight != nil, textView.attributedText.string == text else { return }
        let selectedRange = textView.selectedRange
        textView.attributedText = NSAttributedString(
            string: text,
            attributes: textAttributes(font: resolvedUIFont)
        )
        if selectedRange.location <= (textView.text as NSString).length {
            textView.selectedRange = NSRange(
                location: selectedRange.location,
                length: min(selectedRange.length, (textView.text as NSString).length - selectedRange.location)
            )
        }
    }

    private var resolvedUIFont: UIFont {
        if let font = UIFont(name: fontName, size: fontSize) {
            return font
        }
        return UIFont.systemFont(ofSize: fontSize)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: LimitedTextView

        init(_ parent: LimitedTextView) {
            self.parent = parent
        }

        func keyboardToolbar() -> UIToolbar {
            let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
            toolbar.items = [
                UIBarButtonItem.flexibleSpace(),
                UIBarButtonItem(
                    image: UIImage(systemName: "keyboard.chevron.compact.down"),
                    style: .plain,
                    target: self,
                    action: #selector(dismissKeyboardFromAccessory)
                )
            ]
            return toolbar
        }

        @objc private func dismissKeyboardFromAccessory() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            parent.onDismiss?()
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocus?()
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            let current = textView.text ?? ""
            guard let swiftRange = Range(range, in: current) else { return false }

            if parent.maximumNumberOfLines == 1 && replacement.contains("\n") {
                return false
            }

            let proposed = current.replacingCharacters(in: swiftRange, with: replacement)
            guard proposed.count <= parent.characterLimit else {
                let allowedCount = max(0, parent.characterLimit - (current.count - range.length))
                return acceptPartialReplacement(
                    replacement,
                    allowedCount: allowedCount,
                    current: current,
                    range: swiftRange,
                    textView: textView
                )
            }

            guard textFits(proposed, in: textView) else {
                return acceptPartialReplacement(
                    replacement,
                    allowedCount: replacement.count,
                    current: current,
                    range: swiftRange,
                    textView: textView
                )
            }

            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            let current = textView.text ?? ""
            if current.count <= parent.characterLimit, textFits(current, in: textView) {
                parent.text = current
                parent.applyStyle(to: textView)
            } else {
                let limited = fittedPrefix(of: current, in: textView)
                let overflow = String(current.dropFirst(limited.count))
                parent.setText(limited, in: textView)
                parent.text = limited
                if !overflow.isEmpty {
                    parent.onOverflow?(overflow)
                }
            }
        }

        private func acceptPartialReplacement(_ replacement: String, allowedCount: Int, current: String, range: Range<String.Index>, textView: UITextView) -> Bool {
            let cappedReplacement = String(replacement.prefix(max(0, allowedCount)))
            let acceptedReplacement = fittedReplacementPrefix(cappedReplacement, current: current, range: range, textView: textView)
            let limited = current.replacingCharacters(in: range, with: acceptedReplacement)
            let overflow = String(replacement.dropFirst(acceptedReplacement.count))

            parent.setText(limited, in: textView)
            parent.text = limited
            if !overflow.isEmpty {
                parent.onOverflow?(overflow)
            }
            return false
        }

        private func fittedReplacementPrefix(_ replacement: String, current: String, range: Range<String.Index>, textView: UITextView) -> String {
            var accepted = ""
            for character in replacement {
                let candidate = accepted + String(character)
                if parent.maximumNumberOfLines == 1 && candidate.contains("\n") {
                    break
                }
                let proposed = current.replacingCharacters(in: range, with: candidate)
                guard proposed.count <= parent.characterLimit, textFits(proposed, in: textView) else {
                    break
                }
                accepted = candidate
            }
            return accepted
        }

        private func fittedPrefix(of value: String, in textView: UITextView) -> String {
            var accepted = ""
            for character in value {
                let candidate = accepted + String(character)
                guard candidate.count <= parent.characterLimit, textFits(candidate, in: textView) else {
                    break
                }
                accepted = candidate
            }
            return accepted
        }

        private func textFits(_ value: String, in textView: UITextView) -> Bool {
            if parent.maximumNumberOfLines > 0 {
                guard textView.bounds.width > 0 else { return true }
                if parent.maximumNumberOfLines == 1 && value.contains("\n") { return false }
                let font = parent.resolvedUIFont
                let attributes = parent.textAttributes(font: font)
                let measuredWidth = parent.maximumNumberOfLines == 1 ? CGFloat.greatestFiniteMagnitude : textView.bounds.width
                let measured = (value as NSString).boundingRect(
                    with: CGSize(width: measuredWidth, height: CGFloat.greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes,
                    context: nil
                )
                let lineHeight = parent.lineHeight ?? font.lineHeight
                return measured.height <= (lineHeight * CGFloat(parent.maximumNumberOfLines)) + 1.0
                    && (parent.maximumNumberOfLines > 1 || measured.width <= textView.bounds.width + 0.5)
            }
            // Multi-line boxes are controlled by characterLimit and frame clipping.
            return true
        }
    }
}

struct EditableTextOverlay: View {
    @Binding var element: MagazineElement
    let page: MagazinePage
    let scaleX: CGFloat
    let scaleY: CGFloat
    let characterLimit: Int
    let visibleLineLimit: Int
    let onDismiss: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isScoreText {
                HStack(spacing: 0) {
                    TextField("", text: scoreBinding)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.plain)
                        .frame(width: max(14, element.fontSize * scaleY * 1.2))
                    Text("/10")
                }
                .font(.custom(resolvedFontName, size: editableTextFontSize))
                .foregroundStyle(Color(uiColor: page.textColor))
                .focused($isFocused)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: elementFrameAlignment)
                .padding(textEdgeInsets)
            } else {
                LimitedTextView(
                    text: limitedTextBinding,
                    fontName: resolvedFontName,
                    fontSize: editableTextFontSize,
                    color: page.textColor,
                    alignment: element.textAlignment.nsTextAlignment,
                    characterLimit: characterLimit,
                    isFocused: true,
                    lineHeight: editableTextLineHeight,
                    maximumNumberOfLines: editableTextMaximumNumberOfLines,
                    onFocus: {},
                    onDismiss: {
                        onDismiss()
                    }
                )
                .padding(textEdgeInsets)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: elementFrameAlignment)
                .background(Color.clear)
                .clipped()
            }
        }
        .background(Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .onAppear {
            isFocused = true
        }
    }

    private var limitedTextBinding: Binding<String> {
        Binding(
            get: { element.text },
            set: {
                if isAffirmationsWordField {
                    element.fontName = "Georgia"
                    element.fontSize = page.title == "GOALS · OUTLOOK" ? 14.4 : 12.96
                    element.isBold = false
                    element.textAlignment = .center
                    element.verticalAlignment = .middle
                }
                element.text = limitedText($0)
            }
        )
    }

    private var scoreBinding: Binding<String> {
        Binding(
            get: {
                if element.text.contains("___") { return "" }
                let digits = element.text.filter(\.isNumber)
                if digits == "10" { return "10" }
                return String(digits.prefix(1))
            },
            set: { newValue in
                let digits = String(newValue.filter(\.isNumber).prefix(2))
                guard let value = Int(digits) else {
                    element.text = "___ / 10"
                    return
                }
                element.text = "\(min(10, max(0, value)))/10"
            }
        )
    }

    private func limitedText(_ value: String) -> String {
        if isCinemaTicketShortField {
            return String(value.prefix(4))
        }
        if isCinemaWatchLogDateField {
            return String(value.prefix(5))
        }
        if isAffirmationsWordField {
            let words = value
                .split { $0.isWhitespace || $0.isNewline }
                .prefix(3)
            return words.joined(separator: " ")
        }
        if value.count <= characterLimit { return value }
        return String(value.prefix(characterLimit))
    }

    private var isCinemaTicketShortField: Bool {
        page.title == "CINEMA · TICKET STUB"
            && element.type == .text
            && element.size.width <= 15
            && abs(element.position.y - 137.0) < 2
    }

    private var isCinemaWatchLogDateField: Bool {
        page.title == "CINEMA · WATCH LOG"
            && element.type == .text
            && abs(element.position.x - 27.0) < 2
            && element.size.width > 20
    }

    private func formattedCinemaWatchDate(_ value: String) -> String {
        let digits = String(value.filter(\.isNumber).prefix(4))
        let first = digits.prefix(2)
        let second = digits.dropFirst(2).prefix(2)
        return "\(first.padding(toLength: 2, withPad: "_", startingAt: 0))/\(second.padding(toLength: 2, withPad: "_", startingAt: 0))"
    }

    private var isScoreText: Bool {
        let trimmed = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("/ 10") || trimmed.contains("/10")
    }

    private var resolvedFontName: String {
        if element.fontName == "Georgia" && element.isBold { return "Georgia-Bold" }
        if element.fontName == "Helvetica" && element.isBold { return "Helvetica-Bold" }
        return element.fontName
    }

    private var preservesOriginalTemplateStyle: Bool {
        !element.isEditableText && (isUnlockableTemplateText(element, page: page) || element.isTextLocked)
    }

    private var editableTextFontSize: CGFloat {
        if preservesOriginalTemplateStyle {
            return fittedOriginalTemplateFontSize
        }
        if element.isTextLocked {
            if element.type == .title {
                if element.fontSize <= 9.36 {
                    return max(5.6, element.fontSize * scaleY * 0.68)
                }
                return element.fontSize * scaleY * 0.56
            }
            return max(5.25, element.fontSize * scaleY * 0.99)
        }
        if isAffirmationsWordField { return element.fontSize * scaleY * 0.78 }
        if element.fontSize <= 4.0 { return element.fontSize * scaleY * 0.78 }
        if isCinemaTicketShortField { return element.fontSize * scaleY * 0.82 }
        if isCinemaWatchLogDateField { return element.fontSize * scaleY * 0.72 }
        if isSmallStandaloneField { return element.fontSize * scaleY * 0.40 }
        return element.type == .title ? element.fontSize * scaleY * 0.56 : element.fontSize * scaleY * 0.82
    }

    private var originalTemplateBaseFontSize: CGFloat {
        if element.type == .title {
            if element.fontSize <= 9.36 {
                return max(5.6, element.fontSize * scaleY * 0.68)
            }
            return element.fontSize * scaleY * 0.56
        }
        return max(5.25, element.fontSize * scaleY * 0.99)
    }

    private var fittedOriginalTemplateFontSize: CGFloat {
        let baseSize = originalTemplateBaseFontSize
        let minimumSize = max(3.2, baseSize * (element.type == .title ? 0.2 : 0.5))
        let inset = textEdgeInsets
        let availableWidth = max(1, element.size.width * scaleX - inset.leading - inset.trailing)
        let availableHeight = max(1, element.size.height * scaleY - inset.top - inset.bottom)
        let limit = max(1, editableTextMaximumNumberOfLines)
        let textToMeasure = element.text.isEmpty ? " " : element.text

        var candidate = baseSize
        while candidate > minimumSize {
            if originalTemplateTextFits(textToMeasure, fontSize: candidate, width: availableWidth, height: availableHeight, maximumLines: limit) {
                return candidate
            }
            candidate -= 0.25
        }
        return minimumSize
    }

    private func originalTemplateTextFits(_ text: String, fontSize: CGFloat, width: CGFloat, height: CGFloat, maximumLines: Int) -> Bool {
        let font = UIFont(name: resolvedFontName, size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = element.textAlignment.nsTextAlignment
        paragraph.lineBreakMode = .byWordWrapping
        let measured = (text as NSString).boundingRect(
            with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: font,
                .paragraphStyle: paragraph
            ],
            context: nil
        )
        let maxHeight = min(height, font.lineHeight * CGFloat(maximumLines) + 1.0)
        return measured.width <= width + 0.5 && measured.height <= maxHeight + 1.0
    }

    private var editableTextLineHeight: CGFloat? {
        if preservesOriginalTemplateStyle {
            return max(1, editableTextFontSize * 1.08)
        }
        if isSmallStandaloneField {
            return max(1, editableTextFontSize * 1.08)
        }
        return nil
    }

    private var editableTextMaximumNumberOfLines: Int {
        if preservesOriginalTemplateStyle {
            return max(1, visibleLineLimit)
        }
        return isSmallStandaloneField ? 1 : 0
    }

    private var isAffirmationsWordField: Bool {
        guard element.type == .title, element.isEditableText else { return false }
        return (page.title == "GOALS · OUTLOOK" && abs(element.position.x - 85.0) < 2 && abs(element.position.y - 91.17) < 2)
            || (page.title == "GOALS · AFFIRMATIONS" && abs(element.position.x - 85.0) < 2 && abs(element.position.y - 158.82) < 2)
    }

    private var isSmallStandaloneField: Bool {
        element.size.height <= 6.5
            && element.size.width <= 55
            && (element.text.contains("/") || element.text.count <= 24)
            && !isScoreText
    }

    private var textEdgeInsets: EdgeInsets {
        if isCinemaTicketShortField {
            return EdgeInsets()
        }
        return EdgeInsets(top: element.textInset.height * scaleY, leading: element.textInset.width * scaleX, bottom: element.textInset.height * scaleY, trailing: element.textInset.width * scaleX)
    }

    private var elementFrameAlignment: Alignment {
        if isCinemaTicketShortField {
            return .center
        }
        if !isScoreText {
            return .topLeading
        }
        switch (element.verticalAlignment, element.textAlignment) {
        case (.top, .left): return .topLeading
        case (.top, .center): return .top
        case (.top, .right): return .topTrailing
        case (.middle, .left): return .leading
        case (.middle, .center): return .center
        case (.middle, .right): return .trailing
        case (.bottom, .left): return .bottomLeading
        case (.bottom, .center): return .bottom
        case (.bottom, .right): return .bottomTrailing
        }
    }
}

struct ContinuousColumnTextOverlay: View {
    @Binding var element: MagazineElement
    let page: MagazinePage
    let scaleX: CGFloat
    let scaleY: CGFloat
    let layout: ContinuousColumnTextLayout
    let characterLimit: Int
    let isFocused: Bool
    var isReadOnly: Bool = false
    let onFocus: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        LimitedTextView(
            text: limitedTextBinding,
            fontName: layout.fontName,
            fontSize: layout.fontSize * scaleY,
            color: page.textColor,
            alignment: .left,
            characterLimit: characterLimit,
            isFocused: isFocused,
            lineHeight: layout.lineHeight * scaleY,
            isEditable: !isReadOnly,
            onFocus: onFocus,
            onDismiss: onDismiss
        )
        .padding(EdgeInsets(top: layout.textInset.height * scaleY, leading: layout.textInset.width * scaleX, bottom: 0, trailing: 0))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isReadOnly { onFocus() }
        }
    }

    private var limitedTextBinding: Binding<String> {
        Binding(
            get: { element.text },
            set: { value in
                element.fontName = layout.fontName
                element.fontSize = layout.fontSize
                element.isBold = false
                element.text = value.count <= characterLimit ? value : String(value.prefix(characterLimit))
            }
        )
    }
}

struct EditableLineOverlay: View {
    @Binding var element: MagazineElement
    let page: MagazinePage
    let scaleX: CGFloat
    let scaleY: CGFloat
    let characterLimit: Int
    let fontName: String
    let fontSize: CGFloat
    let isBold: Bool
    let isFocused: Bool
    let allowsWrapping: Bool
    let maximumNumberOfLines: Int
    let lineHeight: CGFloat?
    var isReadOnly: Bool = false
    let onFocus: () -> Void
    let onDismiss: () -> Void
    let onOverflow: (String) -> Void

    var body: some View {
        let resolvedFontSize = editableLineResolvedFontSize(fontSize, scaleY: scaleY)
        let resolvedLineHeight = lineHeight ?? (allowsWrapping ? max(1, fontSize * scaleY * 1.15) : max(1, fontSize * scaleY * 1.05))
        LimitedTextView(
            text: limitedTextBinding,
            fontName: resolvedFontName,
            fontSize: resolvedFontSize,
            color: page.textColor,
            alignment: .left,
            characterLimit: characterLimit,
            isFocused: isFocused,
            lineHeight: resolvedLineHeight,
            maximumNumberOfLines: maximumNumberOfLines,
            isEditable: !isReadOnly,
            onFocus: onFocus,
            onDismiss: onDismiss,
            onOverflow: onOverflow
        )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: allowsWrapping ? .topLeading : .bottomLeading)
            .background(Color.clear)
            .contentShape(Rectangle())
            .onTapGesture {
                if !isReadOnly { onFocus() }
            }
    }

    private var limitedTextBinding: Binding<String> {
        Binding(
            get: { element.text },
            set: { value in
                element.fontName = fontName
                element.fontSize = fontSize
                element.isBold = isBold
                element.text = value.count <= characterLimit ? value : String(value.prefix(characterLimit))
            }
        )
    }

    private var resolvedFontName: String {
        if fontName == "Georgia" && isBold { return "Georgia-Bold" }
        if fontName == "Helvetica" && isBold { return "Helvetica-Bold" }
        return fontName
    }
}

struct AppreciationTextBoxOverlay: View {
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    @Binding var element: MagazineElement
    let page: MagazinePage
    let scaleX: CGFloat
    let scaleY: CGFloat
    let isFocused: Bool
    let onFocus: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            if element.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isFocused {
                Text(appText("write here…", languageRaw))
                    .font(.custom("Helvetica", size: overlayFontSize * scaleY))
                    .foregroundStyle(Color(uiColor: page.textColor).opacity(0.65))
                    .padding(EdgeInsets(top: 2.0 * scaleY, leading: 2.8 * scaleX, bottom: 0, trailing: 0))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            LimitedTextView(
                text: limitedTextBinding,
                fontName: "Helvetica",
                fontSize: overlayFontSize * scaleY,
                color: page.textColor,
                alignment: .left,
                characterLimit: boxCharacterLimit,
                isFocused: isFocused,
                lineHeight: overlayLineHeight * scaleY,
                maximumNumberOfLines: maxVisibleLines,
                onFocus: onFocus,
                onDismiss: onDismiss
            )
            .padding(EdgeInsets(top: 2.0 * scaleY, leading: 2.8 * scaleX, bottom: 1.0 * scaleY, trailing: 2.0 * scaleX))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.clear)
            .contentShape(Rectangle())
            .onTapGesture(perform: onFocus)
        }
    }

    private var limitedTextBinding: Binding<String> {
        Binding(
            get: { element.text },
            set: { value in
                element.fontName = "Helvetica"
                element.fontSize = overlayFontSize
                element.isBold = false
                element.text = value.count <= boxCharacterLimit ? value : String(value.prefix(boxCharacterLimit))
            }
        )
    }

    private var overlayFontSize: CGFloat {
        page.title == "FAVOURITES · BEAUTY SHELF" ? 5.05 : (page.title == "FAVOURITES · APPS & INTERNET" ? 5.95 : 4.35)
    }

    private var overlayLineHeight: CGFloat {
        page.title == "FAVOURITES · BEAUTY SHELF" ? 5.85 : (page.title == "FAVOURITES · APPS & INTERNET" ? 6.75 : 5.15)
    }

    private var maxVisibleLines: Int {
        if page.title == "FAVOURITES · BEAUTY SHELF" { return 3 }
        if page.title == "FAVOURITES · APPS & INTERNET" { return 4 }
        if page.title == "READING · MINI REVIEWS" { return 2 }
        return max(1, Int((element.size.height - 3.0) / 5.15))
    }

    private var boxCharacterLimit: Int {
        let charactersPerLine = max(8, Int((element.size.width - 5.0) / 1.65))
        let extraCharacters: Int
        if page.title == "FAVOURITES · BEAUTY SHELF" {
            extraCharacters = 24
        } else if page.title == "FAVOURITES · APPS & INTERNET" {
            extraCharacters = 33
        } else {
            extraCharacters = 0
        }
        return charactersPerLine * maxVisibleLines + extraCharacters
    }
}

struct PowerPointElementView: View {
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    
    @Binding var element: MagazineElement
    let page: MagazinePage
    let editable: Bool
    let isSelected: Bool
    let scaleX: CGFloat
    let scaleY: CGFloat
    let suppressLineText: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            switch element.type {
            case .title:
                if shouldHideStreakNumber(element) {
                    EmptyView()
                } else if editable && isSelected && (element.isEditableText || isUnlockableTemplateText(element, page: page)) {
                    EmptyView()
                } else if isRatingText(element) {
                    RatingDisplayView(
                        element: element,
                        rowWidth: ratingRowWidth(for: element),
                        fontName: displayFontName,
                        fontSize: titleDisplayFontSize,
                        color: page.titleColor,
                        scaleX: scaleX
                    )
                } else {
                    Text(displayText)
                        .font(.custom(displayFontName, size: titleDisplayFontSize))
                        .foregroundStyle(Color(uiColor: page.titleColor))
                        .multilineTextAlignment(element.textAlignment.swiftUITextAlignment)
                        .minimumScaleFactor(0.2)
                        .lineLimit(2)
                        .padding(isSingleAwardStar ? EdgeInsets() : textEdgeInsets)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: elementFrameAlignment)
                        .clipped()
                }

            case .text:
                if shouldHideStreakNumber(element) {
                    EmptyView()
                } else if editable && isSelected && (element.isEditableText || isUnlockableTemplateText(element, page: page)) {
                    EmptyView()
                } else if isRatingText(element) {
                    RatingDisplayView(
                        element: element,
                        rowWidth: ratingRowWidth(for: element),
                        fontName: displayFontName,
                        fontSize: nonEditableTextFontSize,
                        color: page.textColor,
                        scaleX: scaleX
                    )
                } else {
                    Text(displayText)
                        .font(.custom(displayFontName, size: nonEditableTextFontSize))
                        .foregroundStyle(Color(uiColor: choiceOrRatingColor))
                        .multilineTextAlignment(element.textAlignment.swiftUITextAlignment)
                        .minimumScaleFactor(0.5)
                        .padding(textEdgeInsets)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: elementFrameAlignment)
                        .clipped()
                }

            case .image:
                ZStack {
                    if let image = element.image {
                        GeometryReader { imageGeo in
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: element.imageFit == .fit ? .fit : .fill)
                                .frame(width: imageGeo.size.width, height: imageGeo.size.height)
                                .scaleEffect(element.imageZoom)
                                .offset(element.imageOffset)
                                .clipped()
                        }
                    } else if !(page.sectionTitle == "Cover") {
                        Rectangle().stroke(Color(uiColor: page.textColor).opacity(0.35), lineWidth: 0.7)
                    }
                }
                .clipped()

            case .line:
                ZStack(alignment: .bottomLeading) {
                    GeometryReader { geo in
                        Path { path in
                            let y = geo.size.height / 2
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geo.size.width, y: y))
                        }
                        .stroke(Color(uiColor: page.textColor).opacity(0.35), lineWidth: max(0.5, min(1.0, scaleY * 0.7)))
                    }
                    if !editable && !suppressLineText && !element.text.isEmpty && !isContinuousColumnLine(element) {
                        Text(element.text)
                            .font(.custom(resolvedFontName, size: max(5.6, element.fontSize * scaleY * 1.05)))
                            .foregroundStyle(Color(uiColor: page.textColor))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity, maxHeight: max(11, element.fontSize * scaleY * 1.75), alignment: .bottomLeading)
                            .offset(y: -1)
                    }
                }

            case .box:
                if element.text == "__BLACK_FILL__" {
                    Rectangle().fill(Color(uiColor: page.titleColor))
                } else if shouldHideStreakInnerBox(element) {
                    EmptyView()
                } else if isStreakOuterCell(element), element.isMarked {
                    ZStack {
                        Rectangle().fill(Color(uiColor: page.accentSafe).opacity(0.12))
                        Rectangle().stroke(Color(uiColor: page.textColor).opacity(0.35), lineWidth: 0.7)
                        Text("♛")
                            .font(.system(size: max(14, element.size.height * scaleY * 0.95)))
                            .foregroundStyle(Color(uiColor: page.titleColor))
                    }
                } else if shouldHideStaticProgressPlaceholder(element) {
                    EmptyView()
                } else if isSliderBox(element) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(uiColor: page.textColor).opacity(0.10))
                            Capsule().stroke(Color(uiColor: page.textColor).opacity(0.60), lineWidth: 0.9)
                            Rectangle()
                                .fill(Color(uiColor: page.titleColor).opacity(0.62))
                                .frame(width: geo.size.width * CGFloat(element.interactionValue))
                                .clipShape(Capsule())
                            Circle()
                                .fill(Color(uiColor: page.titleColor))
                                .overlay(Circle().stroke(Color(uiColor: page.backgroundColor), lineWidth: 1.1))
                                .frame(width: max(7, geo.size.height * 1.8), height: max(7, geo.size.height * 1.8))
                                .offset(x: max(0, min(geo.size.width - max(7, geo.size.height * 1.8), geo.size.width * CGFloat(element.interactionValue) - max(7, geo.size.height * 1.8) / 2)))
                            if (element.text == "__SLIDER_HINT__" || element.text == "__BOOK_REVIEW_HINT__") && element.interactionValue <= 0.001 {
                                Text(appText(element.text == "__BOOK_REVIEW_HINT__" ? "swipe to review" : "slide to track progress", languageRaw))
                                    .font(.system(size: max(7, 3.4 * scaleY), weight: .regular))
                                    .foregroundStyle(Color(uiColor: page.textColor).opacity(0.45))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                    }
                } else if isChoiceContainerBox(element) {
                    Rectangle()
                        .fill(choiceContainerIsMarked(element) ? Color(uiColor: page.titleColor).opacity(0.18) : Color.clear)
                        .overlay(Rectangle().stroke(Color(uiColor: page.textColor).opacity(0.35), lineWidth: 0.7))
                } else if !editable && isStaticEditableBoxText(element) {
                    ZStack(alignment: .topLeading) {
                        Rectangle().stroke(Color(uiColor: page.textColor).opacity(0.35), lineWidth: 0.7)
                        if !element.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(element.text)
                                .font(.custom("Helvetica", size: staticEditableBoxFontSize * scaleY))
                                .foregroundStyle(Color(uiColor: page.textColor))
                                .lineSpacing(max(0, staticEditableBoxLineHeight * scaleY - staticEditableBoxFontSize * scaleY))
                                .padding(EdgeInsets(top: 2.0 * scaleY, leading: 2.8 * scaleX, bottom: 1.0 * scaleY, trailing: 2.0 * scaleX))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .clipped()
                        }
                    }
                } else {
                    Rectangle()
                        .fill(element.isMarked ? Color(uiColor: page.titleColor).opacity(0.25) : Color.clear)
                        .overlay(Rectangle().stroke(Color(uiColor: page.textColor).opacity(0.35), lineWidth: 0.7))
                }
            }
        }
    }

    private var titleDisplayFontSize: CGFloat {
        // Keep big editorial headings unchanged, but make small headers and micro-labels readable in review.
        if element.fontSize <= 9.36 {
            return max(5.6, element.fontSize * scaleY * 0.68)
        }
        return element.fontSize * scaleY * 0.56
    }

    private var choiceOrRatingColor: UIColor {
        if isChoiceText(element) { return page.titleColor }
        return page.textColor
    }

    private var isScoreText: Bool {
        let trimmed = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("/ 10") || trimmed.contains("/10")
    }

    private var displayText: String {
        let trimmed = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if page.title == "TINY WINS · TROPHY CABINET" && trimmed.uppercased() == "DATE" { return "" }
        if page.title == "CINEMA · TICKET STUB" && element.isEditableText && trimmed.isEmpty { return "" }
        if element.isEditableText && trimmed.isEmpty && !isScoreText && shouldShowEmptyEditablePlaceholder { return "write here…" }
        if trimmed.lowercased().contains("your headline") { return "" }
        if templateLogicText(trimmed) == "One month older and wiser." { return "" }
        if page.title == "MONTHLY RESET · LETTER",
           ["THIS MONTH", "This Month"].contains(templateLogicText(trimmed)) {
            return ""
        }
        if page.title == "RELATIONSHIPS · NEWEST OBSESSI", trimmed.lowercased() == "crush:", element.position.y > 200 {
            let targetX: CGFloat = element.position.x < 85 ? 46.36 : 123.64
            if let name = page.elements.first(where: {
                $0.type == .line
                    && abs($0.position.x - targetX) < 3
                    && abs($0.position.y - 79.41) < 1.5
            })?.text.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                return name
            }
        }
        return ratingTextIfNeeded(element.text)
    }

    private var shouldShowEmptyEditablePlaceholder: Bool {
        page.elements.contains { box in
            box.type == .box
                && box.size.width > element.size.width * 0.65
                && box.size.height > element.size.height
                && abs(element.position.x - box.position.x) <= box.size.width / 2
                && abs(element.position.y - box.position.y) <= box.size.height / 2
        }
    }

    private var displayFontName: String {
        if isChoiceText(element) { return element.isBold ? "Georgia-Bold" : "Georgia" }
        return resolvedFontName
    }

    private var limitedTextBinding: Binding<String> {
        Binding(
            get: { element.text },
            set: { element.text = limitedText($0) }
        )
    }

    private func limitedText(_ value: String) -> String {
        guard let wordLimit = wordLimit, wordLimit > 0 else { return value }
        let parts = value.split(whereSeparator: \.isWhitespace)
        guard parts.count > wordLimit else { return value }
        return parts.prefix(wordLimit).joined(separator: " ")
    }

    private var wordLimit: Int? {
        guard element.isEditableText else { return nil }
        let editableBox = page.elements
            .filter { box in
                box.type == .box
                    && box.size.width > element.size.width * 0.65
                    && box.size.height > element.size.height
                    && abs(element.position.x - box.position.x) <= box.size.width / 2
                    && abs(element.position.y - box.position.y) <= box.size.height / 2
            }
            .min { $0.size.width * $0.size.height < $1.size.width * $1.size.height }

        let availableSize = editableBox?.size ?? element.size
        let averageWordWidth = max(2.4, element.fontSize * 1.45)
        let lineHeight = max(4, element.fontSize * 1.35)
        let wordsPerLine = max(1, Int((availableSize.width - element.textInset.width * 2) / averageWordWidth))
        let lineCount = max(1, Int((availableSize.height - element.textInset.height * 2) / lineHeight))
        return max(1, wordsPerLine * lineCount)
    }

    private var nonEditableTextFontSize: CGFloat {
        if isChoiceText(element) { return max(12, element.fontSize * scaleY * 1.15) }
        if page.title == "HOBBIES · TRACKER" {
            let trimmed = templateLogicText(element.text).uppercased()
            if trimmed.hasPrefix("HOBBY ") { return max(5.8, element.fontSize * scaleY * 1.10) }
            if trimmed == "NAME" { return max(4.2, element.fontSize * scaleY * 0.92) }
        }
        // Keep saved user text the same size as the editor overlay.
        if element.isEditableText { return editableBodyDisplayFontSize }
        return max(5.25, element.fontSize * scaleY * 0.99)
    }

    private var editableBodyDisplayFontSize: CGFloat {
        let staticFontSize: CGFloat
        if isCinemaTicketShortField {
            staticFontSize = element.fontSize * scaleY * 0.82
        } else if isCinemaWatchLogDateField {
            staticFontSize = element.fontSize * scaleY * 0.72
        } else if staticEnclosingEditableBox != nil {
            staticFontSize = element.fontSize * scaleY
        } else if isSmallStandaloneEditableField {
            staticFontSize = element.fontSize * scaleY * 0.40
        } else if element.fontSize <= 4.0 {
            staticFontSize = element.fontSize * scaleY * 0.78
        } else {
            staticFontSize = element.fontSize * scaleY * 0.82
        }

        logTextFontConsistency(staticFontSize: staticFontSize)
        return staticFontSize
    }

    private var editableTextFontSize: CGFloat {
        element.type == .title ? titleDisplayFontSize : editableBodyDisplayFontSize
    }

    private var isCinemaTicketShortField: Bool {
        page.title == "CINEMA · TICKET STUB"
            && element.type == .text
            && element.size.width <= 15
            && abs(element.position.y - 137.0) < 2
    }

    private var isCinemaWatchLogDateField: Bool {
        page.title == "CINEMA · WATCH LOG"
            && element.type == .text
            && abs(element.position.x - 27.0) < 2
            && element.size.width > 20
    }

    private var isSmallStandaloneEditableField: Bool {
        guard staticEnclosingEditableBox == nil else { return false }
        return element.size.height <= 6.5
            && element.size.width <= 55
            && (element.text.contains("/") || element.text.count <= 24)
            && !isScoreText
    }

    private var staticEnclosingEditableBox: MagazineElement? {
        page.elements
            .filter { box in
                box.type == .box
                    && box.size.width > element.size.width * 0.65
                    && box.size.height > element.size.height
                    && abs(element.position.x - box.position.x) <= box.size.width / 2
                    && abs(element.position.y - box.position.y) <= box.size.height / 2
            }
            .min { $0.size.width * $0.size.height < $1.size.width * $1.size.height }
    }

    private func logTextFontConsistency(staticFontSize: CGFloat) {
        if element.text.lowercased().contains("hello") && !didLogHelloTextFontConsistency {
            didLogHelloTextFontConsistency = true
            print("hello editor displayed font size:", staticFontSize)
            print("hello static published font size:", staticFontSize)
        }

        guard !didLogTextFontConsistency,
              element.isEditableText,
              !element.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isEditablePlaceholderText(element.text)
        else { return }

        didLogTextFontConsistency = true
        print("text value:", element.text)
        print("stored element.fontSize:", element.fontSize)
        print("editable overlay fontSize:", staticFontSize)
        print("publish/static render fontSize:", staticFontSize)
    }

    private func isEditablePlaceholderText(_ text: String) -> Bool {
        let normalized = templateLogicText(text).lowercased()
        return normalized == "write here..."
            || normalized == "write here…"
            || normalized == "__/__"
            || normalized == "__ / __ / __"
            || normalized == "write one word here"
            || normalized == "one word"
            || normalized == "write your word"
            || normalized == "a few lines from you..."
            || normalized == "a few lines from you…"
            || normalized.contains("___")
    }

    private func ratingTextIfNeeded(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("♡") || trimmed.contains("♥") {
            let count = Int(element.interactionValue)
            let separator = text.contains("  ") ? "  " : " "
            return (1...5).map { $0 <= count ? "♥" : "♡" }.joined(separator: separator)
        }
        if trimmed.contains("☆") || trimmed.contains("★ ★") {
            let count = Int(element.interactionValue)
            let separator = text.contains("  ") ? "  " : " "
            return (1...5).map { $0 <= count ? "★" : "☆" }.joined(separator: separator)
        }
        if trimmed.hasSuffix("/31") || trimmed == "✦ /31" {
            return "✦ \(markedBoxesNear(element.position.y))/31"
        }
        if trimmed.contains("___ %") || trimmed.contains("__ %") || trimmed.contains("%") {
            return "+ \(progressPercentNear(element.position.y))%"
        }
        return text
    }

    private func markedBoxesNear(_ y: CGFloat) -> Int {
        if isStreakPage {
            return page.elements.filter { e in
                isStreakOuterCell(e) && e.isMarked
            }.count
        }
        if page.elements.contains(where: { $0.text == "How I spend" }) {
            let rowYs = page.elements
                .filter { $0.type == .box && $0.size.width <= 5 && $0.size.height > 8 && $0.position.y > y }
                .map(\.position.y)
            guard let rowY = rowYs.min(by: { abs($0 - y) < abs($1 - y) }) else { return 0 }
            return page.elements.filter { e in
                e.type == .box && e.isMarked && e.size.width <= 5 && e.size.height > 8 && abs(e.position.y - rowY) < 2
            }.count
        }
        return page.elements.filter { e in
            e.type == .box && e.isMarked && e.size.width <= 9 && e.size.height <= 12 && abs(e.position.y - y) < 12
        }.count
    }

    private func progressPercentNear(_ y: CGFloat) -> Int {
        let bars = page.elements.filter { e in
            e.type == .box && e.size.width > 95 && e.size.height <= 7 && abs(e.position.y - y) < 8
        }
        guard let bar = bars.min(by: { abs($0.position.y - y) < abs($1.position.y - y) }) else { return 0 }
        return Int(round(bar.interactionValue * 100))
    }

    private func shouldHideStaticProgressPlaceholder(_ e: MagazineElement) -> Bool {
        page.elements.contains { templateLogicText($0.text) == "Skill" || templateLogicText($0.text) == "Book of" } && e.type == .box && e.size.width > 20 && e.size.width <= 90 && e.size.height <= 7
    }

    private func isChoiceContainerBox(_ e: MagazineElement) -> Bool {
        guard e.type == .box, e.size.width >= 10, e.size.height > 7 else { return false }
        return page.elements.contains { t in
            isChoiceText(t) && abs(t.position.x - e.position.x) <= e.size.width / 2 && abs(t.position.y - e.position.y) <= e.size.height / 2
        }
    }

    private func choiceContainerIsMarked(_ e: MagazineElement) -> Bool {
        page.elements.contains { t in
            isChoiceText(t) && t.isMarked && abs(t.position.x - e.position.x) <= e.size.width / 2 && abs(t.position.y - e.position.y) <= e.size.height / 2
        }
    }

    private func isStaticEditableBoxText(_ e: MagazineElement) -> Bool {
        guard e.type == .box else { return false }
        switch page.title {
        case "RELATIONSHIPS · APPRECIATION":
            return e.size.width > 55 && e.size.height > 20 && e.position.y > 90 && e.position.y < 225
        case "FAVOURITES · BEAUTY SHELF":
            return e.size.width > 85 && e.size.height > 10 && [109.0, 196.0].contains { abs(e.position.y - $0) < 2.0 }
        case "FAVOURITES · APPS & INTERNET":
            return e.size.width > 60 && e.size.height > 20 && [128.5, 202.5].contains { abs(e.position.y - $0) < 2.0 }
        case "READING · MINI REVIEWS":
            return e.size.width > 90 && e.size.height > 10 && [119.25, 173.66, 228.08].contains { abs(e.position.y - $0) < 1.6 }
        default:
            return false
        }
    }

    private var staticEditableBoxFontSize: CGFloat {
        if page.title == "FAVOURITES · BEAUTY SHELF" { return 5.05 }
        if page.title == "FAVOURITES · APPS & INTERNET" { return 5.95 }
        if page.title == "READING · MINI REVIEWS" { return 4.65 }
        return 4.35
    }

    private var staticEditableBoxLineHeight: CGFloat {
        if page.title == "FAVOURITES · BEAUTY SHELF" { return 5.85 }
        if page.title == "FAVOURITES · APPS & INTERNET" { return 6.75 }
        if page.title == "READING · MINI REVIEWS" { return 5.35 }
        return 5.15
    }

    private var resolvedFontName: String {
        if element.fontName == "Georgia" && element.isBold { return "Georgia-Bold" }
        if element.fontName == "Helvetica" && element.isBold { return "Helvetica-Bold" }
        return element.fontName
    }

    private var isSingleAwardStar: Bool {
        element.text.trimmingCharacters(in: .whitespacesAndNewlines) == "★" && page.title == "TINY WINS · TROPHY CABINET"
    }

    private var textEdgeInsets: EdgeInsets {
        EdgeInsets(top: element.textInset.height * scaleY, leading: element.textInset.width * scaleX, bottom: element.textInset.height * scaleY, trailing: element.textInset.width * scaleX)
    }

    private var elementFrameAlignment: Alignment {
        if element.isEditableText && !isScoreText {
            return .topLeading
        }
        switch (element.verticalAlignment, element.textAlignment) {
        case (.top, .left): return .topLeading
        case (.top, .center): return .top
        case (.top, .right): return .topTrailing
        case (.middle, .left): return .leading
        case (.middle, .center): return .center
        case (.middle, .right): return .trailing
        case (.bottom, .left): return .bottomLeading
        case (.bottom, .center): return .bottom
        case (.bottom, .right): return .bottomTrailing
        }
    }

    private func isContinuousColumnLine(_ line: MagazineElement) -> Bool {
        isMagazineContinuousColumnLine(line, pageTitle: page.title)
    }

    private var isStreakPage: Bool { page.elements.contains { templateLogicText($0.text) == "Streak." } }
    private func isStreakOuterCell(_ element: MagazineElement) -> Bool { isStreakPage && element.type == .box && element.size.width > 12 && element.size.height > 10 && element.position.y > 70 && element.position.y < 160 }
    private func shouldHideStreakInnerBox(_ element: MagazineElement) -> Bool { isStreakPage && element.type == .box && element.size.width <= 8 && element.position.y > 70 && element.position.y < 160 }
    private func shouldHideStreakNumber(_ element: MagazineElement) -> Bool { isStreakPage && element.type == .text && Double(element.text.trimmingCharacters(in: .whitespacesAndNewlines)) != nil && element.position.y > 70 && element.position.y < 160 }
    private func isSliderBox(_ element: MagazineElement) -> Bool { element.type == .box && element.size.width > 95 && element.size.height <= 7 && element.text != "__BLACK_FILL__" }
    private func isChoiceText(_ element: MagazineElement) -> Bool { ["YES", "NO", "MAYBE", "NEVER", "Y", "N"].contains(templateLogicText(element.text).uppercased()) }
    private func isRatingText(_ element: MagazineElement) -> Bool {
        let t = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.contains("♡") || t.contains("♥") || t.contains("☆") || t.contains("★ ★")
    }
    private func ratingRowWidth(for element: MagazineElement) -> CGFloat {
        let symbols = element.text.filter { $0 == "♡" || $0 == "♥" || $0 == "☆" || $0 == "★" }.count
        guard symbols > 0 else { return element.size.width }
        let availableWidth = max(1, element.size.width - element.textInset.width * 2)
        return min(availableWidth, max(availableWidth * 0.72, CGFloat(symbols) * element.fontSize * 0.9))
    }
}

struct RatingDisplayView: View {
    let element: MagazineElement
    let rowWidth: CGFloat
    let fontName: String
    let fontSize: CGFloat
    let color: UIColor
    let scaleX: CGFloat

    var body: some View {
        GeometryReader { geo in
            let scaledRowWidth = rowWidth * scaleX
            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { index in
                    if isHeartRating {
                        Image(systemName: index <= Int(element.interactionValue) ? "heart.fill" : "heart")
                            .font(.system(size: fontSize, weight: .regular))
                            .foregroundStyle(Color(uiColor: color))
                            .frame(width: scaledRowWidth / 5, height: fontSize * 1.25)
                    } else {
                        Text(symbol(for: index))
                            .font(.custom(fontName, size: fontSize))
                            .foregroundStyle(Color(uiColor: color))
                            .frame(width: scaledRowWidth / 5)
                    }
                }
            }
            .frame(width: scaledRowWidth, alignment: .center)
            .position(x: rowMinX(in: geo.size.width, rowWidth: scaledRowWidth) + scaledRowWidth / 2, y: geo.size.height / 2)
        }
        .clipped()
    }

    private func symbol(for index: Int) -> String {
        let filledCount = Int(element.interactionValue)
        return index <= filledCount ? "★" : "☆"
    }

    private var isHeartRating: Bool {
        element.text.contains("♡") || element.text.contains("♥")
    }

    private func rowMinX(in width: CGFloat, rowWidth: CGFloat) -> CGFloat {
        let inset = element.textInset.width * scaleX
        switch element.textAlignment {
        case .left: return inset
        case .center: return (width - rowWidth) / 2
        case .right: return width - inset - rowWidth
        }
    }
}

private extension MagazinePage {
    var accentSafe: UIColor { titleColor }
}

enum MagazineTemplateFactory {

    static func todayDateText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd / MM / yyyy"
        return "DATE  \(formatter.string(from: Date()))"
    }

    static func makeIssue(sections: [IssueSection], scheme: PenPalColourScheme) -> [MagazinePage] {
        var pages: [MagazinePage] = []
        pages.append(templatePage(0, sectionTitle: "Cover", scheme: scheme))
        pages.append(templatePage(1, sectionTitle: "Contents", scheme: scheme))
        for section in sections {
            for slideIndex in slideIndices(for: section.type) { pages.append(templatePage(slideIndex, sectionTitle: section.title, scheme: scheme)) }
        }
        pages.append(templatePage(58, sectionTitle: "Back", scheme: scheme))
        return pages
    }

    static func renumberPages(_ pages: inout [MagazinePage]) {
        guard !pages.isEmpty else { return }

        for index in pages.indices {
            let visiblePage = index + 1
            for elementIndex in pages[index].elements.indices {
                let text = pages[index].elements[elementIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.hasPrefix("№01 ·") {
                    pages[index].elements[elementIndex].text = "№01 · \(String(format: "%02d", visiblePage))"
                } else if pages[index].title == "TINY WINS · THE DAILY ME" && text.hasPrefix("NO.") {
                    pages[index].elements[elementIndex].text = "NO. \(String(format: "%02d", visiblePage))"
                } else if pages[index].title == "TINY WINS · THE DAILY ME" && text.hasPrefix("DATE") {
                    pages[index].elements[elementIndex].text = todayDateText()
                } else if pages[index].elements[elementIndex].position.y > 240,
                          pages[index].elements[elementIndex].position.x > 120,
                          Int(text) != nil {
                    pages[index].elements[elementIndex].text = String(format: "%02d", visiblePage)
                }
            }
        }

        let sectionStarts = firstPageIndexBySection(in: pages)
        renumberSectionCovers(&pages, sectionStarts: sectionStarts)
        updateContentsPage(&pages, sectionStarts: sectionStarts)
    }

    private static func firstPageIndexBySection(in pages: [MagazinePage]) -> [(title: String, pageIndex: Int)] {
        var seen: Set<String> = []
        var starts: [(String, Int)] = []
        for (index, page) in pages.enumerated() {
            guard !["Cover", "Contents", "Back"].contains(page.sectionTitle) else { continue }
            guard !seen.contains(page.sectionTitle) else { continue }
            seen.insert(page.sectionTitle)
            starts.append((page.sectionTitle, index))
        }
        return starts
    }

    private static func renumberSectionCovers(_ pages: inout [MagazinePage], sectionStarts: [(title: String, pageIndex: Int)]) {
        for (sectionIndex, start) in sectionStarts.enumerated() where pages.indices.contains(start.pageIndex) {
            let sectionNumber = String(format: "%02d", sectionIndex + 1)
            pages[start.pageIndex].title = sectionNumber
            for elementIndex in pages[start.pageIndex].elements.indices {
                let element = pages[start.pageIndex].elements[elementIndex]
                let trimmed = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if element.type == .title, Int(trimmed) != nil {
                    pages[start.pageIndex].elements[elementIndex].text = sectionNumber
                } else if element.type == .text, trimmed.hasPrefix("Nº ") {
                    pages[start.pageIndex].elements[elementIndex].text = "Nº \(sectionNumber) · \(start.title.uppercased())"
                }
            }
        }
    }

    private static func updateContentsPage(_ pages: inout [MagazinePage], sectionStarts: [(title: String, pageIndex: Int)]) {
        guard let contentsIndex = pages.firstIndex(where: { $0.sectionTitle == "Contents" || $0.title == "CONTENTS · IN THIS ISSUE" }) else { return }
        let rowYs: [CGFloat] = [76.47, 89.7, 102.94, 116.17, 129.41, 142.64, 155.88, 169.12, 182.35, 195.59, 208.82]
        let dotLeader = "· · · · · · · · · · · · · ·"

        for (rowIndex, rowY) in rowYs.enumerated() {
            let row = rowElements(in: pages[contentsIndex], at: rowY)
            let hasSection = rowIndex < sectionStarts.count
            if let numberIndex = row.numberIndex {
                pages[contentsIndex].elements[numberIndex].text = hasSection ? String(format: "%02d", rowIndex + 1) : ""
            }
            if let titleIndex = row.titleIndex {
                pages[contentsIndex].elements[titleIndex].text = hasSection ? contentsDisplayTitle(sectionStarts[rowIndex].title) : ""
            }
            if let dotsIndex = row.dotsIndex {
                pages[contentsIndex].elements[dotsIndex].text = hasSection ? dotLeader : ""
            }
            if let pageIndex = row.pageIndex {
                pages[contentsIndex].elements[pageIndex].text = hasSection ? String(format: "%02d", sectionStarts[rowIndex].pageIndex + 1) : ""
            }
        }
    }

    private static func contentsDisplayTitle(_ title: String) -> String {
        switch title {
        case "Affirmationen & Ziele":
            return "Ziele"
        default:
            return title
        }
    }

    private static func rowElements(in page: MagazinePage, at y: CGFloat) -> (numberIndex: Int?, titleIndex: Int?, dotsIndex: Int?, pageIndex: Int?) {
        let rowIndices = page.elements.indices.filter { abs(page.elements[$0].position.y - y) < 1.2 }
        let numberIndex = rowIndices.first { page.elements[$0].type == .title && page.elements[$0].position.x < 35 }
        let titleIndex = rowIndices.first { page.elements[$0].type == .title && page.elements[$0].position.x > 35 }
        let dotsIndex = rowIndices.first { page.elements[$0].type == .text && page.elements[$0].position.x > 70 && page.elements[$0].position.x < 130 }
        let pageIndex = rowIndices.first { page.elements[$0].type == .text && page.elements[$0].position.x > 145 }
        return (numberIndex, titleIndex, dotsIndex, pageIndex)
    }

    private static func slideIndices(for type: IssueSectionType) -> [Int] {
        switch type {
        case .monthlyReset: return [2, 3, 4, 5, 6, 7, 8]
        case .tinyWins: return [9, 10, 11, 12, 13]
        case .hobbies: return [14, 15, 16, 17, 18]
        case .relationships: return [19, 20, 21, 22, 23, 24]
        case .playlist: return [26, 27, 28, 29, 30]
        case .cinema: return [31, 32, 33, 34]
        case .reading: return [35, 36, 37, 38, 39]
        case .food: return [40, 41, 43]
        case .travel: return [44, 45, 46]
        case .favourites: return [48, 49, 50, 51]
        case .affirmations: return [53, 54, 55, 56]
        }
    }
    private static func templatePage(_ index: Int, sectionTitle: String, scheme: PenPalColourScheme) -> MagazinePage {
        switch index {
        case 0:
            return MagazinePage(title: "ISSUE №01 · 2026", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .box, text: "__BLACK_FILL__", position: CGPoint(x: 85.0, y: 20.59), size: CGSize(width: 170.0, height: 41.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "ISSUE №01 · 2026", position: CGPoint(x: 85.0, y: 13.96), size: CGSize(width: 145.27, height: 7.35), fontSize: 7.26, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 20.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 20.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "STAY PART OF YOUR FRIENDS' STORIES", position: CGPoint(x: 85.0, y: 29.41), size: CGSize(width: 145.27, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 85.0, y: 121.56), size: CGSize(width: 170.0, height: 47.06), fontSize: 69.12, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 217.65), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "LIVE · CAPTURE · SHARE", position: CGPoint(x: 85.0, y: 223.53), size: CGSize(width: 145.27, height: 5.88), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "MADE WITH LOVE", position: CGPoint(x: 85.0, y: 230.88), size: CGSize(width: 145.27, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 85.0, y: 165.0), size: CGSize(width: 118.0, height: 66.0), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false)
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 1:
            return MagazinePage(title: "CONTENTS · IN THIS ISSUE", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "CONTENTS · IN THIS ISSUE", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 02", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "Contents.", position: CGPoint(x: 85.0, y: 41.17), size: CGSize(width: 145.27, height: 32.35), fontSize: 34.56, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "In this issue.", position: CGPoint(x: 85.0, y: 58.82), size: CGSize(width: 145.27, height: 8.82), fontSize: 7.26, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 66.18), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "01", position: CGPoint(x: 20.09, y: 76.47), size: CGSize(width: 15.45, height: 11.76), fontSize: 12.96, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Monthly Reset", position: CGPoint(x: 83.45, y: 76.47), size: CGSize(width: 108.18, height: 11.76), fontSize: 10.08, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "· · · · · · · · · · · · · · ·", position: CGPoint(x: 86.54, y: 77.06), size: CGSize(width: 114.36, height: 11.76), fontSize: 7.26, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "03", position: CGPoint(x: 151.45, y: 76.47), size: CGSize(width: 12.36, height: 11.76), fontSize: 7.63, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "02", position: CGPoint(x: 20.09, y: 89.7), size: CGSize(width: 15.45, height: 11.76), fontSize: 12.96, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Tiny Wins", position: CGPoint(x: 83.45, y: 89.7), size: CGSize(width: 108.18, height: 11.76), fontSize: 10.08, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "· · · · · · · · · · · · · · ·", position: CGPoint(x: 86.54, y: 90.29), size: CGSize(width: 114.36, height: 11.76), fontSize: 7.26, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "08", position: CGPoint(x: 151.45, y: 89.7), size: CGSize(width: 12.36, height: 11.76), fontSize: 7.63, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "03", position: CGPoint(x: 20.09, y: 102.94), size: CGSize(width: 15.45, height: 11.76), fontSize: 12.96, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Hobbies", position: CGPoint(x: 83.45, y: 102.94), size: CGSize(width: 108.18, height: 11.76), fontSize: 10.08, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "· · · · · · · · · · · · · · ·", position: CGPoint(x: 86.54, y: 103.53), size: CGSize(width: 114.36, height: 11.76), fontSize: 7.26, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "13", position: CGPoint(x: 151.45, y: 102.94), size: CGSize(width: 12.36, height: 11.76), fontSize: 7.63, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "04", position: CGPoint(x: 20.09, y: 116.17), size: CGSize(width: 15.45, height: 11.76), fontSize: 12.96, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Relationships", position: CGPoint(x: 83.45, y: 116.17), size: CGSize(width: 108.18, height: 11.76), fontSize: 10.08, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "· · · · · · · · · · · · · · ·", position: CGPoint(x: 86.54, y: 116.76), size: CGSize(width: 114.36, height: 11.76), fontSize: 7.26, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "18", position: CGPoint(x: 151.45, y: 116.17), size: CGSize(width: 12.36, height: 11.76), fontSize: 7.63, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "05", position: CGPoint(x: 20.09, y: 129.41), size: CGSize(width: 15.45, height: 11.76), fontSize: 12.96, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Playlist & Music", position: CGPoint(x: 83.45, y: 129.41), size: CGSize(width: 108.18, height: 11.76), fontSize: 10.08, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "· · · · · · · · · · · · · · ·", position: CGPoint(x: 86.54, y: 130.0), size: CGSize(width: 114.36, height: 11.76), fontSize: 7.26, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "23", position: CGPoint(x: 151.45, y: 129.41), size: CGSize(width: 12.36, height: 11.76), fontSize: 7.63, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "06", position: CGPoint(x: 20.09, y: 142.64), size: CGSize(width: 15.45, height: 11.76), fontSize: 12.96, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Cinema", position: CGPoint(x: 83.45, y: 142.64), size: CGSize(width: 108.18, height: 11.76), fontSize: 10.08, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "· · · · · · · · · · · · · · ·", position: CGPoint(x: 86.54, y: 143.23), size: CGSize(width: 114.36, height: 11.76), fontSize: 7.26, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "28", position: CGPoint(x: 151.45, y: 142.64), size: CGSize(width: 12.36, height: 11.76), fontSize: 7.63, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "07", position: CGPoint(x: 20.09, y: 155.88), size: CGSize(width: 15.45, height: 11.76), fontSize: 12.96, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Reading", position: CGPoint(x: 83.45, y: 155.88), size: CGSize(width: 108.18, height: 11.76), fontSize: 10.08, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "· · · · · · · · · · · · · · ·", position: CGPoint(x: 86.54, y: 156.47), size: CGSize(width: 114.36, height: 11.76), fontSize: 7.26, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "33", position: CGPoint(x: 151.45, y: 155.88), size: CGSize(width: 12.36, height: 11.76), fontSize: 7.63, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "08", position: CGPoint(x: 20.09, y: 169.12), size: CGSize(width: 15.45, height: 11.76), fontSize: 12.96, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Food & Recipes", position: CGPoint(x: 83.45, y: 169.12), size: CGSize(width: 108.18, height: 11.76), fontSize: 10.08, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "· · · · · · · · · · · · · · ·", position: CGPoint(x: 86.54, y: 169.7), size: CGSize(width: 114.36, height: 11.76), fontSize: 7.26, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "38", position: CGPoint(x: 151.45, y: 169.12), size: CGSize(width: 12.36, height: 11.76), fontSize: 7.63, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "09", position: CGPoint(x: 20.09, y: 182.35), size: CGSize(width: 15.45, height: 11.76), fontSize: 12.96, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Travel & Places", position: CGPoint(x: 83.45, y: 182.35), size: CGSize(width: 108.18, height: 11.76), fontSize: 10.08, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "· · · · · · · · · · · · · · ·", position: CGPoint(x: 86.54, y: 182.94), size: CGSize(width: 114.36, height: 11.76), fontSize: 7.26, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "43", position: CGPoint(x: 151.45, y: 182.35), size: CGSize(width: 12.36, height: 11.76), fontSize: 7.63, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "10", position: CGPoint(x: 20.09, y: 195.59), size: CGSize(width: 15.45, height: 11.76), fontSize: 12.96, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Favourites", position: CGPoint(x: 83.45, y: 195.59), size: CGSize(width: 108.18, height: 11.76), fontSize: 10.08, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "· · · · · · · · · · · · · · ·", position: CGPoint(x: 86.54, y: 196.17), size: CGSize(width: 114.36, height: 11.76), fontSize: 7.26, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "48", position: CGPoint(x: 151.45, y: 195.59), size: CGSize(width: 12.36, height: 11.76), fontSize: 7.63, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "11", position: CGPoint(x: 20.09, y: 208.82), size: CGSize(width: 15.45, height: 11.76), fontSize: 12.96, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Affirmations & Goals", position: CGPoint(x: 83.45, y: 208.82), size: CGSize(width: 108.18, height: 11.76), fontSize: 10.08, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "· · · · · · · · · · · · · · ·", position: CGPoint(x: 86.54, y: 209.41), size: CGSize(width: 114.36, height: 11.76), fontSize: 7.26, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "53", position: CGPoint(x: 151.45, y: 208.82), size: CGSize(width: 12.36, height: 11.76), fontSize: 7.63, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "02", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 2:
            return MagazinePage(title: "01", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "01", position: CGPoint(x: 117.45, y: 35.29), size: CGSize(width: 80.36, height: 47.06), fontSize: 63.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "SECTION", position: CGPoint(x: 43.27, y: 17.65), size: CGSize(width: 61.82, height: 5.88), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 35.54, y: 25.0), size: CGSize(width: 46.36, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "Monthly Reset.", position: CGPoint(x: 85.0, y: 122.06), size: CGSize(width: 145.27, height: 64.71), fontSize: 43.2, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 41.41, y: 157.35), size: CGSize(width: 58.11, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "A slow audit of the days behind — what stayed, what shifted, what is worth remembering.", position: CGPoint(x: 85.0, y: 176.47), size: CGSize(width: 145.27, height: 29.41), fontSize: 9.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 223.53), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "Nº 01 · MONTHLY RESET", position: CGPoint(x: 85.0, y: 230.15), size: CGSize(width: 145.27, height: 7.35), fontSize: 6.45, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 85.0, y: 238.23), size: CGSize(width: 145.27, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 3:
            return MagazinePage(title: "MONTHLY RESET · DAILY REFLECTI", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "MONTHLY RESET · DAILY REFLECTION", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 03", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "END OF MONTH, HONESTLY.", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "End of", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 27.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "month", position: CGPoint(x: 85.0, y: 60.3), size: CGSize(width: 145.27, height: 32.35), fontSize: 27.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 67.65), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "DATE", position: CGPoint(x: 27.81, y: 72.6), size: CGSize(width: 30.91, height: 6.4), fontSize: 6.4, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 37.09, y: 80.2), size: CGSize(width: 49.45, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "", position: CGPoint(x: 37.09, y: 84.0), size: CGSize(width: 49.45, height: 6.8), fontSize: 7.2, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "FEELING", position: CGPoint(x: 110.0, y: 72.6), size: CGSize(width: 83.0, height: 6.4), fontSize: 6.4, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 108.0, y: 80.2), size: CGSize(width: 74.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "one word", position: CGPoint(x: 108.0, y: 84.0), size: CGSize(width: 74.0, height: 6.8), fontSize: 7.2, fontName: "Helvetica", isBold: false, isEditableText: true, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "ONE GOOD THING", position: CGPoint(x: 85.0, y: 93.2), size: CGSize(width: 145.27, height: 6.8), fontSize: 7.2, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 111.91), size: CGSize(width: 145.27, height: 25.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "write here…", position: CGPoint(x: 85.0, y: 104.7), size: CGSize(width: 139.09, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: true, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "ONE HARD THING", position: CGPoint(x: 85.0, y: 132.9), size: CGSize(width: 145.27, height: 6.8), fontSize: 7.2, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 151.62), size: CGSize(width: 145.27, height: 25.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "write here…", position: CGPoint(x: 85.0, y: 144.41), size: CGSize(width: 139.09, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: true, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "ONE THING I LEARNED", position: CGPoint(x: 85.0, y: 172.6), size: CGSize(width: 145.27, height: 6.8), fontSize: 7.2, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 191.32), size: CGSize(width: 145.27, height: 25.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "write here…", position: CGPoint(x: 85.0, y: 184.12), size: CGSize(width: 139.09, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: true, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "ONE THING I’M GRATEFUL FOR", position: CGPoint(x: 85.0, y: 211.8), size: CGSize(width: 145.27, height: 6.8), fontSize: 7.2, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 228.5), size: CGSize(width: 145.27, height: 21.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),

            MagazineElement(type: .text, text: "write here…", position: CGPoint(x: 85.0, y: 223.82), size: CGSize(width: 139.09, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: true, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "03", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 4:
            return MagazinePage(title: "MONTHLY RESET", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "MONTHLY RESET", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 04", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "HIGHS & LOWS", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "How the month", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 23.04, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "shaped me.", position: CGPoint(x: 85.0, y: 57.36), size: CGSize(width: 145.27, height: 32.35), fontSize: 23.04, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 64.71), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "THE HIGHS", position: CGPoint(x: 46.36, y: 71.77), size: CGSize(width: 68.0, height: 5.29), fontSize: 7.0, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 46.36, y: 75.0), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 46.36, y: 84.71), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 46.36, y: 93.53), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 46.36, y: 102.35), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 46.36, y: 111.18), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 46.36, y: 120.0), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 46.36, y: 150.0), size: CGSize(width: 68.0, height: 47.06), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 46.36, y: 173.53), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  a high moment", position: CGPoint(x: 46.36, y: 168.53), size: CGSize(width: 68.0, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "THE LOWS", position: CGPoint(x: 123.64, y: 71.77), size: CGSize(width: 68.0, height: 5.29), fontSize: 7.0, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 123.64, y: 75.0), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 123.64, y: 84.71), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 123.64, y: 93.53), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 123.64, y: 102.35), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 123.64, y: 111.18), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 123.64, y: 120.0), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 123.64, y: 150.0), size: CGSize(width: 68.0, height: 47.06), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 123.64, y: 173.53), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  a low moment", position: CGPoint(x: 123.64, y: 168.53), size: CGSize(width: 68.0, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "MONTH IN ONE FRAME", position: CGPoint(x: 85.0, y: 182.06), size: CGSize(width: 145.27, height: 5.29), fontSize: 7.0, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 185.29), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 85.0, y: 208.83), size: CGSize(width: 145.27, height: 41.18), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 229.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  one image that holds the whole month", position: CGPoint(x: 85.0, y: 224.42), size: CGSize(width: 145.27, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "04", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 5:
            return MagazinePage(title: "MONTHLY RESET · GRATITUDE", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "MONTHLY RESET · GRATITUDE", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 05", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "GRATITUDE", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "What I am", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 23.04, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "grateful for.", position: CGPoint(x: 85.0, y: 57.36), size: CGSize(width: 145.27, height: 32.35), fontSize: 23.04, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 64.71), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "✦", position: CGPoint(x: 16.99, y: 73.53), size: CGSize(width: 12.0, height: 12.0), fontSize: 9.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 0, height: 0)),
            MagazineElement(type: .title, text: "small things", position: CGPoint(x: 51.0, y: 73.53), size: CGSize(width: 58.73, height: 8.82), fontSize: 10.08, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 46.36, y: 79.41), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "1.", position: CGPoint(x: 16.99, y: 89.7), size: CGSize(width: 9.27, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 51.0, y: 92.06), size: CGSize(width: 58.73, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "2.", position: CGPoint(x: 16.99, y: 101.47), size: CGSize(width: 9.27, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 51.0, y: 103.82), size: CGSize(width: 58.73, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "3.", position: CGPoint(x: 16.99, y: 113.23), size: CGSize(width: 9.27, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 51.0, y: 115.59), size: CGSize(width: 58.73, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "4.", position: CGPoint(x: 16.99, y: 125.0), size: CGSize(width: 9.27, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 51.0, y: 127.35), size: CGSize(width: 58.73, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "5.", position: CGPoint(x: 16.99, y: 136.76), size: CGSize(width: 9.27, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 51.0, y: 139.12), size: CGSize(width: 58.73, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "✦", position: CGPoint(x: 94.28, y: 73.53), size: CGSize(width: 12.0, height: 12.0), fontSize: 9.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 0, height: 0)),
            MagazineElement(type: .title, text: "people", position: CGPoint(x: 128.28, y: 73.53), size: CGSize(width: 58.73, height: 8.82), fontSize: 10.08, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 123.64, y: 79.41), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "1.", position: CGPoint(x: 94.28, y: 89.7), size: CGSize(width: 9.27, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 128.28, y: 92.06), size: CGSize(width: 58.73, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "2.", position: CGPoint(x: 94.28, y: 101.47), size: CGSize(width: 9.27, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 128.28, y: 103.82), size: CGSize(width: 58.73, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "3.", position: CGPoint(x: 94.28, y: 113.23), size: CGSize(width: 9.27, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 128.28, y: 115.59), size: CGSize(width: 58.73, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "4.", position: CGPoint(x: 94.28, y: 125.0), size: CGSize(width: 9.27, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 128.28, y: 127.35), size: CGSize(width: 58.73, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "5.", position: CGPoint(x: 94.28, y: 136.76), size: CGSize(width: 9.27, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 128.28, y: 139.12), size: CGSize(width: 58.73, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "✦", position: CGPoint(x: 16.99, y: 157.35), size: CGSize(width: 12.0, height: 12.0), fontSize: 9.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 0, height: 0)),
            MagazineElement(type: .title, text: "moments", position: CGPoint(x: 51.0, y: 157.35), size: CGSize(width: 58.73, height: 8.82), fontSize: 10.08, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 46.36, y: 163.24), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "1.", position: CGPoint(x: 16.99, y: 173.53), size: CGSize(width: 9.27, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 51.0, y: 175.88), size: CGSize(width: 58.73, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "2.", position: CGPoint(x: 16.99, y: 185.29), size: CGSize(width: 9.27, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 51.0, y: 187.65), size: CGSize(width: 58.73, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "3.", position: CGPoint(x: 16.99, y: 197.06), size: CGSize(width: 9.27, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 51.0, y: 199.41), size: CGSize(width: 58.73, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "4.", position: CGPoint(x: 16.99, y: 208.82), size: CGSize(width: 9.27, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 51.0, y: 211.18), size: CGSize(width: 58.73, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "5.", position: CGPoint(x: 16.99, y: 220.59), size: CGSize(width: 9.27, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 51.0, y: 222.94), size: CGSize(width: 58.73, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "✦", position: CGPoint(x: 94.28, y: 157.35), size: CGSize(width: 12.0, height: 12.0), fontSize: 9.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 0, height: 0)),
            MagazineElement(type: .title, text: "health & wellness", position: CGPoint(x: 128.28, y: 157.35), size: CGSize(width: 58.73, height: 8.82), fontSize: 10.08, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 123.64, y: 163.24), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "1.", position: CGPoint(x: 94.28, y: 173.53), size: CGSize(width: 9.27, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 128.28, y: 175.88), size: CGSize(width: 58.73, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "2.", position: CGPoint(x: 94.28, y: 185.29), size: CGSize(width: 9.27, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 128.28, y: 187.65), size: CGSize(width: 58.73, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "3.", position: CGPoint(x: 94.28, y: 197.06), size: CGSize(width: 9.27, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 128.28, y: 199.41), size: CGSize(width: 58.73, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "4.", position: CGPoint(x: 94.28, y: 208.82), size: CGSize(width: 9.27, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 128.28, y: 211.18), size: CGSize(width: 58.73, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "5.", position: CGPoint(x: 94.28, y: 220.59), size: CGSize(width: 9.27, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 128.28, y: 222.94), size: CGSize(width: 58.73, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "05", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 6:
            return MagazinePage(title: "MONTHLY RESET · LETTER", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "MONTHLY RESET · LETTER", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 06", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "A LETTER", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Dear month,", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "a letter to the month from me.", position: CGPoint(x: 85.0, y: 49.27), size: CGSize(width: 145.27, height: 7.35), fontSize: 7.63, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 55.88), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 134.45, y: 85.29), size: CGSize(width: 46.36, height: 52.94), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 134.45, y: 79.42), size: CGSize(width: 34.0, height: 32.35), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 134.45, y: 79.42), size: CGSize(width: 34.0, height: 32.35), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "THIS MONTH", position: CGPoint(x: 134.45, y: 96.5), size: CGSize(width: 34.0, height: 5.0), fontSize: 4.32, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 0, height: 0)),
            MagazineElement(type: .text, text: "This Month", position: CGPoint(x: 134.45, y: 106.8), size: CGSize(width: 46.36, height: 5.88), fontSize: 5.1, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 34.0, y: 85.29), size: CGSize(width: 43.27, height: 52.94), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 34.0, y: 111.76), size: CGSize(width: 43.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  self portrait", position: CGPoint(x: 34.0, y: 106.77), size: CGSize(width: 43.27, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "THE FIRST THING I WANT TO REMEMBER…", position: CGPoint(x: 85.0, y: 120.3), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 138.24), size: CGSize(width: 145.27, height: 29.41), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "write here…", position: CGPoint(x: 85.0, y: 128.82), size: CGSize(width: 139.09, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: true, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "WHAT I LEARNED ABOUT MYSELF…", position: CGPoint(x: 85.0, y: 158.53), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 176.47), size: CGSize(width: 145.27, height: 29.41), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "write here…", position: CGPoint(x: 85.0, y: 167.06), size: CGSize(width: 139.09, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: true, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "WHAT I AM READY TO CHANGE…", position: CGPoint(x: 85.0, y: 196.77), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 213.24), size: CGSize(width: 145.27, height: 26.47), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "write here…", position: CGPoint(x: 85.0, y: 205.29), size: CGSize(width: 139.09, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: true, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "with love,", position: CGPoint(x: 35.54, y: 231.62), size: CGSize(width: 46.36, height: 7.35), fontSize: 8.4, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 75.09, y: 233.71), size: CGSize(width: 77.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "your name", position: CGPoint(x: 86.09, y: 236.35), size: CGSize(width: 77.27, height: 4.12), fontSize: 6, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "06", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 7:
            return MagazinePage(title: "MONTHLY RESET · LOOKING BACK", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "MONTHLY RESET · LOOKING BACK", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 07", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "LOOKING BACK", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "The Monthly", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Story.", position: CGPoint(x: 85.0, y: 58.83), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 66.18), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "week one", position: CGPoint(x: 46.36, y: 74.27), size: CGSize(width: 68.0, height: 7.35), fontSize: 9.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 46.36, y: 79.41), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 46.36, y: 101.47), size: CGSize(width: 68.0, height: 38.24), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 46.36, y: 120.59), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  a moment", position: CGPoint(x: 46.36, y: 115.58), size: CGSize(width: 68.0, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "WHAT HAPPENED →", position: CGPoint(x: 46.36, y: 125.58), size: CGSize(width: 68.0, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 46.36, y: 136.03), size: CGSize(width: 68.0, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "write here…", position: CGPoint(x: 46.36, y: 133.5), size: CGSize(width: 62.0, height: 10.5), fontSize: 5.64, fontName: "Georgia", isBold: false, isEditableText: true, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "week two", position: CGPoint(x: 123.64, y: 74.27), size: CGSize(width: 68.0, height: 7.35), fontSize: 9.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 123.64, y: 79.41), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 123.64, y: 101.47), size: CGSize(width: 68.0, height: 38.24), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 123.64, y: 120.59), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  a moment", position: CGPoint(x: 123.64, y: 115.58), size: CGSize(width: 68.0, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "WHAT HAPPENED →", position: CGPoint(x: 123.64, y: 125.58), size: CGSize(width: 68.0, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 123.64, y: 136.03), size: CGSize(width: 68.0, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "write here…", position: CGPoint(x: 123.64, y: 133.5), size: CGSize(width: 62.0, height: 10.5), fontSize: 5.64, fontName: "Georgia", isBold: false, isEditableText: true, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "week three", position: CGPoint(x: 46.36, y: 153.68), size: CGSize(width: 68.0, height: 7.35), fontSize: 9.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 46.36, y: 158.82), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 46.36, y: 180.88), size: CGSize(width: 68.0, height: 38.24), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 46.36, y: 200.0), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  a moment", position: CGPoint(x: 46.36, y: 195.0), size: CGSize(width: 68.0, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "WHAT HAPPENED →", position: CGPoint(x: 46.36, y: 205.0), size: CGSize(width: 68.0, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 46.36, y: 215.44), size: CGSize(width: 68.0, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "write here…", position: CGPoint(x: 46.36, y: 212.9), size: CGSize(width: 62.0, height: 10.5), fontSize: 5.64, fontName: "Georgia", isBold: false, isEditableText: true, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "week four", position: CGPoint(x: 123.64, y: 153.68), size: CGSize(width: 68.0, height: 7.35), fontSize: 9.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 123.64, y: 158.82), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 123.64, y: 180.88), size: CGSize(width: 68.0, height: 38.24), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 123.64, y: 200.0), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  a moment", position: CGPoint(x: 123.64, y: 195.0), size: CGSize(width: 68.0, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "WHAT HAPPENED →", position: CGPoint(x: 123.64, y: 205.0), size: CGSize(width: 68.0, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 123.64, y: 215.44), size: CGSize(width: 68.0, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "write here…", position: CGPoint(x: 123.64, y: 212.9), size: CGSize(width: 62.0, height: 10.5), fontSize: 5.64, fontName: "Georgia", isBold: false, isEditableText: true, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "07", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 8:
            return MagazinePage(title: "MONTHLY RESET · GROW TRACKER", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "MONTHLY RESET · GROW TRACKER", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 08", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "SCORECARD", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "How I grew.", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 61.5), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 47.2, y: 108.0), size: CGSize(width: 72.0, height: 78.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "mind", position: CGPoint(x: 47.2, y: 84.0), size: CGSize(width: 64.0, height: 10.5), fontSize: 13.8, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "___ / 10", position: CGPoint(x: 47.2, y: 95), size: CGSize(width: 64.0, height: 17.65), fontSize: 15.84, fontName: "Georgia", isBold: false, isEditableText: true, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "a note →", position: CGPoint(x: 47.2, y: 122.5), size: CGSize(width: 58.0, height: 7.2), fontSize: 7.2, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 47.2, y: 134.0), size: CGSize(width: 58.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 47.2, y: 142.5), size: CGSize(width: 58.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 122.8, y: 108.0), size: CGSize(width: 72.0, height: 78.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "body", position: CGPoint(x: 122.8, y: 84.0), size: CGSize(width: 64.0, height: 10.5), fontSize: 13.8, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "___ / 10", position: CGPoint(x: 122.8, y: 95), size: CGSize(width: 64.0, height: 17.65), fontSize: 15.84, fontName: "Georgia", isBold: false, isEditableText: true, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "a note →", position: CGPoint(x: 122.8, y: 122.5), size: CGSize(width: 58.0, height: 7.2), fontSize: 7.2, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 122.8, y: 134.0), size: CGSize(width: 58.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 122.8, y: 142.5), size: CGSize(width: 58.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 47.2, y: 190.0), size: CGSize(width: 72.0, height: 74.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "love", position: CGPoint(x: 47.2, y: 165.0), size: CGSize(width: 64.0, height: 10.5), fontSize: 13.8, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "___ / 10", position: CGPoint(x: 47.2, y: 176), size: CGSize(width: 64.0, height: 17.65), fontSize: 15.84, fontName: "Georgia", isBold: false, isEditableText: true, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "a note →", position: CGPoint(x: 47.2, y: 203.5), size: CGSize(width: 58.0, height: 7.2), fontSize: 7.2, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 47.2, y: 215.0), size: CGSize(width: 58.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 47.2, y: 223.5), size: CGSize(width: 58.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 122.8, y: 190.0), size: CGSize(width: 72.0, height: 74.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "rest", position: CGPoint(x: 122.8, y: 165.0), size: CGSize(width: 64.0, height: 10.5), fontSize: 13.8, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "___ / 10", position: CGPoint(x: 122.8, y: 176), size: CGSize(width: 64.0, height: 17.65), fontSize: 15.84, fontName: "Georgia", isBold: false, isEditableText: true, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "a note →", position: CGPoint(x: 122.8, y: 203.5), size: CGSize(width: 58.0, height: 7.2), fontSize: 7.2, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 122.8, y: 215.0), size: CGSize(width: 58.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 122.8, y: 223.5), size: CGSize(width: 58.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "08", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 9:
            return MagazinePage(title: "02", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "02", position: CGPoint(x: 117.45, y: 35.29), size: CGSize(width: 80.36, height: 47.06), fontSize: 63.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "SECTION", position: CGPoint(x: 43.27, y: 17.65), size: CGSize(width: 61.82, height: 5.88), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 35.54, y: 25.0), size: CGSize(width: 46.36, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "Tiny Wins.", position: CGPoint(x: 85.0, y: 122.06), size: CGSize(width: 145.27, height: 64.71), fontSize: 43.2, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 41.41, y: 157.35), size: CGSize(width: 58.11, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "Small wins to share — the headlines of a good month.", position: CGPoint(x: 85.0, y: 176.47), size: CGSize(width: 145.27, height: 29.41), fontSize: 9.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 223.53), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "Nº 02 · TINY WINS", position: CGPoint(x: 85.0, y: 230.15), size: CGSize(width: 145.27, height: 7.35), fontSize: 6.45, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 85.0, y: 238.23), size: CGSize(width: 145.27, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 10:
            return MagazinePage(title: "TINY WINS · THE DAILY ME", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "TINY WINS · THE DAILY ME", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 10", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "TINY WINS · THE DAILY ME", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "THE DAILY ME", position: CGPoint(x: 85.0, y: 34.5), size: CGSize(width: 145.27, height: 14.71), fontSize: 24.48, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 48.0), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "VOL. I", position: CGPoint(x: 29.88, y: 55.5), size: CGSize(width: 35.03, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "NO. 11", position: CGPoint(x: 68.0, y: 55.5), size: CGSize(width: 35.03, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "DATE  16 / 06 / 2026", position: CGPoint(x: 126.73, y: 55.5), size: CGSize(width: 61.82, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 61.5), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "TOP STORY", position: CGPoint(x: 29.88, y: 71.0), size: CGSize(width: 35.03, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Local human has a very good", position: CGPoint(x: 85.0, y: 86.0), size: CGSize(width: 145.27, height: 16.0), fontSize: 17.0, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "month.", position: CGPoint(x: 85.0, y: 101.0), size: CGSize(width: 145.27, height: 16.0), fontSize: 17.0, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 116.0), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "A small triumph!", position: CGPoint(x: 85.0, y: 123.0), size: CGSize(width: 145.27, height: 8.0), fontSize: 8.6, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 52.36, y: 149.0), size: CGSize(width: 80.0, height: 45.0), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  the scene of the win", position: CGPoint(x: 52.36, y: 166.5), size: CGSize(width: 80.0, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "CORRESPONDENT NOTE", position: CGPoint(x: 127.0, y: 123.0), size: CGSize(width: 62.0, height: 6.2), fontSize: 6.5, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 127.0, y: 149.0), size: CGSize(width: 62.0, height: 41.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "a few lines from you…", position: CGPoint(x: 127.0, y: 135.0), size: CGSize(width: 56.0, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: true, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "EDITORIAL — WHAT MADE THIS MONTH A WIN", position: CGPoint(x: 85.0, y: 181.5), size: CGSize(width: 145.27, height: 7.0), fontSize: 6.8, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 210.0), size: CGSize(width: 145.27, height: 48.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "write here…", position: CGPoint(x: 85.0, y: 193.5), size: CGSize(width: 139.09, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: true, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "10", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 11:
            return MagazinePage(title: "TINY WINS · TROPHY CABINET", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "TINY WINS · TROPHY CABINET", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 11", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "TROPHY CABINET", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Trophy", position: CGPoint(x: 85.0, y: 43.0), size: CGSize(width: 145.27, height: 28.0), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Cabinet.", position: CGPoint(x: 85.0, y: 58.0), size: CGSize(width: 145.27, height: 28.0), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 70.5), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 91.5), size: CGSize(width: 145.27, height: 36.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "★", position: CGPoint(x: 20.0, y: 81.5), size: CGSize(width: 8.4, height: 8.4), fontSize: 7.8, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 0, height: 0)),
            MagazineElement(type: .text, text: "AWARD Nº 01", position: CGPoint(x: 58.0, y: 81.5), size: CGSize(width: 66.0, height: 7.6), fontSize: 7.8, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "FOR", position: CGPoint(x: 27.0, y: 94.0), size: CGSize(width: 24.0, height: 7.0), fontSize: 7.2, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 96.0, y: 96.5), size: CGSize(width: 102.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 96.0, y: 106.5), size: CGSize(width: 102.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 130.5), size: CGSize(width: 145.27, height: 36.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "★", position: CGPoint(x: 20.0, y: 120.5), size: CGSize(width: 8.4, height: 8.4), fontSize: 7.8, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 0, height: 0)),
            MagazineElement(type: .text, text: "AWARD Nº 02", position: CGPoint(x: 58.0, y: 120.5), size: CGSize(width: 66.0, height: 7.6), fontSize: 7.8, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "FOR", position: CGPoint(x: 27.0, y: 133.0), size: CGSize(width: 24.0, height: 7.0), fontSize: 7.2, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 96.0, y: 135.0), size: CGSize(width: 102.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 96.0, y: 145.0), size: CGSize(width: 102.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 169.5), size: CGSize(width: 145.27, height: 36.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "★", position: CGPoint(x: 20.0, y: 159.5), size: CGSize(width: 8.4, height: 8.4), fontSize: 7.8, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 0, height: 0)),
            MagazineElement(type: .text, text: "AWARD Nº 03", position: CGPoint(x: 58.0, y: 159.5), size: CGSize(width: 66.0, height: 7.6), fontSize: 7.8, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "FOR", position: CGPoint(x: 27.0, y: 172.0), size: CGSize(width: 24.0, height: 7.0), fontSize: 7.2, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 96.0, y: 174.0), size: CGSize(width: 102.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 96.0, y: 184.0), size: CGSize(width: 102.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 208.5), size: CGSize(width: 145.27, height: 36.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "★", position: CGPoint(x: 20.0, y: 198.5), size: CGSize(width: 8.4, height: 8.4), fontSize: 7.8, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 0, height: 0)),
            MagazineElement(type: .text, text: "AWARD Nº 04", position: CGPoint(x: 58.0, y: 198.5), size: CGSize(width: 66.0, height: 7.6), fontSize: 7.8, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "FOR", position: CGPoint(x: 27.0, y: 211.0), size: CGSize(width: 24.0, height: 7.0), fontSize: 7.2, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 96.0, y: 213.0), size: CGSize(width: 102.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 96.0, y: 223.0), size: CGSize(width: 102.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "11", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 12:
            return MagazinePage(title: "TINY WINS · STREAK", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "TINY WINS · STREAK", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 12", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "A MONTH OF TINY VICTORIES", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Streak.", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 27.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 54.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "M", position: CGPoint(x: 22.73, y: 63.23), size: CGSize(width: 20.75, height: 8.82), fontSize: 7.26, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "T", position: CGPoint(x: 43.49, y: 63.23), size: CGSize(width: 20.75, height: 8.82), fontSize: 7.26, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "W", position: CGPoint(x: 64.25, y: 63.23), size: CGSize(width: 20.75, height: 8.82), fontSize: 7.26, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "T", position: CGPoint(x: 85.0, y: 63.23), size: CGSize(width: 20.75, height: 8.82), fontSize: 7.26, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "F", position: CGPoint(x: 105.75, y: 63.23), size: CGSize(width: 20.75, height: 8.82), fontSize: 7.26, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "S", position: CGPoint(x: 126.5, y: 63.23), size: CGSize(width: 20.75, height: 8.82), fontSize: 7.26, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "S", position: CGPoint(x: 147.25, y: 63.23), size: CGSize(width: 20.75, height: 8.82), fontSize: 7.26, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 69.12), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 22.73, y: 78.68), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "1", position: CGPoint(x: 22.74, y: 74.7), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 22.43, y: 79.85), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 43.49, y: 78.68), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "2", position: CGPoint(x: 43.49, y: 74.7), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 43.18, y: 79.85), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 64.25, y: 78.68), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "3", position: CGPoint(x: 64.25, y: 74.7), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 63.94, y: 79.85), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 78.68), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "4", position: CGPoint(x: 85.0, y: 74.7), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 84.69, y: 79.85), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 105.75, y: 78.68), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "5", position: CGPoint(x: 105.75, y: 74.7), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 105.44, y: 79.85), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 126.5, y: 78.68), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "6", position: CGPoint(x: 126.51, y: 74.7), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 126.2, y: 79.85), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 147.25, y: 78.68), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "7", position: CGPoint(x: 147.26, y: 74.7), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 146.95, y: 79.85), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 22.73, y: 94.85), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "8", position: CGPoint(x: 22.74, y: 90.88), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 22.43, y: 96.02), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 43.49, y: 94.85), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "9", position: CGPoint(x: 43.49, y: 90.88), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 43.18, y: 96.02), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 64.25, y: 94.85), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "10", position: CGPoint(x: 64.25, y: 90.88), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 63.94, y: 96.02), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 94.85), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "11", position: CGPoint(x: 85.0, y: 90.88), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 84.69, y: 96.02), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 105.75, y: 94.85), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "12", position: CGPoint(x: 105.75, y: 90.88), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 105.44, y: 96.02), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 126.5, y: 94.85), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "13", position: CGPoint(x: 126.51, y: 90.88), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 126.2, y: 96.02), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 147.25, y: 94.85), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "14", position: CGPoint(x: 147.26, y: 90.88), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 146.95, y: 96.02), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 22.73, y: 111.03), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "15", position: CGPoint(x: 22.74, y: 107.05), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 22.43, y: 112.2), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 43.49, y: 111.03), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "16", position: CGPoint(x: 43.49, y: 107.05), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 43.18, y: 112.2), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 64.25, y: 111.03), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "17", position: CGPoint(x: 64.25, y: 107.05), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 63.94, y: 112.2), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 111.03), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "18", position: CGPoint(x: 85.0, y: 107.05), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 84.69, y: 112.2), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 105.75, y: 111.03), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "19", position: CGPoint(x: 105.75, y: 107.05), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 105.44, y: 112.2), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 126.5, y: 111.03), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "20", position: CGPoint(x: 126.51, y: 107.05), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 126.2, y: 112.2), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 147.25, y: 111.03), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "21", position: CGPoint(x: 147.26, y: 107.05), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 146.95, y: 112.2), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 22.73, y: 127.21), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "22", position: CGPoint(x: 22.74, y: 123.23), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 22.43, y: 128.38), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 43.49, y: 127.21), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "23", position: CGPoint(x: 43.49, y: 123.23), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 43.18, y: 128.38), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 64.25, y: 127.21), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "24", position: CGPoint(x: 64.25, y: 123.23), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 63.94, y: 128.38), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 127.21), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "25", position: CGPoint(x: 85.0, y: 123.23), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 84.69, y: 128.38), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 105.75, y: 127.21), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "26", position: CGPoint(x: 105.75, y: 123.23), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 105.44, y: 128.38), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 126.5, y: 127.21), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "27", position: CGPoint(x: 126.51, y: 123.23), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 126.2, y: 128.38), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 147.25, y: 127.21), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "28", position: CGPoint(x: 147.26, y: 123.23), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 146.95, y: 128.38), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 22.73, y: 143.38), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "29", position: CGPoint(x: 22.74, y: 139.41), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 22.43, y: 144.56), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 43.49, y: 143.38), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "30", position: CGPoint(x: 43.49, y: 139.41), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 43.18, y: 144.56), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 64.25, y: 143.38), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "31", position: CGPoint(x: 64.25, y: 139.41), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 63.94, y: 144.56), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 143.38), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "32", position: CGPoint(x: 85.0, y: 139.41), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 84.69, y: 144.56), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 105.75, y: 143.38), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "33", position: CGPoint(x: 105.75, y: 139.41), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 105.44, y: 144.56), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 126.5, y: 143.38), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "34", position: CGPoint(x: 126.51, y: 139.41), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 126.2, y: 144.56), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 147.25, y: 143.38), size: CGSize(width: 20.75, height: 16.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "35", position: CGPoint(x: 147.26, y: 139.41), size: CGSize(width: 17.66, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 146.95, y: 144.56), size: CGSize(width: 5.56, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "WIN OF THE MONTH", position: CGPoint(x: 85.0, y: 161.47), size: CGSize(width: 145.27, height: 6.8), fontSize: 7.0, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 164.71), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 200.74), size: CGSize(width: 145.27, height: 66.18), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "write here…", position: CGPoint(x: 85.0, y: 172.94), size: CGSize(width: 139.09, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: true, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "12", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 13:
            return MagazinePage(title: "TINY WINS · HIGHLIGHT REEL", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "TINY WINS · HIGHLIGHT REEL", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 13", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "HIGHLIGHT REEL", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 6.4, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Highlight", position: CGPoint(x: 85.0, y: 43.5), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Reel.", position: CGPoint(x: 85.0, y: 58.2), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 72.5), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "SCENE 01", position: CGPoint(x: 47.0, y: 78.0), size: CGSize(width: 68.0, height: 7.2), fontSize: 7.8, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 47.0, y: 102.5), size: CGSize(width: 68.0, height: 39.0), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 47.0, y: 122.0), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  scene 01", position: CGPoint(x: 47.0, y: 117.0), size: CGSize(width: 68.0, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 47.0, y: 134.0), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "title", position: CGPoint(x: 47.0, y: 139.5), size: CGSize(width: 68.0, height: 6.8), fontSize: 7.0, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "SCENE 02", position: CGPoint(x: 123.0, y: 78.0), size: CGSize(width: 68.0, height: 7.2), fontSize: 7.8, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 123.0, y: 102.5), size: CGSize(width: 68.0, height: 39.0), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 123.0, y: 122.0), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  scene 02", position: CGPoint(x: 123.0, y: 117.0), size: CGSize(width: 68.0, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 123.0, y: 134.0), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "title", position: CGPoint(x: 123.0, y: 139.5), size: CGSize(width: 68.0, height: 6.8), fontSize: 7.0, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "SCENE 03", position: CGPoint(x: 47.0, y: 153.5), size: CGSize(width: 68.0, height: 7.2), fontSize: 7.8, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 47.0, y: 178.0), size: CGSize(width: 68.0, height: 39.0), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 47.0, y: 197.5), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  scene 03", position: CGPoint(x: 47.0, y: 192.5), size: CGSize(width: 68.0, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 47.0, y: 209.5), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "title", position: CGPoint(x: 47.0, y: 215.0), size: CGSize(width: 68.0, height: 6.8), fontSize: 7.0, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "SCENE 04", position: CGPoint(x: 123.0, y: 153.5), size: CGSize(width: 68.0, height: 7.2), fontSize: 7.8, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 123.0, y: 178.0), size: CGSize(width: 68.0, height: 39.0), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 123.0, y: 197.5), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  scene 04", position: CGPoint(x: 123.0, y: 192.5), size: CGSize(width: 68.0, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 123.0, y: 209.5), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "title", position: CGPoint(x: 123.0, y: 215.0), size: CGSize(width: 68.0, height: 6.8), fontSize: 7.0, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "13", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        
        case 14:
            return MagazinePage(title: "03", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "03", position: CGPoint(x: 117.45, y: 35.29), size: CGSize(width: 80.36, height: 47.06), fontSize: 63.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "SECTION", position: CGPoint(x: 43.27, y: 17.65), size: CGSize(width: 61.82, height: 5.88), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 35.54, y: 25.0), size: CGSize(width: 46.36, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "Hobbies.", position: CGPoint(x: 85.0, y: 122.06), size: CGSize(width: 145.27, height: 64.71), fontSize: 43.2, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 41.41, y: 157.35), size: CGSize(width: 58.11, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "The practice of becoming better at something you love.", position: CGPoint(x: 85.0, y: 176.47), size: CGSize(width: 145.27, height: 29.41), fontSize: 9.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 223.53), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "Nº 03 · HOBBIES", position: CGPoint(x: 85.0, y: 230.15), size: CGSize(width: 145.27, height: 7.35), fontSize: 6.45, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 85.0, y: 238.23), size: CGSize(width: 145.27, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 15:
            return MagazinePage(title: "HOBBIES · TRACKER", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "HOBBIES · TRACKER", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 15", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "HOBBY TRACKER", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "How I spend", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 23.04, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "my time.", position: CGPoint(x: 85.0, y: 58.83), size: CGSize(width: 145.27, height: 32.35), fontSize: 23.04, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 61.5), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "HOBBY 01", position: CGPoint(x: 85.0, y: 73.5), size: CGSize(width: 145.27, height: 7.8), fontSize: 7.8, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 84.0), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "name", position: CGPoint(x: 85.0, y: 86.0), size: CGSize(width: 145.27, height: 6.8), fontSize: 6.8, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "✦ 0/31", position: CGPoint(x: 145.0, y: 76.5), size: CGSize(width: 35.0, height: 8.5), fontSize: 9.8, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 16.3, y: 97.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 20.97, y: 97.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 25.64, y: 97.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 30.31, y: 97.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 34.98, y: 97.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 39.65, y: 97.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 44.32, y: 97.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 48.99, y: 97.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 53.66, y: 97.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 58.33, y: 97.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 63.0, y: 97.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 67.67, y: 97.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 72.34, y: 97.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 77.01, y: 97.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 81.68, y: 97.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 86.35, y: 97.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 91.02, y: 97.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 95.69, y: 97.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 100.36, y: 97.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 105.03, y: 97.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 109.7, y: 97.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 114.37, y: 97.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 119.04, y: 97.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 123.71, y: 97.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 128.38, y: 97.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 133.05, y: 97.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 137.72, y: 97.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 142.39, y: 97.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 147.06, y: 97.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 151.73, y: 97.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 156.4, y: 97.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "HOBBY 02", position: CGPoint(x: 85.0, y: 110.0), size: CGSize(width: 145.27, height: 7.8), fontSize: 7.8, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 120.5), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "name", position: CGPoint(x: 85.0, y: 122.5), size: CGSize(width: 145.27, height: 6.8), fontSize: 6.8, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "✦ 0/31", position: CGPoint(x: 145.0, y: 113.0), size: CGSize(width: 35.0, height: 8.5), fontSize: 9.8, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 16.3, y: 133.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 20.97, y: 133.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 25.64, y: 133.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 30.31, y: 133.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 34.98, y: 133.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 39.65, y: 133.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 44.32, y: 133.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 48.99, y: 133.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 53.66, y: 133.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 58.33, y: 133.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 63.0, y: 133.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 67.67, y: 133.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 72.34, y: 133.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 77.01, y: 133.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 81.68, y: 133.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 86.35, y: 133.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 91.02, y: 133.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 95.69, y: 133.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 100.36, y: 133.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 105.03, y: 133.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 109.7, y: 133.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 114.37, y: 133.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 119.04, y: 133.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 123.71, y: 133.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 128.38, y: 133.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 133.05, y: 133.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 137.72, y: 133.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 142.39, y: 133.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 147.06, y: 133.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 151.73, y: 133.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 156.4, y: 133.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "HOBBY 03", position: CGPoint(x: 85.0, y: 146.5), size: CGSize(width: 145.27, height: 7.8), fontSize: 7.8, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 157.0), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "name", position: CGPoint(x: 85.0, y: 159.0), size: CGSize(width: 145.27, height: 6.8), fontSize: 6.8, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "✦ 0/31", position: CGPoint(x: 145.0, y: 149.5), size: CGSize(width: 35.0, height: 8.5), fontSize: 9.8, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 16.3, y: 170.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 20.97, y: 170.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 25.64, y: 170.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 30.31, y: 170.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 34.98, y: 170.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 39.65, y: 170.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 44.32, y: 170.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 48.99, y: 170.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 53.66, y: 170.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 58.33, y: 170.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 63.0, y: 170.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 67.67, y: 170.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 72.34, y: 170.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 77.01, y: 170.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 81.68, y: 170.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 86.35, y: 170.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 91.02, y: 170.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 95.69, y: 170.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 100.36, y: 170.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 105.03, y: 170.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 109.7, y: 170.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 114.37, y: 170.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 119.04, y: 170.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 123.71, y: 170.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 128.38, y: 170.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 133.05, y: 170.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 137.72, y: 170.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 142.39, y: 170.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 147.06, y: 170.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 151.73, y: 170.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 156.4, y: 170.0), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "HOBBY 04", position: CGPoint(x: 85.0, y: 183.0), size: CGSize(width: 145.27, height: 7.8), fontSize: 7.8, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 193.5), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "name", position: CGPoint(x: 85.0, y: 195.5), size: CGSize(width: 145.27, height: 6.8), fontSize: 6.8, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "✦ 0/31", position: CGPoint(x: 145.0, y: 186.0), size: CGSize(width: 35.0, height: 8.5), fontSize: 9.8, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 16.3, y: 206.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 20.97, y: 206.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 25.64, y: 206.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 30.31, y: 206.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 34.98, y: 206.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 39.65, y: 206.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 44.32, y: 206.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 48.99, y: 206.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 53.66, y: 206.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 58.33, y: 206.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 63.0, y: 206.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 67.67, y: 206.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 72.34, y: 206.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 77.01, y: 206.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 81.68, y: 206.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 86.35, y: 206.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 91.02, y: 206.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 95.69, y: 206.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 100.36, y: 206.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 105.03, y: 206.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 109.7, y: 206.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 114.37, y: 206.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 119.04, y: 206.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 123.71, y: 206.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 128.38, y: 206.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 133.05, y: 206.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 137.72, y: 206.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 142.39, y: 206.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 147.06, y: 206.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 151.73, y: 206.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 156.4, y: 206.5), size: CGSize(width: 4.2, height: 10.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "15", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 16:
            return MagazinePage(title: "HOBBIES · A NEW TRY", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "HOBBIES · A NEW TRY", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 16", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "A NEW TRY", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Trying out", position: CGPoint(x: 85.0, y: 46.0), size: CGSize(width: 145.27, height: 32.35), fontSize: 23.04, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "new things.", position: CGPoint(x: 85.0, y: 61.0), size: CGSize(width: 145.27, height: 32.35), fontSize: 23.04, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 69.5), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 48.68, y: 108.0), size: CGSize(width: 72.64, height: 67.65), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 48.68, y: 141.8), size: CGSize(width: 72.64, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  the practice", position: CGPoint(x: 48.68, y: 136.8), size: CGSize(width: 72.64, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "", position: CGPoint(x: 124.41, y: 81.0), size: CGSize(width: 66.45, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "NAME →", position: CGPoint(x: 121.4, y: 78.5), size: CGSize(width: 66.45, height: 7.2), fontSize: 7.2, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 124.41, y: 88.0), size: CGSize(width: 66.45, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "effort", position: CGPoint(x: 105.09, y: 99.5), size: CGSize(width: 35.0, height: 8.0), fontSize: 8.0, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 122.56, y: 99.65), size: CGSize(width: 4.02, height: 3.82), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 128.12, y: 99.65), size: CGSize(width: 4.02, height: 3.82), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 133.68, y: 99.65), size: CGSize(width: 4.02, height: 3.82), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 139.25, y: 99.65), size: CGSize(width: 4.02, height: 3.82), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 144.81, y: 99.65), size: CGSize(width: 4.02, height: 3.82), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "cost", position: CGPoint(x: 105.09, y: 109.0), size: CGSize(width: 35.0, height: 8.0), fontSize: 8.0, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 122.56, y: 109.15), size: CGSize(width: 4.02, height: 3.82), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 128.12, y: 109.15), size: CGSize(width: 4.02, height: 3.82), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 133.68, y: 109.15), size: CGSize(width: 4.02, height: 3.82), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 139.25, y: 109.15), size: CGSize(width: 4.02, height: 3.82), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 144.81, y: 109.15), size: CGSize(width: 4.02, height: 3.82), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "difficulty", position: CGPoint(x: 105.09, y: 118.5), size: CGSize(width: 35.0, height: 8.0), fontSize: 8.0, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 122.56, y: 118.65), size: CGSize(width: 4.02, height: 3.82), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 128.12, y: 118.65), size: CGSize(width: 4.02, height: 3.82), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 133.68, y: 118.65), size: CGSize(width: 4.02, height: 3.82), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 139.25, y: 118.65), size: CGSize(width: 4.02, height: 3.82), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 144.81, y: 118.65), size: CGSize(width: 4.02, height: 3.82), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "reward", position: CGPoint(x: 105.09, y: 128.0), size: CGSize(width: 35.0, height: 8.0), fontSize: 8.0, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 122.56, y: 128.15), size: CGSize(width: 4.02, height: 3.82), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 128.12, y: 128.15), size: CGSize(width: 4.02, height: 3.82), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 133.68, y: 128.15), size: CGSize(width: 4.02, height: 3.82), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 139.25, y: 128.15), size: CGSize(width: 4.02, height: 3.82), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 144.81, y: 128.15), size: CGSize(width: 4.02, height: 3.82), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "WILL I CONTINUE?", position: CGPoint(x: 85.0, y: 158.0), size: CGSize(width: 145.27, height: 7.4), fontSize: 7.4, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 162.0), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 34.0, y: 174.0), size: CGSize(width: 36.5, height: 9.2), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "YES", position: CGPoint(x: 34.0, y: 174.0), size: CGSize(width: 36.5, height: 9.2), fontSize: 6.2, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 83.45, y: 174.0), size: CGSize(width: 36.5, height: 9.2), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "NO", position: CGPoint(x: 83.45, y: 174.0), size: CGSize(width: 36.5, height: 9.2), fontSize: 6.2, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "WHAT I LEARNED", position: CGPoint(x: 85.0, y: 194.0), size: CGSize(width: 145.27, height: 7.4), fontSize: 7.4, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 218.0), size: CGSize(width: 145.27, height: 40.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "write here…", position: CGPoint(x: 85.0, y: 203.0), size: CGSize(width: 139.09, height: 5.88), fontSize: 6.55, fontName: "Helvetica", isBold: false, isEditableText: true, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "16", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 17:
            return MagazinePage(title: "HOBBIES · GALLERY", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "HOBBIES · GALLERY", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 17", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "HOBBY GALLERY", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Hobby", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Gallery.", position: CGPoint(x: 85.0, y: 58.83), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 66.18), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 54.39, y: 105.89), size: CGSize(width: 84.07, height: 70.59), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 54.39, y: 141.18), size: CGSize(width: 84.07, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  photo · large", position: CGPoint(x: 54.39, y: 136.18), size: CGSize(width: 84.07, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 130.13, y: 87.5), size: CGSize(width: 55.02, height: 33.82), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 130.13, y: 104.41), size: CGSize(width: 55.02, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  photo", position: CGPoint(x: 130.13, y: 99.42), size: CGSize(width: 55.02, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 130.13, y: 124.26), size: CGSize(width: 55.02, height: 33.82), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 130.13, y: 141.18), size: CGSize(width: 55.02, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  photo", position: CGPoint(x: 130.13, y: 136.18), size: CGSize(width: 55.02, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 39.87, y: 166.18), size: CGSize(width: 55.02, height: 41.18), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 39.87, y: 186.76), size: CGSize(width: 55.02, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  photo", position: CGPoint(x: 39.87, y: 181.77), size: CGSize(width: 55.02, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 115.59, y: 166.18), size: CGSize(width: 84.07, height: 41.18), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 115.59, y: 186.76), size: CGSize(width: 84.07, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  photo · wide", position: CGPoint(x: 115.59, y: 181.77), size: CGSize(width: 84.07, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 85.0, y: 211.77), size: CGSize(width: 145.27, height: 41.18), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 232.35), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  photo · banner", position: CGPoint(x: 85.0, y: 227.36), size: CGSize(width: 145.27, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "17", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 18:
            return MagazinePage(title: "HOBBIES · PROGRESS", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "HOBBIES · PROGRESS", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 18", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PROGRESS TRACKER", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Skill", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Progress.", position: CGPoint(x: 85.0, y: 58.83), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 69.0), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "technique", position: CGPoint(x: 85.0, y: 83.0), size: CGSize(width: 145.27, height: 8.5), fontSize: 11.2, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "__SLIDER_HINT__", position: CGPoint(x: 85.0, y: 93.0), size: CGSize(width: 145.27, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 41.41, y: 93.0), size: CGSize(width: 58.11, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "speed", position: CGPoint(x: 85.0, y: 108.0), size: CGSize(width: 145.27, height: 8.5), fontSize: 11.2, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "__SLIDER_HINT__", position: CGPoint(x: 85.0, y: 118.0), size: CGSize(width: 145.27, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 41.41, y: 118.0), size: CGSize(width: 58.11, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "consistency", position: CGPoint(x: 85.0, y: 133.0), size: CGSize(width: 145.27, height: 8.5), fontSize: 11.2, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "__SLIDER_HINT__", position: CGPoint(x: 85.0, y: 143.0), size: CGSize(width: 145.27, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 41.41, y: 143.0), size: CGSize(width: 58.11, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "theory", position: CGPoint(x: 85.0, y: 158.0), size: CGSize(width: 145.27, height: 8.5), fontSize: 11.2, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "__SLIDER_HINT__", position: CGPoint(x: 85.0, y: 168.0), size: CGSize(width: 145.27, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 41.41, y: 168.0), size: CGSize(width: 58.11, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "creativity", position: CGPoint(x: 85.0, y: 183.0), size: CGSize(width: 145.27, height: 8.5), fontSize: 11.2, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "__SLIDER_HINT__", position: CGPoint(x: 85.0, y: 193.0), size: CGSize(width: 145.27, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 41.41, y: 193.0), size: CGSize(width: 58.11, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "confidence", position: CGPoint(x: 85.0, y: 208.0), size: CGSize(width: 145.27, height: 8.5), fontSize: 11.2, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "__SLIDER_HINT__", position: CGPoint(x: 85.0, y: 218.0), size: CGSize(width: 145.27, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 41.41, y: 218.0), size: CGSize(width: 58.11, height: 5.29), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "18", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 19:
            return MagazinePage(title: "04", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "04", position: CGPoint(x: 117.45, y: 35.29), size: CGSize(width: 80.36, height: 47.06), fontSize: 63.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "SECTION", position: CGPoint(x: 43.27, y: 17.65), size: CGSize(width: 61.82, height: 5.88), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 35.54, y: 25.0), size: CGSize(width: 46.36, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "Relationships.", position: CGPoint(x: 85.0, y: 122.06), size: CGSize(width: 145.27, height: 64.71), fontSize: 34.56, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 41.41, y: 157.35), size: CGSize(width: 58.11, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "An ode to the people by your side, with a little gossip in the margins.", position: CGPoint(x: 85.0, y: 176.47), size: CGSize(width: 145.27, height: 29.41), fontSize: 9.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 223.53), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "Nº 04 · RELATIONSHIPS", position: CGPoint(x: 85.0, y: 230.15), size: CGSize(width: 145.27, height: 7.35), fontSize: 6.45, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 85.0, y: 238.23), size: CGSize(width: 145.27, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 20:
            return MagazinePage(title: "RELATIONSHIPS · DATE REVIEW", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "RELATIONSHIPS · DATE REVIEW", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: true, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 20", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "DATE REVIEW", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "How it", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 23.04, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "went.", position: CGPoint(x: 85.0, y: 58.83), size: CGSize(width: 145.27, height: 32.35), fontSize: 23.04, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 66.18), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "WITH", position: CGPoint(x: 21.63, y: 73.53), size: CGSize(width: 24.0, height: 6.8), fontSize: 6.8, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 94.28, y: 77.35), size: CGSize(width: 126.73, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "WHERE", position: CGPoint(x: 21.63, y: 83.82), size: CGSize(width: 24.0, height: 6.8), fontSize: 6.8, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 94.28, y: 87.65), size: CGSize(width: 126.73, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "WHEN", position: CGPoint(x: 21.63, y: 94.12), size: CGSize(width: 24.0, height: 6.8), fontSize: 6.8, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 94.28, y: 97.94), size: CGSize(width: 126.73, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 45.05, y: 130.88), size: CGSize(width: 65.37, height: 50.0), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 45.05, y: 155.88), size: CGSize(width: 65.37, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  the date", position: CGPoint(x: 45.05, y: 150.89), size: CGSize(width: 65.37, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: true, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "FIRST IMPRESSIONS", position: CGPoint(x: 120.78, y: 108.52), size: CGSize(width: 73.72, height: 6.4), fontSize: 6.6, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 120.78, y: 133.82), size: CGSize(width: 73.72, height: 44.12), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "write here…", position: CGPoint(x: 120.78, y: 117.06), size: CGSize(width: 67.54, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: true, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "VIBE CHECK", position: CGPoint(x: 85.0, y: 162.94), size: CGSize(width: 145.27, height: 6.4), fontSize: 6.6, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 166.18), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "conversation", position: CGPoint(x: 31.9, y: 174.0), size: CGSize(width: 42.0, height: 6.47), fontSize: 7.4, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 14.00, y: 180.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 18.60, y: 180.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 23.20, y: 180.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 27.80, y: 180.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 32.40, y: 180.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "chemistry", position: CGPoint(x: 86.9, y: 174.0), size: CGSize(width: 42.0, height: 6.47), fontSize: 7.4, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 69.00, y: 180.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 73.60, y: 180.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 78.20, y: 180.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 82.80, y: 180.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 87.40, y: 180.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "humor", position: CGPoint(x: 136.6, y: 174.0), size: CGSize(width: 33.32, height: 6.47), fontSize: 7.4, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 123.00, y: 180.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 127.60, y: 180.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 132.20, y: 180.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 136.80, y: 180.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 141.40, y: 180.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "looks", position: CGPoint(x: 31.9, y: 188.0), size: CGSize(width: 42.0, height: 6.47), fontSize: 7.4, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 14.00, y: 194.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 18.60, y: 194.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 23.20, y: 194.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 27.80, y: 194.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 32.40, y: 194.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "presence", position: CGPoint(x: 86.9, y: 188.0), size: CGSize(width: 42.0, height: 6.47), fontSize: 7.4, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 69.00, y: 194.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 73.60, y: 194.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 78.20, y: 194.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 82.80, y: 194.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 87.40, y: 194.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "manners", position: CGPoint(x: 140.9, y: 188.0), size: CGSize(width: 42.0, height: 6.47), fontSize: 7.4, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 123.00, y: 194.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 127.60, y: 194.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 132.20, y: 194.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 136.80, y: 194.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 141.40, y: 194.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "overall", position: CGPoint(x: 27.57, y: 202.0), size: CGSize(width: 33.32, height: 6.47), fontSize: 7.4, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 14.00, y: 208.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 18.60, y: 208.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 23.20, y: 208.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 27.80, y: 208.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 32.40, y: 208.00), size: CGSize(width: 3.6, height: 3.4), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "DO I WANT TO SEE THIS PERSON AGAIN?", position: CGPoint(x: 85.0, y: 217.5), size: CGSize(width: 145.27, height: 6.4), fontSize: 6.6, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 34.0, y: 230.0), size: CGSize(width: 36.5, height: 9.2), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "NEVER", position: CGPoint(x: 34.0, y: 230.0), size: CGSize(width: 36.5, height: 9.2), fontSize: 6.2, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 83.45, y: 230.0), size: CGSize(width: 36.5, height: 9.2), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "MAYBE", position: CGPoint(x: 83.45, y: 230.0), size: CGSize(width: 36.5, height: 9.2), fontSize: 6.2, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 132.91, y: 230.0), size: CGSize(width: 36.5, height: 9.2), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "YES", position: CGPoint(x: 132.91, y: 230.0), size: CGSize(width: 36.5, height: 9.2), fontSize: 6.2, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "20", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 21:
            return MagazinePage(title: "RELATIONSHIPS · THE RANKING", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "RELATIONSHIPS · THE RANKING", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 21", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "DATE REVIEW", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: true, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "The", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Ranking.", position: CGPoint(x: 85.0, y: 58.83), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 66.18), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),

            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 112.0), size: CGSize(width: 145.27, height: 72.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "N° 01", position: CGPoint(x: 31.0, y: 81.0), size: CGSize(width: 34.0, height: 11.0), fontSize: 15.6, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 39.0, y: 116.0), size: CGSize(width: 44.0, height: 50.0), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  portrait", position: CGPoint(x: 39.0, y: 136.0), size: CGSize(width: 44.0, height: 6.47), fontSize: 6.2, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "NAME", position: CGPoint(x: 96.0, y: 95.0), size: CGSize(width: 64.0, height: 6.8), fontSize: 6.6, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 96.0, y: 108.0), size: CGSize(width: 59.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "OCCUPATION", position: CGPoint(x: 96.0, y: 114.0), size: CGSize(width: 64.0, height: 6.8), fontSize: 6.6, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 96.0, y: 127.0), size: CGSize(width: 59.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "AGE", position: CGPoint(x: 143.0, y: 114.0), size: CGSize(width: 20.0, height: 6.8), fontSize: 6.6, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 143.0, y: 127.0), size: CGSize(width: 15.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "WOULD SEE AGAIN", position: CGPoint(x: 96.0, y: 134.0), size: CGSize(width: 64.0, height: 6.8), fontSize: 6.6, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 128.0, y: 137.0), size: CGSize(width: 12.36, height: 8.82), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "Y", position: CGPoint(x: 128.0, y: 137.0), size: CGSize(width: 12.36, height: 8.82), fontSize: 7.26, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 141.91, y: 137.0), size: CGSize(width: 12.36, height: 8.82), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "N", position: CGPoint(x: 141.91, y: 137.0), size: CGSize(width: 12.36, height: 8.82), fontSize: 7.26, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),

            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 188.0), size: CGSize(width: 145.27, height: 72.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "N° 02", position: CGPoint(x: 31.0, y: 156.0), size: CGSize(width: 34.0, height: 11.0), fontSize: 15.6, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 39.0, y: 192.0), size: CGSize(width: 44.0, height: 50.0), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  portrait", position: CGPoint(x: 39.0, y: 212.0), size: CGSize(width: 44.0, height: 6.47), fontSize: 6.2, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "NAME", position: CGPoint(x: 96.0, y: 171.0), size: CGSize(width: 64.0, height: 6.8), fontSize: 6.6, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 96.0, y: 184.0), size: CGSize(width: 59.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "OCCUPATION", position: CGPoint(x: 96.0, y: 190.0), size: CGSize(width: 64.0, height: 6.8), fontSize: 6.6, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 96.0, y: 203.0), size: CGSize(width: 59.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "AGE", position: CGPoint(x: 143.0, y: 190.0), size: CGSize(width: 20.0, height: 6.8), fontSize: 6.6, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 143.0, y: 203.0), size: CGSize(width: 15.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "WOULD SEE AGAIN", position: CGPoint(x: 96.0, y: 210.0), size: CGSize(width: 64.0, height: 6.8), fontSize: 6.6, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 128.0, y: 213.0), size: CGSize(width: 12.36, height: 8.82), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "Y", position: CGPoint(x: 128.0, y: 213.0), size: CGSize(width: 12.36, height: 8.82), fontSize: 7.26, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 141.91, y: 213.0), size: CGSize(width: 12.36, height: 8.82), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "N", position: CGPoint(x: 141.91, y: 213.0), size: CGSize(width: 12.36, height: 8.82), fontSize: 7.26, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),

            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "21", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 22:
            return MagazinePage(title: "RELATIONSHIPS · APPRECIATION", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "RELATIONSHIPS · APPRECIATION", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 22", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "APPRECIATION POST", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "People I love.", position: CGPoint(x: 85.0, y: 41.2), size: CGSize(width: 145.27, height: 22.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 61.2), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),

            MagazineElement(type: .text, text: "THEIR NAME", position: CGPoint(x: 85.0, y: 73.5), size: CGSize(width: 145.27, height: 6.4), fontSize: 7.4, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 83.2), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "why I love them →", position: CGPoint(x: 85.0, y: 92.0), size: CGSize(width: 145.27, height: 6.8), fontSize: 7.4, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 110.0), size: CGSize(width: 145.27, height: 28.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),

            MagazineElement(type: .text, text: "THEIR NAME", position: CGPoint(x: 85.0, y: 129.0), size: CGSize(width: 145.27, height: 6.4), fontSize: 7.4, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 138.7), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "why I love them →", position: CGPoint(x: 85.0, y: 147.5), size: CGSize(width: 145.27, height: 6.8), fontSize: 7.4, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 165.5), size: CGSize(width: 145.27, height: 28.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),

            MagazineElement(type: .text, text: "THEIR NAME", position: CGPoint(x: 85.0, y: 184.5), size: CGSize(width: 145.27, height: 6.4), fontSize: 7.4, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 194.2), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "why I love them →", position: CGPoint(x: 85.0, y: 203.0), size: CGSize(width: 145.27, height: 6.8), fontSize: 7.4, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 221.0), size: CGSize(width: 145.27, height: 28.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),

            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "22", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 23:
            return MagazinePage(title: "RELATIONSHIPS · IN LOVE WITH L", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "RELATIONSHIPS · IN LOVE WITH LIFE", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 23", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "APPRECIATION", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "In love with", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 23.04, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "life.", position: CGPoint(x: 85.0, y: 58.83), size: CGSize(width: 145.27, height: 32.35), fontSize: 23.04, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 66.18), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "Dear life,", position: CGPoint(x: 85.0, y: 75.0), size: CGSize(width: 145.27, height: 10.5), fontSize: 14.2, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "things you gave me this month —", position: CGPoint(x: 85.0, y: 94.86), size: CGSize(width: 145.27, height: 8.2), fontSize: 8.8, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "✦", position: CGPoint(x: 15.45, y: 104.7), size: CGSize(width: 6.18, height: 6.47), fontSize: 7.63, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 55.9, y: 108.24), size: CGSize(width: 87.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "✦", position: CGPoint(x: 15.45, y: 114.11), size: CGSize(width: 6.18, height: 6.47), fontSize: 7.63, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 55.9, y: 117.65), size: CGSize(width: 87.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "✦", position: CGPoint(x: 15.45, y: 123.53), size: CGSize(width: 6.18, height: 6.47), fontSize: 7.63, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 55.9, y: 127.06), size: CGSize(width: 87.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "✦", position: CGPoint(x: 15.45, y: 132.95), size: CGSize(width: 6.18, height: 6.47), fontSize: 7.63, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 55.9, y: 136.47), size: CGSize(width: 87.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "✦", position: CGPoint(x: 15.45, y: 142.36), size: CGSize(width: 6.18, height: 6.47), fontSize: 7.63, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 55.9, y: 145.88), size: CGSize(width: 87.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "✦", position: CGPoint(x: 15.45, y: 151.77), size: CGSize(width: 6.18, height: 6.47), fontSize: 7.63, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 55.9, y: 155.29), size: CGSize(width: 87.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "✦", position: CGPoint(x: 15.45, y: 161.18), size: CGSize(width: 6.18, height: 6.47), fontSize: 7.63, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 55.9, y: 164.71), size: CGSize(width: 87.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 130.89, y: 133.82), size: CGSize(width: 53.47, height: 64.71), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 130.89, y: 166.18), size: CGSize(width: 53.47, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  a small joy", position: CGPoint(x: 130.89, y: 161.18), size: CGSize(width: 53.47, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "yours, always.", position: CGPoint(x: 128.0, y: 174.2), size: CGSize(width: 53.47, height: 8.2), fontSize: 10.2, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 130.89, y: 184.0), size: CGSize(width: 53.47, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "sign here", position: CGPoint(x: 130.89, y: 188.0), size: CGSize(width: 53.47, height: 5.0), fontSize: 6.5, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "ONE MORE THING I WANT TO REMEMBER", position: CGPoint(x: 85.0, y: 199.71), size: CGSize(width: 145.27, height: 6.4), fontSize: 6.6, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 218.38), size: CGSize(width: 145.27, height: 30.88), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "write here…", position: CGPoint(x: 85.0, y: 208.23), size: CGSize(width: 139.09, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: true, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "23", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 24:
            return MagazinePage(title: "RELATIONSHIPS · NEWEST OBSESSI", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "RELATIONSHIPS · NEWEST OBSESSION", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 24", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "NEWEST OBSESSION", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Crush", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Diary.", position: CGPoint(x: 85.0, y: 58.83), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 66.18), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 136.0, y: 100.0), size: CGSize(width: 48.0, height: 58.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 136.0, y: 96.0), size: CGSize(width: 43.0, height: 42.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 136.0, y: 96.0), size: CGSize(width: 43.0, height: 42.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false, imageFit: .fill),
            MagazineElement(type: .title, text: "name:", position: CGPoint(x: 29.0, y: 78.3), size: CGSize(width: 30.0, height: 8.82), fontSize: 12.8, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 70.7, y: 81.4), size: CGSize(width: 63.4, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "first noticed", position: CGPoint(x: 45.0, y: 99.0), size: CGSize(width: 64.0, height: 7.4), fontSize: 9.3, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 59.0, y: 115.5), size: CGSize(width: 90.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 59.0, y: 131.2), size: CGSize(width: 90.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "why they’re hot", position: CGPoint(x: 45.0, y: 150.0), size: CGSize(width: 64.0, height: 7.4), fontSize: 9.3, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 166.7), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 182.4), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "what I already know about them", position: CGPoint(x: 70.5, y: 195.0), size: CGSize(width: 116.0, height: 7.4), fontSize: 9.3, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 213.8), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 229.5), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "24", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 25:
            return MagazinePage(title: "RELATIONSHIPS · PEOPLE I LOVE", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "RELATIONSHIPS · PEOPLE I LOVE", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 25", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PEOPLE I LOVE", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "The people", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 23.04, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "in my corner.", position: CGPoint(x: 85.0, y: 58.83), size: CGSize(width: 145.27, height: 32.35), fontSize: 23.04, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 68.46), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            
            MagazineElement(type: .text, text: "NAME", position: CGPoint(x: 59.0, y: 82.0), size: CGSize(width: 84.0, height: 7.35), fontSize: 8.0, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 59.0, y: 91.0), size: CGSize(width: 84.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 137.0, y: 111.0), size: CGSize(width: 43.0, height: 58.0), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 137.0, y: 140.0), size: CGSize(width: 43.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  portrait", position: CGPoint(x: 137.0, y: 135.0), size: CGSize(width: 43.0, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "HOW WE MET", position: CGPoint(x: 59.0, y: 104.0), size: CGSize(width: 84.0, height: 6.47), fontSize: 7.0, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 59.0, y: 113.0), size: CGSize(width: 84.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "WHY I LOVE THEM", position: CGPoint(x: 59.0, y: 128.0), size: CGSize(width: 84.0, height: 6.47), fontSize: 7.0, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 59.0, y: 137.0), size: CGSize(width: 84.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 59.0, y: 149.0), size: CGSize(width: 84.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            
            MagazineElement(type: .text, text: "NAME", position: CGPoint(x: 59.0, y: 166.0), size: CGSize(width: 84.0, height: 7.35), fontSize: 8.0, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 59.0, y: 175.0), size: CGSize(width: 84.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 137.0, y: 195.0), size: CGSize(width: 43.0, height: 58.0), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 137.0, y: 224.0), size: CGSize(width: 43.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  portrait", position: CGPoint(x: 137.0, y: 219.0), size: CGSize(width: 43.0, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "HOW WE MET", position: CGPoint(x: 59.0, y: 188.0), size: CGSize(width: 84.0, height: 6.47), fontSize: 7.0, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 59.0, y: 197.0), size: CGSize(width: 84.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "WHY I LOVE THEM", position: CGPoint(x: 59.0, y: 212.0), size: CGSize(width: 84.0, height: 6.47), fontSize: 7.0, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 59.0, y: 221.0), size: CGSize(width: 84.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 59.0, y: 233.0), size: CGSize(width: 84.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "25", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 26:
            return MagazinePage(title: "05", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "05", position: CGPoint(x: 117.45, y: 35.29), size: CGSize(width: 80.36, height: 47.06), fontSize: 63.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "SECTION", position: CGPoint(x: 43.27, y: 17.65), size: CGSize(width: 61.82, height: 5.88), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 35.54, y: 25.0), size: CGSize(width: 46.36, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "Playlist & Music.", position: CGPoint(x: 85.0, y: 122.06), size: CGSize(width: 145.27, height: 64.71), fontSize: 43.2, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 41.41, y: 157.35), size: CGSize(width: 58.11, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "Notes of the month — the songs that carried these days.", position: CGPoint(x: 85.0, y: 176.47), size: CGSize(width: 145.27, height: 29.41), fontSize: 9.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 223.53), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "Nº 05 · PLAYLIST & MUSIC", position: CGPoint(x: 85.0, y: 230.15), size: CGSize(width: 145.27, height: 7.35), fontSize: 6.45, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 85.0, y: 238.23), size: CGSize(width: 145.27, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 27:
            return MagazinePage(title: "PLAYLIST & MUSIC · WRAPPED", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "PLAYLIST & MUSIC · WRAPPED", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 27", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "WRAPPED", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "My Month", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "in Sound.", position: CGPoint(x: 85.0, y: 58.83), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 66.18), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "TOP 5", position: CGPoint(x: 41.41, y: 74), size: CGSize(width: 58.11, height: 9.5), fontSize: 11.0, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 41.41, y: 106.0), size: CGSize(width: 58.11, height: 52.94), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 41.41, y: 106.0), size: CGSize(width: 58.11, height: 52.94), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "TOP ARTIST", position: CGPoint(x: 117.14, y: 84.0), size: CGSize(width: 80.98, height: 6.47), fontSize: 7.8, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 117.14, y: 93.0), size: CGSize(width: 80.98, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "TOP SONG", position: CGPoint(x: 117.14, y: 103.0), size: CGSize(width: 80.98, height: 6.47), fontSize: 7.8, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 117.14, y: 112.0), size: CGSize(width: 80.98, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "A MOOD", position: CGPoint(x: 117.14, y: 122.0), size: CGSize(width: 80.98, height: 6.47), fontSize: 7.8, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 117.14, y: 131.0), size: CGSize(width: 80.98, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "02", position: CGPoint(x: 20.09, y: 154.0), size: CGSize(width: 15.45, height: 8.82), fontSize: 12.96, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "SONG NAME - ARTIST", position: CGPoint(x: 93.5, y: 159.2), size: CGSize(width: 128.3, height: 6.47), fontSize: 6.2, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 93.5, y: 156.4), size: CGSize(width: 128.3, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "03", position: CGPoint(x: 20.09, y: 175.0), size: CGSize(width: 15.45, height: 8.82), fontSize: 12.96, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "SONG NAME - ARTIST", position: CGPoint(x: 93.5, y: 180.2), size: CGSize(width: 128.3, height: 6.47), fontSize: 6.2, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 93.5, y: 177.4), size: CGSize(width: 128.3, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "04", position: CGPoint(x: 20.09, y: 196.0), size: CGSize(width: 15.45, height: 8.82), fontSize: 12.96, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "SONG NAME - ARTIST", position: CGPoint(x: 93.5, y: 201.2), size: CGSize(width: 128.3, height: 6.47), fontSize: 6.2, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 93.5, y: 198.4), size: CGSize(width: 128.3, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "05", position: CGPoint(x: 20.09, y: 217.0), size: CGSize(width: 15.45, height: 8.82), fontSize: 12.96, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "SONG NAME - ARTIST", position: CGPoint(x: 93.5, y: 222.2), size: CGSize(width: 128.3, height: 6.47), fontSize: 6.2, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 93.5, y: 219.4), size: CGSize(width: 128.3, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "27", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 28:
            return MagazinePage(title: "PLAYLIST & MUSIC · FESTIVAL", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "PLAYLIST & MUSIC · FESTIVAL", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 28", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "LIVE FROM MY HEADPHONES", position: CGPoint(x: 85.0, y: 28.68), size: CGSize(width: 145.27, height: 7.35), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "PenPalooza", position: CGPoint(x: 85.0, y: 50.0), size: CGSize(width: 145.27, height: 35.29), fontSize: 33.12, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 58.82), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),

            MagazineElement(type: .text, text: "HEADLINER", position: CGPoint(x: 85.0, y: 72.0), size: CGSize(width: 145.27, height: 8.82), fontSize: 8.8, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 84.5), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "artist · song", position: CGPoint(x: 85.0, y: 87.0), size: CGSize(width: 145.27, height: 6.47), fontSize: 7.2, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "a line about why →", position: CGPoint(x: 85.0, y: 101.0), size: CGSize(width: 145.27, height: 6.47), fontSize: 8.0, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 105.0), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 114.0), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),

            MagazineElement(type: .text, text: "DISCOVERY STAGE", position: CGPoint(x: 85.0, y: 133.0), size: CGSize(width: 145.27, height: 8.82), fontSize: 8.8, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 145.5), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "artist · song", position: CGPoint(x: 85.0, y: 148.0), size: CGSize(width: 145.27, height: 6.47), fontSize: 7.2, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "a line about why →", position: CGPoint(x: 85.0, y: 162.0), size: CGSize(width: 145.27, height: 6.47), fontSize: 8.0, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 166.0), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 175.0), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),

            MagazineElement(type: .text, text: "ON REPEAT", position: CGPoint(x: 85.0, y: 194.0), size: CGSize(width: 145.27, height: 8.82), fontSize: 8.8, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 206.5), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "artist · song", position: CGPoint(x: 85.0, y: 209.0), size: CGSize(width: 145.27, height: 6.47), fontSize: 7.2, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "a line about why →", position: CGPoint(x: 85.0, y: 223.0), size: CGSize(width: 145.27, height: 6.47), fontSize: 8.0, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 227.0), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 236.0), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "28", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 29:
            return MagazinePage(title: "PLAYLIST & MUSIC · LINER NOTES", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "PLAYLIST & MUSIC · LINER NOTES", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 29", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "LINER NOTES", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Album of", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 23.04, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "the Month.", position: CGPoint(x: 85.0, y: 58.83), size: CGSize(width: 145.27, height: 32.35), fontSize: 23.04, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 66.18), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 48.68, y: 108.2), size: CGSize(width: 72.64, height: 69.12), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 48.68, y: 142.76), size: CGSize(width: 72.64, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  cover art", position: CGPoint(x: 48.68, y: 137.76), size: CGSize(width: 72.64, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "ALBUM", position: CGPoint(x: 121.3, y: 76.23), size: CGSize(width: 66.45, height: 6.47), fontSize: 7.0, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 124.41, y: 88.2), size: CGSize(width: 66.45, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "ARTIST", position: CGPoint(x: 121.3, y: 92.41), size: CGSize(width: 66.45, height: 6.47), fontSize: 7.0, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 124.41, y: 102.8), size: CGSize(width: 66.45, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "YEAR", position: CGPoint(x: 103.93, y: 108.58), size: CGSize(width: 31.68, height: 6.47), fontSize: 7.0, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 107.02, y: 119.2), size: CGSize(width: 31.68, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "GENRE", position: CGPoint(x: 139.7, y: 108.58), size: CGSize(width: 31.68, height: 6.47), fontSize: 7.0, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 141.79, y: 119.2), size: CGSize(width: 31.68, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "★ ★ ★ ★ ★", position: CGPoint(x: 124.41, y: 136.0), size: CGSize(width: 66.45, height: 11.76), fontSize: 12.96, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "WHAT STAYED WITH ME", position: CGPoint(x: 85.0, y: 153.71), size: CGSize(width: 145.27, height: 6.47), fontSize: 7.0, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 178.0), size: CGSize(width: 145.27, height: 38.12), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "write here…", position: CGPoint(x: 85.0, y: 162.23), size: CGSize(width: 139.09, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: true, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "FAVOURITE TRACK", position: CGPoint(x: 81.91, y: 207.12), size: CGSize(width: 145.27, height: 6.47), fontSize: 7.0, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 218.0), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "29", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 30:
            return MagazinePage(title: "PLAYLIST & MUSIC · MIXTAPE", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "PLAYLIST & MUSIC · MIXTAPE", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 30", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "MIXTAPE", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Music", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Moodboard.", position: CGPoint(x: 85.0, y: 58.83), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 66.18), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "when I am in my feelings", position: CGPoint(x: 85.0, y: 83.0), size: CGSize(width: 145.27, height: 9.0), fontSize: 11.0, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "artist:", position: CGPoint(x: 31.5, y: 99.0), size: CGSize(width: 32.0, height: 6.47), fontSize: 8.2, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 99.5, y: 102.3), size: CGSize(width: 117.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "song:", position: CGPoint(x: 31.5, y: 113.0), size: CGSize(width: 32.0, height: 6.47), fontSize: 8.2, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 99.5, y: 116.3), size: CGSize(width: 117.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "when I am happy", position: CGPoint(x: 85.0, y: 136.0), size: CGSize(width: 145.27, height: 9.0), fontSize: 11.0, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "artist:", position: CGPoint(x: 31.5, y: 152.0), size: CGSize(width: 32.0, height: 6.47), fontSize: 8.2, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 99.5, y: 155.3), size: CGSize(width: 117.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "song:", position: CGPoint(x: 31.5, y: 166.0), size: CGSize(width: 32.0, height: 6.47), fontSize: 8.2, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 99.5, y: 169.3), size: CGSize(width: 117.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "when I am in love", position: CGPoint(x: 85.0, y: 189.0), size: CGSize(width: 145.27, height: 9.0), fontSize: 11.0, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "artist:", position: CGPoint(x: 31.5, y: 205.0), size: CGSize(width: 32.0, height: 6.47), fontSize: 8.2, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 99.5, y: 208.3), size: CGSize(width: 117.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "song:", position: CGPoint(x: 31.5, y: 219.0), size: CGSize(width: 32.0, height: 6.47), fontSize: 8.2, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 99.5, y: 222.3), size: CGSize(width: 117.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "30", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 31:
            return MagazinePage(title: "06", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "06", position: CGPoint(x: 117.45, y: 35.29), size: CGSize(width: 80.36, height: 47.06), fontSize: 63.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "SECTION", position: CGPoint(x: 43.27, y: 17.65), size: CGSize(width: 61.82, height: 5.88), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 35.54, y: 25.0), size: CGSize(width: 46.36, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "Cinema.", position: CGPoint(x: 85.0, y: 122.06), size: CGSize(width: 145.27, height: 64.71), fontSize: 43.2, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 41.41, y: 157.35), size: CGSize(width: 58.11, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "Tickets, scenes, scores — remembering Oscar-worthy perfomances.", position: CGPoint(x: 85.0, y: 176.47), size: CGSize(width: 145.27, height: 29.41), fontSize: 9.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 223.53), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "Nº 06 · MOVIES & SHOWS", position: CGPoint(x: 85.0, y: 230.15), size: CGSize(width: 145.27, height: 7.35), fontSize: 6.45, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 85.0, y: 238.23), size: CGSize(width: 145.27, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 32:
            return MagazinePage(title: "CINEMA · TICKET STUB", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "CINEMA · TICKET STUB", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 32", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "ADMIT ONE", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "The film of", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 21.6, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "the night.", position: CGPoint(x: 85.0, y: 57.36), size: CGSize(width: 145.27, height: 32.35), fontSize: 21.6, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 64.71), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 123.0), size: CGSize(width: 145.27, height: 108.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL CINEMA", position: CGPoint(x: 85.0, y: 77.0), size: CGSize(width: 145.27, height: 9.5), fontSize: 8.5, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "ADMIT ONE", position: CGPoint(x: 85.0, y: 87.0), size: CGSize(width: 145.27, height: 8.0), fontSize: 7.2, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "TITLE", position: CGPoint(x: 81.91, y: 99.0), size: CGSize(width: 126.73, height: 6.2), fontSize: 7.3, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 108.0), size: CGSize(width: 126.73, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "DIRECTED BY", position: CGPoint(x: 81.91, y: 117.0), size: CGSize(width: 126.73, height: 6.2), fontSize: 7.3, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 126.0), size: CGSize(width: 126.73, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "№ 0001", position: CGPoint(x: 44.82, y: 137.0), size: CGSize(width: 46.36, height: 7.35), fontSize: 8.6, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "ROW", position: CGPoint(x: 103.8, y: 137.0), size: CGSize(width: 13.0, height: 6.76), fontSize: 8.6, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 0, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 120.0, y: 141.2), size: CGSize(width: 15.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "", position: CGPoint(x: 120.0, y: 138.2), size: CGSize(width: 15.0, height: 7.2), fontSize: 7.0, fontName: "Helvetica", isBold: false, isEditableText: true, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 0, height: 1.47)),
            MagazineElement(type: .text, text: "SEAT", position: CGPoint(x: 127.8, y: 137.0), size: CGSize(width: 16.0, height: 6.76), fontSize: 8.6, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 0, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 148.0, y: 141.2), size: CGSize(width: 15.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "", position: CGPoint(x: 148.0, y: 138.2), size: CGSize(width: 15.0, height: 7.2), fontSize: 7.0, fontName: "Helvetica", isBold: false, isEditableText: true, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 0, height: 1.47)),
            MagazineElement(type: .text, text: "RATING", position: CGPoint(x: 44.82, y: 151.0), size: CGSize(width: 46.36, height: 7.35), fontSize: 7.3, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "★ ★ ★ ★ ★", position: CGPoint(x: 55.0, y: 160.0), size: CGSize(width: 68.0, height: 8.82), fontSize: 11.8, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "WHAT I WILL REMEMBER ABOUT IT", position: CGPoint(x: 85.0, y: 184.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 6.7, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 211.35), size: CGSize(width: 145.27, height: 47.06), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "write here…", position: CGPoint(x: 85.0, y: 193.12), size: CGSize(width: 139.09, height: 5.88), fontSize: 6.0, fontName: "Helvetica", isBold: false, isEditableText: true, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "32", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 33:
            return MagazinePage(title: "CINEMA · WATCH LOG", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "CINEMA · WATCH LOG", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 33", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "WATCH LOG", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "What I", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "watched.", position: CGPoint(x: 85.0, y: 58.83), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 66.18), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "DATE", position: CGPoint(x: 23.18, y: 73.23), size: CGSize(width: 21.64, height: 6.47), fontSize: 7.0, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "TITLE", position: CGPoint(x: 75.72, y: 73.23), size: CGSize(width: 77.27, height: 6.47), fontSize: 7.0, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "RATING", position: CGPoint(x: 139.0, y: 73.23), size: CGSize(width: 46.0, height: 6.47), fontSize: 7.0, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 76.47), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "", position: CGPoint(x: 27.0, y: 86.00), size: CGSize(width: 22.0, height: 6.8), fontSize: 6.04, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 25.0, y: 89.10), size: CGSize(width: 18.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 78.0, y: 89.10), size: CGSize(width: 72.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "☆ ☆ ☆ ☆ ☆", position: CGPoint(x: 134.5, y: 86.00), size: CGSize(width: 46.0, height: 7.35), fontSize: 6.0, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "", position: CGPoint(x: 27.0, y: 100.00), size: CGSize(width: 22.0, height: 6.8), fontSize: 6.04, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 25.0, y: 103.10), size: CGSize(width: 18.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 78.0, y: 103.10), size: CGSize(width: 72.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "☆ ☆ ☆ ☆ ☆", position: CGPoint(x: 134.5, y: 100.00), size: CGSize(width: 46.0, height: 7.35), fontSize: 6.0, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "", position: CGPoint(x: 27.0, y: 114.00), size: CGSize(width: 22.0, height: 6.8), fontSize: 6.04, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 25.0, y: 117.10), size: CGSize(width: 18.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 78.0, y: 117.10), size: CGSize(width: 72.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "☆ ☆ ☆ ☆ ☆", position: CGPoint(x: 134.5, y: 114.00), size: CGSize(width: 46.0, height: 7.35), fontSize: 6.0, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "", position: CGPoint(x: 27.0, y: 128.00), size: CGSize(width: 22.0, height: 6.8), fontSize: 6.04, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 25.0, y: 131.10), size: CGSize(width: 18.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 78.0, y: 131.10), size: CGSize(width: 72.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "☆ ☆ ☆ ☆ ☆", position: CGPoint(x: 134.5, y: 128.00), size: CGSize(width: 46.0, height: 7.35), fontSize: 6.0, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "", position: CGPoint(x: 27.0, y: 142.00), size: CGSize(width: 22.0, height: 6.8), fontSize: 6.04, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 25.0, y: 145.10), size: CGSize(width: 18.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 78.0, y: 145.10), size: CGSize(width: 72.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "☆ ☆ ☆ ☆ ☆", position: CGPoint(x: 134.5, y: 142.00), size: CGSize(width: 46.0, height: 7.35), fontSize: 6.0, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "", position: CGPoint(x: 27.0, y: 156.00), size: CGSize(width: 22.0, height: 6.8), fontSize: 6.04, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 25.0, y: 159.10), size: CGSize(width: 18.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 78.0, y: 159.10), size: CGSize(width: 72.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "☆ ☆ ☆ ☆ ☆", position: CGPoint(x: 134.5, y: 156.00), size: CGSize(width: 46.0, height: 7.35), fontSize: 6.0, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "", position: CGPoint(x: 27.0, y: 170.00), size: CGSize(width: 22.0, height: 6.8), fontSize: 6.04, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 25.0, y: 173.10), size: CGSize(width: 18.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 78.0, y: 173.10), size: CGSize(width: 72.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "☆ ☆ ☆ ☆ ☆", position: CGPoint(x: 134.5, y: 170.00), size: CGSize(width: 46.0, height: 7.35), fontSize: 6.0, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "", position: CGPoint(x: 27.0, y: 184.00), size: CGSize(width: 22.0, height: 6.8), fontSize: 6.04, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 25.0, y: 187.10), size: CGSize(width: 18.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 78.0, y: 187.10), size: CGSize(width: 72.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "☆ ☆ ☆ ☆ ☆", position: CGPoint(x: 134.5, y: 184.00), size: CGSize(width: 46.0, height: 7.35), fontSize: 6.0, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "", position: CGPoint(x: 27.0, y: 198.00), size: CGSize(width: 22.0, height: 6.8), fontSize: 6.04, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 25.0, y: 201.10), size: CGSize(width: 18.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 78.0, y: 201.10), size: CGSize(width: 72.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "☆ ☆ ☆ ☆ ☆", position: CGPoint(x: 134.5, y: 198.00), size: CGSize(width: 46.0, height: 7.35), fontSize: 6.0, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "", position: CGPoint(x: 27.0, y: 212.00), size: CGSize(width: 22.0, height: 6.8), fontSize: 6.04, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 25.0, y: 215.10), size: CGSize(width: 18.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 78.0, y: 215.10), size: CGSize(width: 72.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "☆ ☆ ☆ ☆ ☆", position: CGPoint(x: 134.5, y: 212.00), size: CGSize(width: 46.0, height: 7.35), fontSize: 6.0, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "33", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 34:
            return MagazinePage(title: "CINEMA · HIGHLIGHTS", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "CINEMA · HIGHLIGHTS", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 34", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "MOVIE HIGHLIGHTS", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "And the Oscar", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 20.16, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "goes to…", position: CGPoint(x: 85.0, y: 57.36), size: CGSize(width: 145.27, height: 32.35), fontSize: 20.16, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 64.71), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "FEATURE 1", position: CGPoint(x: 38.47, y: 73.09), size: CGSize(width: 56.0, height: 8.82), fontSize: 8.4, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 41.41, y: 111.76), size: CGSize(width: 58.11, height: 61.76), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 41.41, y: 142.65), size: CGSize(width: 58.11, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  poster", position: CGPoint(x: 41.41, y: 137.65), size: CGSize(width: 58.11, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "TITLE", position: CGPoint(x: 114.05, y: 83.52), size: CGSize(width: 80.98, height: 6.47), fontSize: 7.0, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 117.14, y: 92.06), size: CGSize(width: 80.98, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "YEAR", position: CGPoint(x: 93.03, y: 103.53), size: CGSize(width: 38.95, height: 6.47), fontSize: 7.0, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 96.12, y: 112.06), size: CGSize(width: 38.95, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "RUNTIME", position: CGPoint(x: 135.07, y: 103.53), size: CGSize(width: 38.95, height: 6.47), fontSize: 7.0, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 138.16, y: 112.06), size: CGSize(width: 38.95, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "RATING", position: CGPoint(x: 117.14, y: 126.47), size: CGSize(width: 80.98, height: 6.47), fontSize: 7.0, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "☆ ☆ ☆ ☆ ☆", position: CGPoint(x: 117.14, y: 139.7), size: CGSize(width: 80.98, height: 8.82), fontSize: 8.0, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "FEATURE 2", position: CGPoint(x: 38.47, y: 159.56), size: CGSize(width: 56.0, height: 8.82), fontSize: 8.4, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 41.41, y: 198.53), size: CGSize(width: 58.11, height: 61.76), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 41.41, y: 229.41), size: CGSize(width: 58.11, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  poster", position: CGPoint(x: 41.41, y: 224.42), size: CGSize(width: 58.11, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "TITLE", position: CGPoint(x: 114.05, y: 170.3), size: CGSize(width: 80.98, height: 6.47), fontSize: 7.0, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 117.14, y: 178.82), size: CGSize(width: 80.98, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "YEAR", position: CGPoint(x: 93.03, y: 190.3), size: CGSize(width: 38.95, height: 6.47), fontSize: 7.0, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 96.12, y: 198.82), size: CGSize(width: 38.95, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "RUNTIME", position: CGPoint(x: 135.07, y: 190.3), size: CGSize(width: 38.95, height: 6.47), fontSize: 7.0, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 138.16, y: 198.82), size: CGSize(width: 38.95, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "RATING", position: CGPoint(x: 117.14, y: 213.24), size: CGSize(width: 80.98, height: 6.47), fontSize: 7.0, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "☆ ☆ ☆ ☆ ☆", position: CGPoint(x: 117.14, y: 226.47), size: CGSize(width: 80.98, height: 8.82), fontSize: 8.0, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "34", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 35:
            return MagazinePage(title: "07", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "07", position: CGPoint(x: 117.45, y: 35.29), size: CGSize(width: 80.36, height: 47.06), fontSize: 63.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "SECTION", position: CGPoint(x: 43.27, y: 17.65), size: CGSize(width: 61.82, height: 5.88), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 35.54, y: 25.0), size: CGSize(width: 46.36, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "Reading.", position: CGPoint(x: 85.0, y: 122.06), size: CGSize(width: 145.27, height: 64.71), fontSize: 43.2, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 41.41, y: 157.35), size: CGSize(width: 58.11, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "Stories worth remembering — pages, lines, and the lives they opened.", position: CGPoint(x: 85.0, y: 176.47), size: CGSize(width: 145.27, height: 29.41), fontSize: 9.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 223.53), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "Nº 07 · READING", position: CGPoint(x: 85.0, y: 230.15), size: CGSize(width: 145.27, height: 7.35), fontSize: 6.45, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 85.0, y: 238.23), size: CGSize(width: 145.27, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 36:
            return MagazinePage(title: "READING · BOOKPLATE", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "READING · BOOKPLATE", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 36", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "BOOKPLATE", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Ex Libris.", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 23.04, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 60.18), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 148.0), size: CGSize(width: 135.0, height: 156.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 148.0), size: CGSize(width: 126.0, height: 146.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "EX LIBRIS", position: CGPoint(x: 85.0, y: 85.0), size: CGSize(width: 108.18, height: 20.59), fontSize: 18.0, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "✦", position: CGPoint(x: 85.0, y: 101.0), size: CGSize(width: 15.45, height: 10.0), fontSize: 11.52, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "TITLE", position: CGPoint(x: 85.0, y: 113.0), size: CGSize(width: 108.18, height: 5.29), fontSize: 6.7, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 123.0), size: CGSize(width: 108.18, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "AUTHOR", position: CGPoint(x: 85.0, y: 135.0), size: CGSize(width: 108.18, height: 5.29), fontSize: 6.7, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 145.0), size: CGSize(width: 108.18, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "A LINE WORTH KEEPING", position: CGPoint(x: 85.0, y: 157.0), size: CGSize(width: 108.18, height: 5.29), fontSize: 6.7, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 189.0), size: CGSize(width: 108.18, height: 50.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "write here…", position: CGPoint(x: 85.0, y: 168.0), size: CGSize(width: 102.0, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: true, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "36", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 37:
            return MagazinePage(title: "READING · MARGIN NOTES", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "READING · MARGIN NOTES", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 37", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "MARGIN NOTES", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Book of", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 23.04, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "the Month.", position: CGPoint(x: 85.0, y: 58.83), size: CGSize(width: 145.27, height: 32.35), fontSize: 23.04, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 66.18), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 41.41, y: 105.89), size: CGSize(width: 58.11, height: 70.59), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 41.41, y: 141.18), size: CGSize(width: 58.11, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  cover", position: CGPoint(x: 41.41, y: 136.18), size: CGSize(width: 58.11, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "TITLE", position: CGPoint(x: 117.14, y: 78.0), size: CGSize(width: 80.98, height: 6.0), fontSize: 6.4, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 117.14, y: 88.0), size: CGSize(width: 80.98, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "AUTHOR", position: CGPoint(x: 117.14, y: 96.0), size: CGSize(width: 80.98, height: 6.0), fontSize: 6.4, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 117.14, y: 106.0), size: CGSize(width: 80.98, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "GENRE", position: CGPoint(x: 117.14, y: 114.0), size: CGSize(width: 80.98, height: 6.0), fontSize: 6.4, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 117.14, y: 124.0), size: CGSize(width: 80.98, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "★ ★ ★ ★ ★", position: CGPoint(x: 117.14, y: 138.23), size: CGSize(width: 80.98, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "writing", position: CGPoint(x: 30.91, y: 151.00), size: CGSize(width: 42.0, height: 6.47), fontSize: 8.2, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "__BOOK_REVIEW_HINT__", position: CGPoint(x: 103.54, y: 151.73), size: CGSize(width: 108.18, height: 3.82), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 76.5, y: 151.73), size: CGSize(width: 54.09, height: 3.82), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "characters", position: CGPoint(x: 30.91, y: 164.00), size: CGSize(width: 42.0, height: 6.47), fontSize: 8.2, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "__BOOK_REVIEW_HINT__", position: CGPoint(x: 103.54, y: 164.73), size: CGSize(width: 108.18, height: 3.82), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 76.5, y: 164.73), size: CGSize(width: 54.09, height: 3.82), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "plot", position: CGPoint(x: 30.91, y: 177.00), size: CGSize(width: 42.0, height: 6.47), fontSize: 8.2, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "__BOOK_REVIEW_HINT__", position: CGPoint(x: 103.54, y: 177.73), size: CGSize(width: 108.18, height: 3.82), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 76.5, y: 177.73), size: CGSize(width: 54.09, height: 3.82), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "feeling", position: CGPoint(x: 30.91, y: 190.00), size: CGSize(width: 42.0, height: 6.47), fontSize: 8.2, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "__BOOK_REVIEW_HINT__", position: CGPoint(x: 103.54, y: 190.73), size: CGSize(width: 108.18, height: 3.82), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 76.5, y: 190.73), size: CGSize(width: 54.09, height: 3.82), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "FINAL THOUGHTS", position: CGPoint(x: 85.0, y: 205.0), size: CGSize(width: 145.27, height: 5.29), fontSize: 8.2, fontName: "Helvetica", isBold: true, isEditableText: true, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 222.5), size: CGSize(width: 145.27, height: 28.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "write here…", position: CGPoint(x: 85.0, y: 212.0), size: CGSize(width: 139.09, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: true, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "37", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 38:
            return MagazinePage(title: "READING · MINI REVIEWS", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "READING · MINI REVIEWS", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 38", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "MARGIN NOTES", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Mini", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Reviews.", position: CGPoint(x: 85.0, y: 58.83), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 66.18), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 32.45, y: 95.59), size: CGSize(width: 40.18, height: 50.0), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 32.45, y: 120.59), size: CGSize(width: 40.18, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  cover", position: CGPoint(x: 32.45, y: 115.58), size: CGSize(width: 40.18, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "TITLE", position: CGPoint(x: 108.19, y: 73.23), size: CGSize(width: 98.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 108.19, y: 81.76), size: CGSize(width: 98.91, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "AUTHOR", position: CGPoint(x: 82.69, y: 89.41), size: CGSize(width: 47.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 82.69, y: 97.94), size: CGSize(width: 47.91, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "GENRE", position: CGPoint(x: 133.69, y: 89.41), size: CGSize(width: 47.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 133.69, y: 97.94), size: CGSize(width: 47.91, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "★ ★ ★ ★ ★", position: CGPoint(x: 108.19, y: 107.35), size: CGSize(width: 98.91, height: 10.29), fontSize: 11.52, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 32.45, y: 150.0), size: CGSize(width: 40.18, height: 50.0), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 32.45, y: 175.0), size: CGSize(width: 40.18, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  cover", position: CGPoint(x: 32.45, y: 170.0), size: CGSize(width: 40.18, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "TITLE", position: CGPoint(x: 108.19, y: 127.64), size: CGSize(width: 98.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 108.19, y: 136.18), size: CGSize(width: 98.91, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "AUTHOR", position: CGPoint(x: 82.69, y: 143.83), size: CGSize(width: 47.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 82.69, y: 152.35), size: CGSize(width: 47.91, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "GENRE", position: CGPoint(x: 133.69, y: 143.83), size: CGSize(width: 47.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 133.69, y: 152.35), size: CGSize(width: 47.91, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "★ ★ ★ ★ ★", position: CGPoint(x: 108.19, y: 161.76), size: CGSize(width: 98.91, height: 10.29), fontSize: 11.52, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 32.45, y: 204.41), size: CGSize(width: 40.18, height: 50.0), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 32.45, y: 229.41), size: CGSize(width: 40.18, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  cover", position: CGPoint(x: 32.45, y: 224.42), size: CGSize(width: 40.18, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "TITLE", position: CGPoint(x: 108.19, y: 182.06), size: CGSize(width: 98.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 108.19, y: 190.59), size: CGSize(width: 98.91, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "AUTHOR", position: CGPoint(x: 82.69, y: 198.24), size: CGSize(width: 47.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 82.69, y: 206.76), size: CGSize(width: 47.91, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "GENRE", position: CGPoint(x: 133.69, y: 198.24), size: CGSize(width: 47.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 133.69, y: 206.76), size: CGSize(width: 47.91, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "★ ★ ★ ★ ★", position: CGPoint(x: 108.19, y: 216.18), size: CGSize(width: 98.91, height: 10.29), fontSize: 11.52, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "38", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 39:
            return MagazinePage(title: "READING · TBR STACK", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "READING · TBR STACK", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 39", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "TO BE READ", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "To be", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "read.", position: CGPoint(x: 85.0, y: 58.83), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 66.18), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            
            MagazineElement(type: .image, text: "", position: CGPoint(x: 30.0, y: 105.0), size: CGSize(width: 36.0, height: 46.0), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "cover", position: CGPoint(x: 30.0, y: 119.0), size: CGSize(width: 36.0, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 108.0, y: 105.0), size: CGSize(width: 96.0, height: 44.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "TITLE", position: CGPoint(x: 110.0, y: 90.0), size: CGSize(width: 90.0, height: 6.2), fontSize: 8, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 108.0, y: 101.0), size: CGSize(width: 80.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "AUTHOR", position: CGPoint(x: 110.0, y: 111.0), size: CGSize(width: 90.0, height: 6.2), fontSize: 8, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 108.0, y: 119.0), size: CGSize(width: 80.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 30.0, y: 157.0), size: CGSize(width: 36.0, height: 46.0), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "cover", position: CGPoint(x: 30.0, y: 171.0), size: CGSize(width: 36.0, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 108.0, y: 157.0), size: CGSize(width: 96.0, height: 44.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "TITLE", position: CGPoint(x: 110.0, y: 142.0), size: CGSize(width: 90.0, height: 6.2), fontSize: 8, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 108.0, y: 153.0), size: CGSize(width: 80.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "AUTHOR", position: CGPoint(x: 110.0, y: 163.0), size: CGSize(width: 90.0, height: 6.2), fontSize: 8, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 108.0, y: 171.0), size: CGSize(width: 80.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 30.0, y: 209.0), size: CGSize(width: 36.0, height: 46.0), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "cover", position: CGPoint(x: 30.0, y: 223.0), size: CGSize(width: 36.0, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 108.0, y: 209.0), size: CGSize(width: 96.0, height: 44.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "TITLE", position: CGPoint(x: 110.0, y: 194.0), size: CGSize(width: 90.0, height: 6.2), fontSize: 8, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 108.0, y: 205.0), size: CGSize(width: 80.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "AUTHOR", position: CGPoint(x: 110.0, y: 215.0), size: CGSize(width: 90.0, height: 6.2), fontSize: 8, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 108.0, y: 223.0), size: CGSize(width: 80.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "39", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 40:
            return MagazinePage(title: "08", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "08", position: CGPoint(x: 117.45, y: 35.29), size: CGSize(width: 80.36, height: 47.06), fontSize: 63.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "SECTION", position: CGPoint(x: 43.27, y: 17.65), size: CGSize(width: 61.82, height: 5.88), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 35.54, y: 25.0), size: CGSize(width: 46.36, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "Food & Recipes.", position: CGPoint(x: 85.0, y: 122.06), size: CGSize(width: 145.27, height: 64.71), fontSize: 43.2, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 41.41, y: 157.35), size: CGSize(width: 58.11, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "From the kitchen — the dishes, the table, the small rituals of the month.", position: CGPoint(x: 85.0, y: 176.47), size: CGSize(width: 145.27, height: 29.41), fontSize: 9.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 223.53), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "Nº 08 · FOOD & RECIPES", position: CGPoint(x: 85.0, y: 230.15), size: CGSize(width: 145.27, height: 7.35), fontSize: 6.45, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 85.0, y: 238.23), size: CGSize(width: 145.27, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 41:
            return MagazinePage(title: "FOOD & RECIPES · CULINARY CREATIONS", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "FOOD & RECIPES · CULINARY CREATIONS", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 41", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "CULINARY CREATIONS", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "My culinary", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "creations.", position: CGPoint(x: 85.0, y: 58.83), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 66.18), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 54.39, y: 105.89), size: CGSize(width: 84.07, height: 70.59), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 54.39, y: 141.18), size: CGSize(width: 84.07, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  photo · large", position: CGPoint(x: 54.39, y: 136.18), size: CGSize(width: 84.07, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 130.13, y: 87.5), size: CGSize(width: 55.02, height: 33.82), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 130.13, y: 104.41), size: CGSize(width: 55.02, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  photo", position: CGPoint(x: 130.13, y: 99.42), size: CGSize(width: 55.02, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 130.13, y: 124.26), size: CGSize(width: 55.02, height: 33.82), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 130.13, y: 141.18), size: CGSize(width: 55.02, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  photo", position: CGPoint(x: 130.13, y: 136.18), size: CGSize(width: 55.02, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 39.87, y: 166.18), size: CGSize(width: 55.02, height: 41.18), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 39.87, y: 186.76), size: CGSize(width: 55.02, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  photo", position: CGPoint(x: 39.87, y: 181.77), size: CGSize(width: 55.02, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 115.59, y: 166.18), size: CGSize(width: 84.07, height: 41.18), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 115.59, y: 186.76), size: CGSize(width: 84.07, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  photo · wide", position: CGPoint(x: 115.59, y: 181.77), size: CGSize(width: 84.07, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 85.0, y: 211.77), size: CGSize(width: 145.27, height: 41.18), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 232.35), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  photo · banner", position: CGPoint(x: 85.0, y: 227.36), size: CGSize(width: 145.27, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "41", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 42:
            return MagazinePage(title: "FOOD & RECIPES · WEEK ON A PLA", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "FOOD & RECIPES · WEEK ON A PLATE", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 42", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "WEEK ON A PLATE", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "A week,", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 23.04, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "on a plate.", position: CGPoint(x: 85.0, y: 58.83), size: CGSize(width: 145.27, height: 32.35), fontSize: 23.04, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 66.18), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "DAY", position: CGPoint(x: 21.63, y: 73.53), size: CGSize(width: 18.55, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "BREAKFAST", position: CGPoint(x: 55.64, y: 73.53), size: CGSize(width: 43.27, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "LUNCH", position: CGPoint(x: 102.0, y: 73.53), size: CGSize(width: 43.27, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "DINNER", position: CGPoint(x: 148.37, y: 73.53), size: CGSize(width: 43.27, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 76.47), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "MON", position: CGPoint(x: 23.18, y: 85.29), size: CGSize(width: 21.64, height: 8.82), fontSize: 9.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 52.8, y: 90.59), size: CGSize(width: 37.61, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 93.5, y: 90.59), size: CGSize(width: 37.61, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 134.19, y: 90.59), size: CGSize(width: 37.61, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 98.53), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "TUE", position: CGPoint(x: 21.63, y: 105.88), size: CGSize(width: 18.55, height: 8.82), fontSize: 9.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 52.8, y: 111.18), size: CGSize(width: 37.61, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 93.5, y: 111.18), size: CGSize(width: 37.61, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 134.19, y: 111.18), size: CGSize(width: 37.61, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 119.12), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "WED", position: CGPoint(x: 23.18, y: 126.47), size: CGSize(width: 21.64, height: 8.82), fontSize: 9.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 52.8, y: 131.76), size: CGSize(width: 37.61, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 93.5, y: 131.76), size: CGSize(width: 37.61, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 134.19, y: 131.76), size: CGSize(width: 37.61, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 139.71), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "THU", position: CGPoint(x: 21.63, y: 147.06), size: CGSize(width: 18.55, height: 8.82), fontSize: 9.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 52.8, y: 152.35), size: CGSize(width: 37.61, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 93.5, y: 152.35), size: CGSize(width: 37.61, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 134.19, y: 152.35), size: CGSize(width: 37.61, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 160.29), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "FRI", position: CGPoint(x: 21.63, y: 167.65), size: CGSize(width: 18.55, height: 8.82), fontSize: 9.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 52.8, y: 172.94), size: CGSize(width: 37.61, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 93.5, y: 172.94), size: CGSize(width: 37.61, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 134.19, y: 172.94), size: CGSize(width: 37.61, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 180.88), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "SAT", position: CGPoint(x: 21.63, y: 188.23), size: CGSize(width: 18.55, height: 8.82), fontSize: 9.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 52.8, y: 193.53), size: CGSize(width: 37.61, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 93.5, y: 193.53), size: CGSize(width: 37.61, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 134.19, y: 193.53), size: CGSize(width: 37.61, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 201.47), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "SUN", position: CGPoint(x: 21.63, y: 208.82), size: CGSize(width: 18.55, height: 8.82), fontSize: 9.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 52.8, y: 214.12), size: CGSize(width: 37.61, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 93.5, y: 214.12), size: CGSize(width: 37.61, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 134.19, y: 214.12), size: CGSize(width: 37.61, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "42", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 43:
            return MagazinePage(title: "FOOD & RECIPES · TABLE FOR ONE", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "FOOD & RECIPES · TABLE FOR ONE", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 43", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "TABLE FOR ONE", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Table", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "for", position: CGPoint(x: 85.0, y: 58.83), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 55.0, y: 57.8), size: CGSize(width: 22.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: ".", position: CGPoint(x: 77.5, y: 58.83), size: CGSize(width: 10.0, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 0, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 66.18), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PLACE", position: CGPoint(x: 85.0, y: 72.8), size: CGSize(width: 145.27, height: 5.29), fontSize: 8.0, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 83.2), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "DATE", position: CGPoint(x: 50.99, y: 91.0), size: CGSize(width: 77.27, height: 5.29), fontSize: 8.0, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "", position: CGPoint(x: 48.68, y: 99.8), size: CGSize(width: 72.64, height: 5.29), fontSize: 5.1, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 48.68, y: 101.0), size: CGSize(width: 72.64, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "OCCASION", position: CGPoint(x: 126.73, y: 91.0), size: CGSize(width: 61.82, height: 5.29), fontSize: 8.0, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 126.73, y: 101.0), size: CGSize(width: 61.82, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 85.0, y: 139.0), size: CGSize(width: 145.27, height: 64.71), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 171.36), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  the meal", position: CGPoint(x: 85.0, y: 166.36), size: CGSize(width: 145.27, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "ATMOSPHERE", position: CGPoint(x: 42.0, y: 176.5), size: CGSize(width: 49.45, height: 6.47), fontSize: 7.1, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "☆☆☆☆☆", position: CGPoint(x: 108.0, y: 176.5), size: CGSize(width: 62.0, height: 7.4), fontSize: 6.1, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "FOOD", position: CGPoint(x: 42.0, y: 187.1), size: CGSize(width: 49.45, height: 6.47), fontSize: 7.1, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "☆☆☆☆☆", position: CGPoint(x: 108.0, y: 187.1), size: CGSize(width: 62.0, height: 7.4), fontSize: 6.1, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "SERVICE", position: CGPoint(x: 42.0, y: 197.7), size: CGSize(width: 49.45, height: 6.47), fontSize: 7.1, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "☆☆☆☆☆", position: CGPoint(x: 108.0, y: 197.7), size: CGSize(width: 62.0, height: 7.4), fontSize: 6.1, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "VALUE", position: CGPoint(x: 42.0, y: 208.3), size: CGSize(width: 49.45, height: 6.47), fontSize: 7.1, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "☆☆☆☆☆", position: CGPoint(x: 108.0, y: 208.3), size: CGSize(width: 62.0, height: 7.4), fontSize: 6.1, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "WORTH RETURNING?", position: CGPoint(x: 85.0, y: 224.71), size: CGSize(width: 145.27, height: 5.29), fontSize: 6.9, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 34.0, y: 233.82), size: CGSize(width: 36.5, height: 9.2), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "YES", position: CGPoint(x: 34.0, y: 233.82), size: CGSize(width: 36.5, height: 9.2), fontSize: 6.2, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 83.45, y: 233.82), size: CGSize(width: 36.5, height: 9.2), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "NO", position: CGPoint(x: 83.45, y: 233.82), size: CGSize(width: 36.5, height: 9.2), fontSize: 6.2, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 132.91, y: 233.82), size: CGSize(width: 36.5, height: 9.2), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "MAYBE", position: CGPoint(x: 132.91, y: 233.82), size: CGSize(width: 36.5, height: 9.2), fontSize: 6.2, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "43", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 44:
            return MagazinePage(title: "09", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "09", position: CGPoint(x: 117.45, y: 35.29), size: CGSize(width: 80.36, height: 47.06), fontSize: 63.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "SECTION", position: CGPoint(x: 43.27, y: 17.65), size: CGSize(width: 61.82, height: 5.88), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 35.54, y: 25.0), size: CGSize(width: 46.36, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "Travel & Places.", position: CGPoint(x: 85.0, y: 122.06), size: CGSize(width: 145.27, height: 64.71), fontSize: 43.2, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 41.41, y: 157.35), size: CGSize(width: 58.11, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "Postcards from everywhere worth exploring and remembering.", position: CGPoint(x: 85.0, y: 176.47), size: CGSize(width: 145.27, height: 29.41), fontSize: 9.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 223.53), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "Nº 09 · TRAVEL & PLACES", position: CGPoint(x: 85.0, y: 230.15), size: CGSize(width: 145.27, height: 7.35), fontSize: 6.45, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 85.0, y: 238.23), size: CGSize(width: 145.27, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 45:
            return MagazinePage(title: "TRAVEL · POSTCARD", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "TRAVEL · POSTCARD", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 45", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "POSTCARD", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Wish you", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "were here.", position: CGPoint(x: 85.0, y: 58.83), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 66.18), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 148.0), size: CGSize(width: 145.27, height: 154.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 85.0, y: 108.83), size: CGSize(width: 136.0, height: 67.65), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 142.65), size: CGSize(width: 136.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  the view", position: CGPoint(x: 85.0, y: 137.65), size: CGSize(width: 136.0, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "Greetings from", position: CGPoint(x: 48.69, y: 152.94), size: CGSize(width: 60.27, height: 8.82), fontSize: 9.16, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 48.69, y: 168.5), size: CGSize(width: 60.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "a place", position: CGPoint(x: 48.69, y: 171.15), size: CGSize(width: 60.27, height: 4.12), fontSize: 5.1, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 48.69, y: 184.0), size: CGSize(width: 60.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 48.69, y: 199.5), size: CGSize(width: 60.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 48.69, y: 215.0), size: CGSize(width: 60.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "", position: CGPoint(x: 48.69, y: 203.68), size: CGSize(width: 60.27, height: 7.35), fontSize: 7.63, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 140.26, y: 157.06), size: CGSize(width: 22.41, height: 22.35), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "✦", position: CGPoint(x: 140.64, y: 156.81), size: CGSize(width: 23.18, height: 27.94), fontSize: 17.28, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "STAMP", position: CGPoint(x: 141.41, y: 165.79), size: CGSize(width: 23.18, height: 4.41), fontSize: 5.1, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "TO", position: CGPoint(x: 97.36, y: 170.0), size: CGSize(width: 15.45, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 121.32, y: 184.0), size: CGSize(width: 63.36, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 121.32, y: 199.5), size: CGSize(width: 63.36, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 121.32, y: 215.0), size: CGSize(width: 63.36, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "45", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 46:
            return MagazinePage(title: "TRAVEL · PLACES SEEN", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "TRAVEL · PLACES SEEN", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 46", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PLACES SEEN", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Places", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "seen.", position: CGPoint(x: 85.0, y: 58.83), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 66.18), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 54.39, y: 105.89), size: CGSize(width: 84.07, height: 70.59), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 54.39, y: 141.18), size: CGSize(width: 84.07, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  photo · large", position: CGPoint(x: 54.39, y: 136.18), size: CGSize(width: 84.07, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 130.13, y: 87.5), size: CGSize(width: 55.02, height: 33.82), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 130.13, y: 104.41), size: CGSize(width: 55.02, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  photo", position: CGPoint(x: 130.13, y: 99.42), size: CGSize(width: 55.02, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 130.13, y: 124.26), size: CGSize(width: 55.02, height: 33.82), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 130.13, y: 141.18), size: CGSize(width: 55.02, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  photo", position: CGPoint(x: 130.13, y: 136.18), size: CGSize(width: 55.02, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 39.87, y: 166.18), size: CGSize(width: 55.02, height: 41.18), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 39.87, y: 186.76), size: CGSize(width: 55.02, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  photo", position: CGPoint(x: 39.87, y: 181.77), size: CGSize(width: 55.02, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 115.59, y: 166.18), size: CGSize(width: 84.07, height: 41.18), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 115.59, y: 186.76), size: CGSize(width: 84.07, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  photo · wide", position: CGPoint(x: 115.59, y: 181.77), size: CGSize(width: 84.07, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 85.0, y: 211.77), size: CGSize(width: 145.27, height: 41.18), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 232.35), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  photo · banner", position: CGPoint(x: 85.0, y: 227.36), size: CGSize(width: 145.27, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "46", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 47:
            return MagazinePage(title: "TRAVEL · PLACES SEEN", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "TRAVEL · PLACES SEEN", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 47", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PLACES SEEN", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Places", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "seen.", position: CGPoint(x: 85.0, y: 58.83), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 66.18), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PLACE", position: CGPoint(x: 43.27, y: 73.53), size: CGSize(width: 61.82, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "WHEN", position: CGPoint(x: 95.81, y: 73.53), size: CGSize(width: 30.91, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "A MEMORY", position: CGPoint(x: 137.54, y: 73.53), size: CGSize(width: 40.18, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 76.47), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 44.81, y: 89.12), size: CGSize(width: 64.91, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 97.36, y: 89.12), size: CGSize(width: 34.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 137.54, y: 89.12), size: CGSize(width: 40.18, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 44.81, y: 103.82), size: CGSize(width: 64.91, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 97.36, y: 103.82), size: CGSize(width: 34.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 137.54, y: 103.82), size: CGSize(width: 40.18, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 44.81, y: 118.53), size: CGSize(width: 64.91, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 97.36, y: 118.53), size: CGSize(width: 34.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 137.54, y: 118.53), size: CGSize(width: 40.18, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 44.81, y: 133.24), size: CGSize(width: 64.91, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 97.36, y: 133.24), size: CGSize(width: 34.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 137.54, y: 133.24), size: CGSize(width: 40.18, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 44.81, y: 147.94), size: CGSize(width: 64.91, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 97.36, y: 147.94), size: CGSize(width: 34.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 137.54, y: 147.94), size: CGSize(width: 40.18, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 44.81, y: 162.65), size: CGSize(width: 64.91, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 97.36, y: 162.65), size: CGSize(width: 34.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 137.54, y: 162.65), size: CGSize(width: 40.18, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 44.81, y: 177.35), size: CGSize(width: 64.91, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 97.36, y: 177.35), size: CGSize(width: 34.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 137.54, y: 177.35), size: CGSize(width: 40.18, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 44.81, y: 192.06), size: CGSize(width: 64.91, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 97.36, y: 192.06), size: CGSize(width: 34.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 137.54, y: 192.06), size: CGSize(width: 40.18, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 44.81, y: 206.76), size: CGSize(width: 64.91, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 97.36, y: 206.76), size: CGSize(width: 34.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 137.54, y: 206.76), size: CGSize(width: 40.18, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 44.81, y: 221.47), size: CGSize(width: 64.91, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 97.36, y: 221.47), size: CGSize(width: 34.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 137.54, y: 221.47), size: CGSize(width: 40.18, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "47", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 48:
            return MagazinePage(title: "10", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "10", position: CGPoint(x: 117.45, y: 35.29), size: CGSize(width: 80.36, height: 47.06), fontSize: 63.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "SECTION", position: CGPoint(x: 43.27, y: 17.65), size: CGSize(width: 61.82, height: 5.88), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 35.54, y: 25.0), size: CGSize(width: 46.36, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "Favourites.", position: CGPoint(x: 85.0, y: 122.06), size: CGSize(width: 145.27, height: 64.71), fontSize: 43.2, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 41.41, y: 157.35), size: CGSize(width: 58.11, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "The small obsessions — the things kept close, this month.", position: CGPoint(x: 85.0, y: 176.47), size: CGSize(width: 145.27, height: 29.41), fontSize: 9.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 223.53), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "Nº 10 · MONTHLY FAVOURITES", position: CGPoint(x: 85.0, y: 230.15), size: CGSize(width: 145.27, height: 7.35), fontSize: 6.45, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 85.0, y: 238.23), size: CGSize(width: 145.27, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 49:
            return MagazinePage(title: "FAVOURITES · BEAUTY SHELF", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "FAVOURITES · BEAUTY SHELF", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 49", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "MY RECOMMENDATIONS", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Beauty", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Shelf.", position: CGPoint(x: 85.0, y: 58.83), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 66.18), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 36.0, y: 106), size: CGSize(width: 49.0, height: 63.0), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  product", position: CGPoint(x: 36.0, y: 134), size: CGSize(width: 49.0, height: 6.47), fontSize: 6.2, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "BRAND / PRODUCT", position: CGPoint(x: 111.5, y: 74.5), size: CGSize(width: 92.0, height: 5.29), fontSize: 6.8, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 111.5, y: 83.5), size: CGSize(width: 92.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "WHY I LOVE IT →", position: CGPoint(x: 111.5, y: 93.5), size: CGSize(width: 92.0, height: 5.29), fontSize: 6.8, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 111.5, y: 109), size: CGSize(width: 92.0, height: 25.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "RATING →", position: CGPoint(x: 111.5, y: 128), size: CGSize(width: 92.0, height: 5.29), fontSize: 6.8, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "★ ★ ★ ★ ★", position: CGPoint(x: 111.5, y: 135), size: CGSize(width: 92.0, height: 8.82), fontSize: 10.08, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 36.0, y: 193), size: CGSize(width: 49.0, height: 63.0), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  product", position: CGPoint(x: 36.0, y: 221), size: CGSize(width: 49.0, height: 6.47), fontSize: 6.2, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "BRAND / PRODUCT", position: CGPoint(x: 111.5, y: 161.5), size: CGSize(width: 92.0, height: 5.29), fontSize: 6.8, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 111.5, y: 170.5), size: CGSize(width: 92.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "WHY I LOVE IT →", position: CGPoint(x: 111.5, y: 180.5), size: CGSize(width: 92.0, height: 5.29), fontSize: 6.8, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 111.5, y: 196), size: CGSize(width: 92.0, height: 25.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "RATING →", position: CGPoint(x: 111.5, y: 215), size: CGSize(width: 92.0, height: 5.29), fontSize: 6.8, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "★ ★ ★ ★ ★", position: CGPoint(x: 111.5, y: 222), size: CGSize(width: 92.0, height: 8.82), fontSize: 10.08, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "49", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 50:
            return MagazinePage(title: "FAVOURITES · EDIBLE", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "FAVOURITES · EDIBLE", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 50", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "EDIBLE FAVOURITES", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Worth a", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "return trip.", position: CGPoint(x: 85.0, y: 58.83), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 66.18), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 85.0, y: 95.59), size: CGSize(width: 145.27, height: 50.0), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 120.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  the meal of the month", position: CGPoint(x: 85.0, y: 115.58), size: CGSize(width: 145.27, height: 6.47), fontSize: 6.2, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "RESTAURANT", position: CGPoint(x: 46.36, y: 129.12), size: CGSize(width: 68.0, height: 7.0), fontSize: 8.2, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 46.36, y: 132.35), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "NAME →", position: CGPoint(x: 46.36, y: 137.94), size: CGSize(width: 68.0, height: 5.29), fontSize: 6.6, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 46.36, y: 148.0), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "WHERE →", position: CGPoint(x: 46.36, y: 155.0), size: CGSize(width: 68.0, height: 5.29), fontSize: 6.6, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 46.36, y: 164.0), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "WHAT I ORDERED →", position: CGPoint(x: 46.36, y: 172.0), size: CGSize(width: 68.0, height: 5.29), fontSize: 6.6, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 46.36, y: 181.0), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "CAFÉ / BAR", position: CGPoint(x: 123.64, y: 129.12), size: CGSize(width: 68.0, height: 7.0), fontSize: 8.2, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 123.64, y: 132.35), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "NAME →", position: CGPoint(x: 123.64, y: 137.94), size: CGSize(width: 68.0, height: 5.29), fontSize: 6.6, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 123.64, y: 148.0), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "WHERE →", position: CGPoint(x: 123.64, y: 155.0), size: CGSize(width: 68.0, height: 5.29), fontSize: 6.6, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 123.64, y: 164.0), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "WHAT I ORDERED →", position: CGPoint(x: 123.64, y: 172.0), size: CGSize(width: 68.0, height: 5.29), fontSize: 6.6, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 123.64, y: 181.0), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 46.36, y: 194.0), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 46.36, y: 207.0), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 123.64, y: 194.0), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 123.64, y: 207.0), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),

            MagazineElement(type: .text, text: "☆☆☆☆☆", position: CGPoint(x: 46.36, y: 222.0), size: CGSize(width: 68.0, height: 6.2), fontSize: 6.8, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 0, height: 0)),
            MagazineElement(type: .text, text: "☆☆☆☆☆", position: CGPoint(x: 123.64, y: 222.0), size: CGSize(width: 68.0, height: 6.2), fontSize: 6.8, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 0, height: 0)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "50", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 51:
            return MagazinePage(title: "FAVOURITES · APPS & INTERNET", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "FAVOURITES · APPS & INTERNET", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 6.4, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 51", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "MY RECOMMENDATIONS", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Apps &", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Internet.", position: CGPoint(x: 85.0, y: 58.83), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 69.71), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "APP / PODCAST / SITE", position: CGPoint(x: 46.36, y: 84.41), size: CGSize(width: 68.0, height: 5.8), fontSize: 7.4, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 46.36, y: 93.5), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "name", position: CGPoint(x: 46.36, y: 99.0), size: CGSize(width: 68.0, height: 5.2), fontSize: 6.8, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "WHAT IT’S ABOUT", position: CGPoint(x: 46.36, y: 108.5), size: CGSize(width: 68.0, height: 6.2), fontSize: 6.9, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 46.36, y: 128.5), size: CGSize(width: 68.0, height: 34.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "APP / PODCAST / SITE", position: CGPoint(x: 123.64, y: 84.41), size: CGSize(width: 68.0, height: 5.8), fontSize: 7.4, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 123.64, y: 93.5), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "name", position: CGPoint(x: 123.64, y: 99.0), size: CGSize(width: 68.0, height: 5.2), fontSize: 6.8, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 123.64, y: 128.5), size: CGSize(width: 68.0, height: 34.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "APP / PODCAST / SITE", position: CGPoint(x: 47.59, y: 158.0), size: CGSize(width: 68.0, height: 5.8), fontSize: 7.4, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 47.59, y: 167.6), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "name", position: CGPoint(x: 47.59, y: 173.0), size: CGSize(width: 68.0, height: 5.2), fontSize: 6.8, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 47.59, y: 202.5), size: CGSize(width: 68.0, height: 34.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "APP / PODCAST / SITE", position: CGPoint(x: 124.86, y: 158.0), size: CGSize(width: 68.0, height: 5.8), fontSize: 7.4, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 124.86, y: 167.6), size: CGSize(width: 68.0, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "name", position: CGPoint(x: 124.86, y: 173.0), size: CGSize(width: 68.0, height: 5.2), fontSize: 6.8, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 124.86, y: 202.5), size: CGSize(width: 68.0, height: 34.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 6.4, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "51", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "WHAT IT’S ABOUT", position: CGPoint(x: 123.64, y: 108.5), size: CGSize(width: 68.0, height: 6.2), fontSize: 6.9, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "WHAT IT’S ABOUT", position: CGPoint(x: 47.59, y: 182.0), size: CGSize(width: 68.0, height: 6.2), fontSize: 6.9, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "WHAT IT’S ABOUT", position: CGPoint(x: 124.86, y: 182.0), size: CGSize(width: 68.0, height: 6.2), fontSize: 6.9, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 52:
            return MagazinePage(title: "FAVOURITES · RITUALS", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "FAVOURITES · RITUALS", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 52", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "MY ROUTINES", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Rituals.", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 27.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 54.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "MORNING", position: CGPoint(x: 85.0, y: 62.49), size: CGSize(width: 145.27, height: 7.35), fontSize: 7.26, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "— sunrise —", position: CGPoint(x: 85.0, y: 68.23), size: CGSize(width: 145.27, height: 5.88), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 72.06), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 14.52, y: 79.71), size: CGSize(width: 4.33, height: 4.12), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 88.87, y: 83.24), size: CGSize(width: 137.55, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 14.52, y: 87.65), size: CGSize(width: 4.33, height: 4.12), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 88.87, y: 91.18), size: CGSize(width: 137.55, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 14.52, y: 95.59), size: CGSize(width: 4.33, height: 4.12), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 88.87, y: 99.12), size: CGSize(width: 137.55, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 14.52, y: 103.53), size: CGSize(width: 4.33, height: 4.12), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 88.87, y: 107.06), size: CGSize(width: 137.55, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 14.52, y: 111.47), size: CGSize(width: 4.33, height: 4.12), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 88.87, y: 115.0), size: CGSize(width: 137.55, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "AFTERNOON", position: CGPoint(x: 85.0, y: 122.8), size: CGSize(width: 145.27, height: 7.35), fontSize: 7.26, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "— midday —", position: CGPoint(x: 85.0, y: 128.53), size: CGSize(width: 145.27, height: 5.88), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 132.35), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 14.52, y: 140.0), size: CGSize(width: 4.33, height: 4.12), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 88.87, y: 143.53), size: CGSize(width: 137.55, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 14.52, y: 147.94), size: CGSize(width: 4.33, height: 4.12), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 88.87, y: 151.47), size: CGSize(width: 137.55, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 14.52, y: 155.88), size: CGSize(width: 4.33, height: 4.12), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 88.87, y: 159.41), size: CGSize(width: 137.55, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 14.52, y: 163.82), size: CGSize(width: 4.33, height: 4.12), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 88.87, y: 167.35), size: CGSize(width: 137.55, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 14.52, y: 171.77), size: CGSize(width: 4.33, height: 4.12), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 88.87, y: 175.29), size: CGSize(width: 137.55, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "NIGHT", position: CGPoint(x: 85.0, y: 183.09), size: CGSize(width: 145.27, height: 7.35), fontSize: 7.26, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "— sundown —", position: CGPoint(x: 85.0, y: 188.82), size: CGSize(width: 145.27, height: 5.88), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 192.65), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 14.52, y: 200.3), size: CGSize(width: 4.33, height: 4.12), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 88.87, y: 203.82), size: CGSize(width: 137.55, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 14.52, y: 208.24), size: CGSize(width: 4.33, height: 4.12), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 88.87, y: 211.76), size: CGSize(width: 137.55, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 14.52, y: 216.18), size: CGSize(width: 4.33, height: 4.12), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 88.87, y: 219.71), size: CGSize(width: 137.55, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 14.52, y: 224.12), size: CGSize(width: 4.33, height: 4.12), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 88.87, y: 227.65), size: CGSize(width: 137.55, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 14.52, y: 232.06), size: CGSize(width: 4.33, height: 4.12), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 88.87, y: 235.59), size: CGSize(width: 137.55, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "52", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 53:
            return MagazinePage(title: "11", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "11", position: CGPoint(x: 117.45, y: 35.29), size: CGSize(width: 80.36, height: 47.06), fontSize: 63.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "SECTION", position: CGPoint(x: 43.27, y: 17.65), size: CGSize(width: 61.82, height: 5.88), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 35.54, y: 25.0), size: CGSize(width: 46.36, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "Affirmations & Goals.", position: CGPoint(x: 85.0, y: 122.06), size: CGSize(width: 145.27, height: 64.71), fontSize: 38.88, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 41.41, y: 157.35), size: CGSize(width: 58.11, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "The intentions to carry into the next month — said quietly, said clearly.", position: CGPoint(x: 85.0, y: 176.47), size: CGSize(width: 145.27, height: 29.41), fontSize: 9.36, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 223.53), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "Nº 11 · AFFIRMATIONS & GOALS", position: CGPoint(x: 85.0, y: 230.15), size: CGSize(width: 145.27, height: 7.35), fontSize: 6.45, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 85.0, y: 238.23), size: CGSize(width: 145.27, height: 5.88), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 54:
            return MagazinePage(title: "GOALS · OUTLOOK", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "GOALS · OUTLOOK", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 54", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "OUTLOOK", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "The month", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 23.04, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "ahead.", position: CGPoint(x: 85.0, y: 58.83), size: CGSize(width: 145.27, height: 32.35), fontSize: 23.04, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "", position: CGPoint(x: 85.0, y: 61.46), size: CGSize(width: 145.27, height: 7.35), fontSize: 7.63, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 67.65), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "A WORD FOR THE MONTH", position: CGPoint(x: 85.0, y: 74.7), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 91.17), size: CGSize(width: 145.27, height: 23.53), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "write one word here", position: CGPoint(x: 85.0, y: 91.17), size: CGSize(width: 145.27, height: 23.53), fontSize: 14.4, fontName: "Georgia", isBold: false, isEditableText: true, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 34.51, y: 139.71), size: CGSize(width: 44.3, height: 52.94), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "WORK", position: CGPoint(x: 34.51, y: 121.33), size: CGSize(width: 44.3, height: 7.35), fontSize: 7.26, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 34.52, y: 136.18), size: CGSize(width: 35.03, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 34.52, y: 144.41), size: CGSize(width: 35.03, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 34.52, y: 152.65), size: CGSize(width: 35.03, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 34.52, y: 160.88), size: CGSize(width: 35.03, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 139.71), size: CGSize(width: 44.3, height: 52.94), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "HEALTH", position: CGPoint(x: 85.0, y: 121.33), size: CGSize(width: 44.3, height: 7.35), fontSize: 7.26, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 136.18), size: CGSize(width: 35.03, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 144.41), size: CGSize(width: 35.03, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 152.65), size: CGSize(width: 35.03, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 160.88), size: CGSize(width: 35.03, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 135.48, y: 139.71), size: CGSize(width: 44.3, height: 52.94), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "CRAFT", position: CGPoint(x: 135.48, y: 121.33), size: CGSize(width: 44.3, height: 7.35), fontSize: 7.26, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 135.49, y: 136.18), size: CGSize(width: 35.03, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 135.49, y: 144.41), size: CGSize(width: 35.03, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 135.49, y: 152.65), size: CGSize(width: 35.03, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 135.49, y: 160.88), size: CGSize(width: 35.03, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 34.51, y: 198.53), size: CGSize(width: 44.3, height: 52.94), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "LOVE", position: CGPoint(x: 34.51, y: 180.15), size: CGSize(width: 44.3, height: 7.35), fontSize: 7.26, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 34.52, y: 195.0), size: CGSize(width: 35.03, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 34.52, y: 203.24), size: CGSize(width: 35.03, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 34.52, y: 211.47), size: CGSize(width: 35.03, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 34.52, y: 219.71), size: CGSize(width: 35.03, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 198.53), size: CGSize(width: 44.3, height: 52.94), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "MONEY", position: CGPoint(x: 85.0, y: 180.15), size: CGSize(width: 44.3, height: 7.35), fontSize: 7.26, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 195.0), size: CGSize(width: 35.03, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 203.24), size: CGSize(width: 35.03, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 211.47), size: CGSize(width: 35.03, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 219.71), size: CGSize(width: 35.03, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 135.48, y: 198.53), size: CGSize(width: 44.3, height: 52.94), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "REST", position: CGPoint(x: 135.48, y: 180.15), size: CGSize(width: 44.3, height: 7.35), fontSize: 7.26, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 135.49, y: 195.0), size: CGSize(width: 35.03, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 135.49, y: 203.24), size: CGSize(width: 35.03, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 135.49, y: 211.47), size: CGSize(width: 35.03, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 135.49, y: 219.71), size: CGSize(width: 35.03, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "54", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 55:
            return MagazinePage(title: "GOALS · AFFIRMATIONS", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "GOALS · AFFIRMATIONS", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 55", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "AFFIRMATIONS", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "For next", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 23.04, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "month.", position: CGPoint(x: 85.0, y: 58.83), size: CGSize(width: 145.27, height: 32.35), fontSize: 23.04, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 66.18), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 52.31, y: 104.42), size: CGSize(width: 79.9, height: 67.65), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 52.31, y: 138.24), size: CGSize(width: 79.9, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  picture", position: CGPoint(x: 52.31, y: 133.24), size: CGSize(width: 79.9, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 127.27, y: 86.77), size: CGSize(width: 60.74, height: 32.35), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 127.27, y: 102.94), size: CGSize(width: 60.74, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  picture", position: CGPoint(x: 127.27, y: 97.94), size: CGSize(width: 60.74, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 127.27, y: 122.05), size: CGSize(width: 60.74, height: 32.35), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 127.27, y: 138.24), size: CGSize(width: 60.74, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  picture", position: CGPoint(x: 127.27, y: 133.24), size: CGSize(width: 60.74, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "A WORD FOR NEXT MONTH", position: CGPoint(x: 85.0, y: 145.3), size: CGSize(width: 145.27, height: 5.29), fontSize: 7.2, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 158.82), size: CGSize(width: 145.27, height: 20.59), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "one word", position: CGPoint(x: 85.0, y: 158.82), size: CGSize(width: 145.27, height: 20.59), fontSize: 12.96, fontName: "Georgia", isBold: false, isEditableText: true, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "INTENTIONS", position: CGPoint(x: 85.0, y: 177.65), size: CGSize(width: 145.27, height: 5.29), fontSize: 7.2, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 180.88), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "✦", position: CGPoint(x: 15.45, y: 187.06), size: CGSize(width: 6.18, height: 6.47), fontSize: 7.63, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 190.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "✦", position: CGPoint(x: 15.45, y: 196.48), size: CGSize(width: 6.18, height: 6.47), fontSize: 7.63, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 200.0), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "✦", position: CGPoint(x: 15.45, y: 205.89), size: CGSize(width: 6.18, height: 6.47), fontSize: 7.63, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 209.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "✦", position: CGPoint(x: 15.45, y: 215.3), size: CGSize(width: 6.18, height: 6.47), fontSize: 7.63, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 218.82), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "✦", position: CGPoint(x: 15.45, y: 224.71), size: CGSize(width: 6.18, height: 6.47), fontSize: 7.63, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 228.24), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "55", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 56:
            return MagazinePage(title: "GOALS · VISION BOARD", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "GOALS · VISION BOARD", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 56", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "VISION BOARD", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Vision", position: CGPoint(x: 85.0, y: 44.12), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .title, text: "Board.", position: CGPoint(x: 85.0, y: 58.83), size: CGSize(width: 145.27, height: 32.35), fontSize: 24.48, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .top, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 66.18), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 35.02, y: 91.18), size: CGSize(width: 45.33, height: 41.18), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 35.02, y: 111.76), size: CGSize(width: 45.33, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  become", position: CGPoint(x: 35.02, y: 106.77), size: CGSize(width: 45.33, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "become", position: CGPoint(x: 35.02, y: 116.18), size: CGSize(width: 45.33, height: 5.88), fontSize: 7.63, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 85.0, y: 91.18), size: CGSize(width: 45.33, height: 41.18), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 111.76), size: CGSize(width: 45.33, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  the feeling", position: CGPoint(x: 85.0, y: 106.77), size: CGSize(width: 45.33, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "the feeling", position: CGPoint(x: 85.0, y: 116.18), size: CGSize(width: 45.33, height: 5.88), fontSize: 7.63, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 134.97, y: 91.18), size: CGSize(width: 45.33, height: 41.18), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 134.97, y: 111.76), size: CGSize(width: 45.33, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  dream", position: CGPoint(x: 134.97, y: 106.77), size: CGSize(width: 45.33, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "dream", position: CGPoint(x: 134.97, y: 116.18), size: CGSize(width: 45.33, height: 5.88), fontSize: 7.63, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 35.02, y: 145.59), size: CGSize(width: 45.33, height: 41.18), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 35.02, y: 166.18), size: CGSize(width: 45.33, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  wear", position: CGPoint(x: 35.02, y: 161.18), size: CGSize(width: 45.33, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "wear", position: CGPoint(x: 35.02, y: 170.59), size: CGSize(width: 45.33, height: 5.88), fontSize: 7.63, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 85.0, y: 145.59), size: CGSize(width: 45.33, height: 41.18), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 166.18), size: CGSize(width: 45.33, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  place", position: CGPoint(x: 85.0, y: 161.18), size: CGSize(width: 45.33, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "place", position: CGPoint(x: 85.0, y: 170.59), size: CGSize(width: 45.33, height: 5.88), fontSize: 7.63, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 134.97, y: 145.59), size: CGSize(width: 45.33, height: 41.18), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 134.97, y: 166.18), size: CGSize(width: 45.33, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  read", position: CGPoint(x: 134.97, y: 161.18), size: CGSize(width: 45.33, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "read", position: CGPoint(x: 134.97, y: 170.59), size: CGSize(width: 45.33, height: 5.88), fontSize: 7.63, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 35.02, y: 200.0), size: CGSize(width: 45.33, height: 41.18), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 35.02, y: 220.59), size: CGSize(width: 45.33, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  make", position: CGPoint(x: 35.02, y: 215.59), size: CGSize(width: 45.33, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "make", position: CGPoint(x: 35.02, y: 225.0), size: CGSize(width: 45.33, height: 5.88), fontSize: 7.63, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .image, text: "", position: CGPoint(x: 85.0, y: 200.0), size: CGSize(width: 45.33, height: 41.18), fontSize: 8, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 220.59), size: CGSize(width: 45.33, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "▢  do", position: CGPoint(x: 85.0, y: 215.59), size: CGSize(width: 45.33, height: 6.47), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "do", position: CGPoint(x: 85.0, y: 225.0), size: CGSize(width: 45.33, height: 5.88), fontSize: 7.63, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "56", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 57:
            return MagazinePage(title: "GOALS · SUMMARY", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 43.27, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 11.52, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "GOALS · SUMMARY", position: CGPoint(x: 85.0, y: 14.99), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "№01 · 57", position: CGPoint(x: 126.73, y: 7.94), size: CGSize(width: 61.82, height: 8.82), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 19.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "WORD OF THE MONTH", position: CGPoint(x: 85.0, y: 25.59), size: CGSize(width: 145.27, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 29.41), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "this month, I want to feel —", position: CGPoint(x: 85.0, y: 91.17), size: CGSize(width: 145.27, height: 8.82), fontSize: 9.16, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 130.88), size: CGSize(width: 145.27, height: 58.82), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "write your word", position: CGPoint(x: 85.0, y: 130.88), size: CGSize(width: 145.27, height: 58.82), fontSize: 34.56, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "— and let it lead the month.", position: CGPoint(x: 85.0, y: 170.59), size: CGSize(width: 145.27, height: 8.82), fontSize: 8.4, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 240.59), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "PENPAL · NO. 01", position: CGPoint(x: 58.73, y: 244.71), size: CGSize(width: 92.73, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .left, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "57", position: CGPoint(x: 142.19, y: 244.71), size: CGSize(width: 30.91, height: 5.29), fontSize: 5.64, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .right, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        case 58:
            return MagazinePage(title: "ISSUE №01", sectionTitle: sectionTitle, elements: [
            MagazineElement(type: .box, text: "", position: CGPoint(x: 85.0, y: 125.0), size: CGSize(width: 170.0, height: 250.0), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "PenPal", position: CGPoint(x: 85.0, y: 61.77), size: CGSize(width: 170.0, height: 35.29), fontSize: 46.08, fontName: "Georgia", isBold: true, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "ISSUE №01", position: CGPoint(x: 85.0, y: 83.82), size: CGSize(width: 170.0, height: 8.82), fontSize: 7.63, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 94.12), size: CGSize(width: 49.45, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .title, text: "“A magazine you make\nto grow together.”", position: CGPoint(x: 85.0, y: 126.47), size: CGSize(width: 145.27, height: 41.18), fontSize: 15.84, fontName: "Georgia", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "— THE EDITORS", position: CGPoint(x: 85.0, y: 157.35), size: CGSize(width: 170.0, height: 8.82), fontSize: 7.26, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .line, text: "", position: CGPoint(x: 85.0, y: 191.18), size: CGSize(width: 145.27, height: 0.5), fontSize: 1, fontName: "Helvetica", isBold: false, isEditableText: false),
            MagazineElement(type: .text, text: "MAKE IT.  SHARE IT.  REMEMBER IT.", position: CGPoint(x: 85.0, y: 198.53), size: CGSize(width: 145.27, height: 8.82), fontSize: 7.63, fontName: "Helvetica", isBold: true, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "penpal · the editorial journal", position: CGPoint(x: 85.0, y: 208.82), size: CGSize(width: 145.27, height: 8.82), fontSize: 7.26, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47)),
            MagazineElement(type: .text, text: "MADE WITH LOVE", position: CGPoint(x: 85.0, y: 227.21), size: CGSize(width: 145.27, height: 7.35), fontSize: 6.45, fontName: "Helvetica", isBold: false, isEditableText: false, textAlignment: .center, verticalAlignment: .middle, textInset: CGSize(width: 3.09, height: 1.47))
        ], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        default:
            return MagazinePage(title: "Blank", sectionTitle: sectionTitle, elements: [], backgroundColor: scheme.paper, titleColor: scheme.accent, textColor: scheme.ink)
        }
    }
}

#Preview { IssueBuilderView() }
