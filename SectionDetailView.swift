import SwiftUI
import PhotosUI
import PencilKit
import Combine

// ============================================================
// MARK: - LANGUAGE HELPER
// ============================================================

protocol LanguageSupporting {}

extension LanguageSupporting {
    
    func t(
        _ en: String,
        _ de: String,
        _ it: String,
        _ es: String,
        _ fr: String,
        language: AppLanguage
    ) -> String {
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
// MARK: - SHARED ISSUE STORE
// ============================================================

final class IssueDraftStore: ObservableObject {
    static let shared = IssueDraftStore()
    @Published var pages: [MagazinePage] = []
    private init() {}
}

// ============================================================
// MARK: - SECOND PAGE: CHOOSE LAYOUT
// ============================================================

struct SectionDetailView: View, LanguageSupporting {
    
    let section: IssueSection
    
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    
    @State private var selectedLayout: FreeMagazineLayout = .layout1
    @State private var selectedTitleStyle: TitleStyle = .editorial
    
    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .english
    }
    
    var body: some View {
        
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                
                Text(section.title)
                    .font(.system(size: 30, weight: .light, design: .serif))
                
                Text(t(
                    "Choose a starting layout. Later you can move, resize, add pages, pictures, text, shapes and titles across the magazine spread.",
                    "Wähle ein Startlayout. Später kannst du Seiten, Bilder, Texte, Formen und Titel frei im Magazin verschieben und anpassen.",
                    "Scegli un layout iniziale. Dopo potrai spostare, ridimensionare e aggiungere pagine, immagini, testi, forme e titoli.",
                    "Elige un diseño inicial. Luego podrás mover, cambiar tamaño y añadir páginas, imágenes, textos, formas y títulos.",
                    "Choisis une mise en page de départ. Ensuite tu pourras déplacer, redimensionner et ajouter des pages, images, textes, formes et titres.",
                    language: language
                ))
                .foregroundStyle(.secondary)
                
                Divider()
                
                Text(t(
                    "1. Choose a starting layout",
                    "1. Wähle ein Startlayout",
                    "1. Scegli un layout iniziale",
                    "1. Elige un diseño inicial",
                    "1. Choisis une mise en page",
                    language: language
                ))
                .font(.headline)
                
                LazyVGrid(
                    columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ],
                    spacing: 18
                ) {
                    ForEach(FreeMagazineLayout.allCases) { layout in
                        FreeLayoutThumbnail(
                            layout: layout,
                            isSelected: selectedLayout == layout
                        )
                        .onTapGesture {
                            selectedLayout = layout
                        }
                    }
                }
                
                Divider()
                
                Text(t(
                    "2. Choose a title style",
                    "2. Wähle einen Titelstil",
                    "2. Scegli uno stile titolo",
                    "2. Elige un estilo de título",
                    "2. Choisis un style de titre",
                    language: language
                ))
                .font(.headline)
                
                LazyVGrid(
                    columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ],
                    spacing: 14
                ) {
                    ForEach(TitleStyle.allCases) { style in
                        TitleStyleButton(
                            style: style,
                            isSelected: selectedTitleStyle == style
                        )
                        .onTapGesture {
                            selectedTitleStyle = style
                        }
                    }
                }
                
                Divider()
                
                Text(t(
                    "Preview",
                    "Vorschau",
                    "Anteprima",
                    "Vista previa",
                    "Aperçu",
                    language: language
                ))
                .font(.headline)
                
                FreeLayoutPreview(
                    layout: selectedLayout,
                    title: section.title
                )
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(radius: 4)
                
                NavigationLink {
                    FreeMagazineEditorView(
                        section: section,
                        startingLayout: selectedLayout,
                        startingTitleStyle: selectedTitleStyle
                    ) {
                        dismiss()
                    }
                } label: {
                    Text(t(
                        "Continue and customise page",
                        "Weiter und Seite gestalten",
                        "Continua e personalizza la pagina",
                        "Continuar y personalizar página",
                        "Continuer et personnaliser la page",
                        language: language
                    ))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                
                Spacer(minLength: 40)
            }
            .padding()
        }
        .navigationTitle(t(
            "Choose Layout",
            "Layout wählen",
            "Scegli layout",
            "Elegir diseño",
            "Choisir la mise en page",
            language: language
        ))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// ============================================================
// MARK: - THIRD PAGE: MAGAZINE EDITOR
// ============================================================

struct FreeMagazineEditorView: View, LanguageSupporting {
    
    let section: IssueSection
    let startingLayout: FreeMagazineLayout
    let startingTitleStyle: TitleStyle
    let onFinish: () -> Void
    
    @StateObject private var issueStore = IssueDraftStore.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    
    @State private var selectedElementID: UUID?
    @State private var currentSectionStartIndex: Int = 0
    @State private var currentSpreadStartIndex: Int = 0
    
    @State private var selectedTextBackgroundColor: Color = .white.opacity(0.35)
    @State private var selectedShapeColor: Color = .pink.opacity(0.65)
    
    @State private var showDrawingCanvas = false
    
    private let pageWidth: CGFloat = 170
    private let pageHeight: CGFloat = 250
    
    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .english
    }
    
    var body: some View {
        
        VStack(spacing: 0) {
            
            topBar
            
            ScrollView {
                VStack(spacing: 22) {
                    
                    magazineSpreadView
                    
                    editorControls
                    
                    if let selectedElementID {
                        SelectedElementEditor(
                            pages: $issueStore.pages,
                            selectedElementID: selectedElementID,
                            selectedTextBackgroundColor: $selectedTextBackgroundColor,
                            selectedShapeColor: $selectedShapeColor
                        )
                        .padding(.horizontal)
                    }
                    
                    Button {
                        dismiss()
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            onFinish()
                        }
                    } label: {
                        Text(t(
                            "Save section and choose next section",
                            "Abschnitt speichern und nächsten wählen",
                            "Salva sezione e scegli la prossima",
                            "Guardar sección y elegir la siguiente",
                            "Sauvegarder la section et choisir la suivante",
                            language: language
                        ))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: 40)
                }
                .padding(.top)
            }
        }
        .navigationTitle(t(
            "Edit Magazine",
            "Magazin bearbeiten",
            "Modifica magazine",
            "Editar revista",
            "Modifier le magazine",
            language: language
        ))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            prepareSectionIfNeeded()
        }
        .sheet(isPresented: $showDrawingCanvas) {
            DrawingCanvasPage { image in
                addDrawing(image)
            }
        }
    }
    
    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(t(
                    "Open magazine",
                    "Offenes Magazin",
                    "Magazine aperto",
                    "Revista abierta",
                    "Magazine ouvert",
                    language: language
                ))
                .font(.headline)
                
                Text("\(issueStore.pages.count) \(t("saved page", "gespeicherte Seite", "pagina salvata", "página guardada", "page sauvegardée", language: language))\(issueStore.pages.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text("\(t("Pages", "Seiten", "Pagine", "Páginas", "Pages", language: language)) \(currentSpreadStartIndex + 1)–\(min(currentSpreadStartIndex + 2, issueStore.pages.count))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
    
    private var magazineSpreadView: some View {
        
        VStack(spacing: 12) {
            
            HStack {
                Button {
                    currentSpreadStartIndex = max(0, currentSpreadStartIndex - 2)
                    selectedElementID = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                }
                .disabled(currentSpreadStartIndex == 0)
                
                Spacer()
                
                Text("\(t("Spread", "Doppelseite", "Doppia pagina", "Doble página", "Double page", language: language)) \(currentSpreadStartIndex / 2 + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button {
                    if currentSpreadStartIndex + 2 < issueStore.pages.count {
                        currentSpreadStartIndex += 2
                        selectedElementID = nil
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.headline)
                }
                .disabled(currentSpreadStartIndex + 2 >= issueStore.pages.count)
            }
            .padding(.horizontal)
            
            MagazineSpreadCanvas(
                pages: $issueStore.pages,
                selectedElementID: $selectedElementID,
                currentSpreadStartIndex: currentSpreadStartIndex,
                pageWidth: pageWidth,
                pageHeight: pageHeight
            )
            .frame(width: pageWidth * 2, height: pageHeight)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(radius: 4)
        }
        .padding(.horizontal)
    }
    
    private var editorControls: some View {
        
        VStack(spacing: 16) {
            
            HStack(spacing: 12) {
                
                Button {
                    addTextBox()
                } label: {
                    EditorActionButton(
                        icon: "text.alignleft",
                        title: t("Add Text", "Text hinzufügen", "Aggiungi testo", "Añadir texto", "Ajouter texte", language: language)
                    )
                }
                
                Button {
                    addSpreadTitle()
                } label: {
                    EditorActionButton(
                        icon: "textformat.size",
                        title: t("Spread Title", "Doppelseiten-Titel", "Titolo doppia pagina", "Título doble página", "Titre double page", language: language)
                    )
                }
                
                Button {
                    addPictureBox()
                } label: {
                    EditorActionButton(
                        icon: "photo",
                        title: t("Add Picture", "Bild hinzufügen", "Aggiungi immagine", "Añadir imagen", "Ajouter image", language: language)
                    )
                }
            }
            
            HStack(spacing: 12) {
                
                Menu {
                    ForEach(MagazineShape.allCases, id: \.self) { shape in
                        Button {
                            addShape(shape)
                        } label: {
                            Label(shape.label, systemImage: shape.systemImage ?? "circle")
                        }
                    }
                } label: {
                    EditorActionButton(
                        icon: "circle.square",
                        title: t("Add Shape", "Form hinzufügen", "Aggiungi forma", "Añadir forma", "Ajouter forme", language: language)
                    )
                }
                
                Button {
                    showDrawingCanvas = true
                } label: {
                    EditorActionButton(
                        icon: "pencil.tip",
                        title: t("Draw", "Zeichnen", "Disegna", "Dibujar", "Dessiner", language: language)
                    )
                }
                
                Button {
                    addPage()
                } label: {
                    EditorActionButton(
                        icon: "plus.rectangle.on.rectangle",
                        title: t("Add Page", "Seite hinzufügen", "Aggiungi pagina", "Añadir página", "Ajouter page", language: language)
                    )
                }
            }
            
            Button {
                deleteSelectedElement()
            } label: {
                EditorActionButton(
                    icon: "trash",
                    title: t("Delete Selected", "Auswahl löschen", "Elimina selezione", "Eliminar selección", "Supprimer sélection", language: language)
                )
            }
            .disabled(selectedElementID == nil)
            
            NavigationLink {
                IssueCoverEditorView()
            } label: {
                EditorActionButton(
                    icon: "checkmark.seal",
                    title: t("Finish Issue", "Ausgabe beenden", "Completa numero", "Terminar edición", "Finaliser numéro", language: language)
                )
            }
            
            VStack(alignment: .leading, spacing: 14) {
                
                if issueStore.pages.indices.contains(activePageIndex) {
                    
                    ColorPicker(
                        t("Current page background", "Aktueller Seitenhintergrund", "Sfondo pagina attuale", "Fondo página actual", "Fond page actuelle", language: language),
                        selection: Binding(
                            get: {
                                Color(uiColor: issueStore.pages[activePageIndex].backgroundColor)
                            },
                            set: { newValue in
                                issueStore.pages[activePageIndex].backgroundColor = UIColor(newValue)
                            }
                        )
                    )
                    
                    ColorPicker(
                        t("Current page title colour", "Aktuelle Titelfarbe", "Colore titolo attuale", "Color título actual", "Couleur titre actuelle", language: language),
                        selection: Binding(
                            get: {
                                Color(uiColor: issueStore.pages[activePageIndex].titleColor)
                            },
                            set: { newValue in
                                issueStore.pages[activePageIndex].titleColor = UIColor(newValue)
                            }
                        )
                    )
                    
                    ColorPicker(
                        t("Current page text colour", "Aktuelle Textfarbe", "Colore testo attuale", "Color texto actual", "Couleur texte actuelle", language: language),
                        selection: Binding(
                            get: {
                                Color(uiColor: issueStore.pages[activePageIndex].textColor)
                            },
                            set: { newValue in
                                issueStore.pages[activePageIndex].textColor = UIColor(newValue)
                            }
                        )
                    )
                    
                    Picker(
                        t("Current page title font", "Aktuelle Titelschrift", "Font titolo attuale", "Fuente título actual", "Police titre actuelle", language: language),
                        selection: $issueStore.pages[activePageIndex].titleStyle
                    ) {
                        ForEach(TitleStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                ColorPicker(
                    t("New text box background", "Neuer Textfeld-Hintergrund", "Sfondo nuovo testo", "Fondo nuevo texto", "Fond nouveau texte", language: language),
                    selection: $selectedTextBackgroundColor
                )
                
                ColorPicker(
                    t("New shape/icon colour", "Neue Form/Icon-Farbe", "Colore nuova forma/icona", "Color nueva forma/icono", "Couleur nouvelle forme/icône", language: language),
                    selection: $selectedShapeColor
                )
            }
            .padding()
            .background(Color.gray.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal)
    }
    
    private func prepareSectionIfNeeded() {
        
        if let existing = issueStore.pages.firstIndex(where: { $0.sectionTitle == section.title }) {
            currentSectionStartIndex = existing
            currentSpreadStartIndex = spreadStart(for: existing)
            return
        }
        
        let page = MagazinePage(
            title: section.title,
            sectionTitle: section.title,
            layout: startingLayout,
            elements: startingLayout.makeElements(
                title: section.title,
                includeTitle: true
            ),
            titleStyle: startingTitleStyle,
            backgroundColor: UIColor(Color(red: 0.97, green: 0.94, blue: 0.86)),
            titleColor: UIColor.black,
            textColor: UIColor.black
        )
        
        issueStore.pages.append(page)
        currentSectionStartIndex = issueStore.pages.count - 1
        currentSpreadStartIndex = spreadStart(for: currentSectionStartIndex)
    }
    
    private func spreadStart(for pageIndex: Int) -> Int {
        pageIndex.isMultiple(of: 2) ? pageIndex : pageIndex - 1
    }
    
    private var activePageIndex: Int {
        if let selectedElementID {
            for pageIndex in issueStore.pages.indices {
                if issueStore.pages[pageIndex].elements.contains(where: { $0.id == selectedElementID }) {
                    return pageIndex
                }
            }
        }
        
        return currentSectionStartIndex
    }
    
    private func addTextBox() {
        guard issueStore.pages.indices.contains(activePageIndex) else { return }
        
        issueStore.pages[activePageIndex].elements.append(
            MagazineElement(
                type: .text,
                text: t("Write here", "Hier schreiben", "Scrivi qui", "Escribe aquí", "Écris ici", language: language),
                position: CGPoint(x: 95, y: 135),
                size: CGSize(width: 95, height: 70),
                textBackgroundColor: UIColor(selectedTextBackgroundColor)
            )
        )
    }
    
    private func addSpreadTitle() {
        guard issueStore.pages.indices.contains(currentSpreadStartIndex) else { return }
        
        issueStore.pages[currentSpreadStartIndex].elements.append(
            MagazineElement(
                type: .title,
                text: section.title,
                position: CGPoint(x: pageWidth, y: 45),
                size: CGSize(width: pageWidth * 1.75, height: 55)
            )
        )
    }
    
    private func addPictureBox() {
        guard issueStore.pages.indices.contains(activePageIndex) else { return }
        
        issueStore.pages[activePageIndex].elements.append(
            MagazineElement(
                type: .image,
                position: CGPoint(x: 95, y: 135),
                size: CGSize(width: 90, height: 90),
                imageFit: .fit
            )
        )
    }
    
    private func addShape(_ shape: MagazineShape) {
        guard issueStore.pages.indices.contains(activePageIndex) else { return }
        
        issueStore.pages[activePageIndex].elements.append(
            MagazineElement(
                type: .shape,
                position: CGPoint(x: 95, y: 135),
                size: CGSize(width: 55, height: 55),
                shape: shape,
                shapeColor: UIColor(selectedShapeColor)
            )
        )
    }
    
    private func addDrawing(_ image: UIImage) {
        guard issueStore.pages.indices.contains(activePageIndex) else { return }
        
        issueStore.pages[activePageIndex].elements.append(
            MagazineElement(
                type: .drawing,
                image: image,
                position: CGPoint(x: 95, y: 135),
                size: CGSize(width: 100, height: 85)
            )
        )
    }
    
    private func addPage() {
        guard issueStore.pages.indices.contains(activePageIndex) else { return }
        
        let sourcePage = issueStore.pages[activePageIndex]
        
        let newPage = MagazinePage(
            title: "",
            sectionTitle: section.title,
            layout: sourcePage.layout,
            elements: sourcePage.layout.makeElements(
                title: "",
                includeTitle: false
            ),
            titleStyle: sourcePage.titleStyle,
            backgroundColor: sourcePage.backgroundColor,
            titleColor: sourcePage.titleColor,
            textColor: sourcePage.textColor
        )
        
        issueStore.pages.append(newPage)
        selectedElementID = nil
        currentSpreadStartIndex = spreadStart(for: issueStore.pages.count - 1)
    }
    
    private func deleteSelectedElement() {
        guard let selectedElementID else { return }
        
        for index in issueStore.pages.indices {
            issueStore.pages[index].elements.removeAll { $0.id == selectedElementID }
        }
        
        self.selectedElementID = nil
    }
}

// ============================================================
// MARK: - SPREAD CANVAS
// ============================================================

struct MagazineSpreadCanvas: View {
    
    @Binding var pages: [MagazinePage]
    @Binding var selectedElementID: UUID?
    
    let currentSpreadStartIndex: Int
    let pageWidth: CGFloat
    let pageHeight: CGFloat
    
    var body: some View {
        
        ZStack(alignment: .topLeading) {
            
            HStack(spacing: 0) {
                
                pageBackground(for: currentSpreadStartIndex)
                    .frame(width: pageWidth, height: pageHeight)
                
                pageBackground(for: currentSpreadStartIndex + 1)
                    .frame(width: pageWidth, height: pageHeight)
            }
            
            Rectangle()
                .fill(Color.black.opacity(0.18))
                .frame(width: 1, height: pageHeight)
                .position(x: pageWidth, y: pageHeight / 2)
            
            ForEach(visiblePageIndices, id: \.self) { pageIndex in
                ForEach(pages[pageIndex].elements.indices, id: \.self) { elementIndex in
                    
                    MagazineElementView(
                        element: $pages[pageIndex].elements[elementIndex],
                        isSelected: selectedElementID == pages[pageIndex].elements[elementIndex].id,
                        page: pages[pageIndex]
                    )
                    .frame(
                        width: pages[pageIndex].elements[elementIndex].size.width,
                        height: pages[pageIndex].elements[elementIndex].size.height
                    )
                    .position(
                        x: CGFloat(pageIndex - currentSpreadStartIndex) * pageWidth + pages[pageIndex].elements[elementIndex].position.x,
                        y: pages[pageIndex].elements[elementIndex].position.y
                    )
                    .onTapGesture {
                        selectedElementID = pages[pageIndex].elements[elementIndex].id
                    }
                }
            }
        }
    }
    
    private var visiblePageIndices: [Int] {
        [currentSpreadStartIndex, currentSpreadStartIndex + 1]
            .filter { pages.indices.contains($0) }
    }
    
    private func pageBackground(for index: Int) -> some View {
        ZStack {
            if pages.indices.contains(index) {
                Color(uiColor: pages[index].backgroundColor)
            } else {
                Color(red: 0.97, green: 0.94, blue: 0.86)
            }
            
            Rectangle()
                .stroke(Color.black.opacity(0.18), lineWidth: 1)
                .padding(6)
        }
    }
}

// ============================================================
// MARK: - ELEMENT VIEW
// ============================================================

struct MagazineElementView: View {
    
    @Binding var element: MagazineElement
    
    let isSelected: Bool
    let page: MagazinePage
    
    @State private var selectedItem: PhotosPickerItem?
    @State private var dragStartPosition: CGPoint?
    @State private var resizeStartSize: CGSize?
    
    var body: some View {
        
        ZStack(alignment: .bottomTrailing) {
            
            content
                .contentShape(Rectangle())
                .gesture(moveGesture)
            
            if isSelected {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.black, lineWidth: 2)
                
                resizeHandle
            }
        }
    }
    
    @ViewBuilder
    private var content: some View {
        
        switch element.type {
            
        case .title:
            Text(element.text)
                .font(page.titleStyle.font)
                .foregroundStyle(Color(uiColor: page.titleColor))
                .lineLimit(nil)
                .minimumScaleFactor(0.2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(4)
                .clipped()
            
        case .text:
            Text(element.text)
                .font(.system(size: 10))
                .foregroundStyle(Color(uiColor: page.textColor))
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(5)
                .background(Color(uiColor: element.textBackgroundColor))
                .clipped()
            
        case .image:
            ZStack {
                if let image = element.image {
                    if element.imageFit == .fill {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: element.size.width, height: element.size.height)
                            .clipped()
                    } else {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: element.size.width, height: element.size.height)
                            .clipped()
                    }
                } else {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        ZStack {
                            Rectangle()
                                .fill(Color.white.opacity(0.75))
                            
                            Rectangle()
                                .stroke(Color.black.opacity(0.35), lineWidth: 1)
                            
                            Image(systemName: "plus.circle")
                                .font(.title3)
                                .foregroundStyle(.black.opacity(0.6))
                        }
                    }
                    .buttonStyle(.plain)
                    .onChange(of: selectedItem) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self),
                               let uiImage = UIImage(data: data) {
                                
                                element.image = uiImage
                                element.imageFit = .fit
                                element.size = fittedSize(for: uiImage)
                            }
                        }
                    }
                }
            }
            
        case .shape:
            ShapeOrIconView(
                shape: element.shape,
                color: Color(uiColor: element.shapeColor)
            )
            
        case .drawing:
            if let image = element.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
        }
    }
    
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragStartPosition == nil {
                    dragStartPosition = element.position
                }
                
                guard let dragStartPosition else { return }
                
                element.position = CGPoint(
                    x: dragStartPosition.x + value.translation.width,
                    y: dragStartPosition.y + value.translation.height
                )
            }
            .onEnded { _ in
                dragStartPosition = nil
            }
    }
    
    private var resizeHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.caption2)
            .padding(7)
            .background(Color.white)
            .clipShape(Circle())
            .shadow(radius: 2)
            .offset(x: 13, y: 13)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if resizeStartSize == nil {
                            resizeStartSize = element.size
                        }
                        
                        guard let resizeStartSize else { return }
                        
                        element.size = CGSize(
                            width: max(28, resizeStartSize.width + value.translation.width),
                            height: max(24, resizeStartSize.height + value.translation.height)
                        )
                    }
                    .onEnded { _ in
                        resizeStartSize = nil
                    }
            )
    }
    
    private func fittedSize(for image: UIImage) -> CGSize {
        let maxWidth: CGFloat = 120
        let maxHeight: CGFloat = 120
        
        guard image.size.width > 0, image.size.height > 0 else {
            return CGSize(width: 90, height: 90)
        }
        
        let scale = min(maxWidth / image.size.width, maxHeight / image.size.height)
        
        return CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
    }
}

// ============================================================
// MARK: - SELECTED ELEMENT EDITOR
// ============================================================

struct SelectedElementEditor: View, LanguageSupporting {
    
    @Binding var pages: [MagazinePage]
    let selectedElementID: UUID
    
    @Binding var selectedTextBackgroundColor: Color
    @Binding var selectedShapeColor: Color
    
    @State private var selectedPhotoItem: PhotosPickerItem?
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    
    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .english
    }
    
    var body: some View {
        
        if let location = selectedElementLocation {
            
            VStack(alignment: .leading, spacing: 14) {
                
                Text(t("Edit selected item", "Ausgewähltes Element bearbeiten", "Modifica elemento selezionato", "Editar elemento seleccionado", "Modifier l’élément sélectionné", language: language))
                    .font(.headline)
                
                if pages[location.pageIndex].elements[location.elementIndex].type == .image {
                    
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Text(pages[location.pageIndex].elements[location.elementIndex].image == nil
                             ? t("Upload picture", "Bild hochladen", "Carica immagine", "Subir imagen", "Importer image", language: language)
                             : t("Replace picture", "Bild ersetzen", "Sostituisci immagine", "Reemplazar imagen", "Remplacer image", language: language))
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    
                    Picker(
                        t("Image fit", "Bildanpassung", "Adattamento immagine", "Ajuste imagen", "Ajustement image", language: language),
                        selection: $pages[location.pageIndex].elements[location.elementIndex].imageFit
                    ) {
                        Text(t("Fit full image", "Ganzes Bild zeigen", "Mostra immagine intera", "Mostrar imagen completa", "Afficher image entière", language: language)).tag(MagazineImageFit.fit)
                        Text(t("Fill / crop", "Füllen / zuschneiden", "Riempi / ritaglia", "Rellenar / recortar", "Remplir / rogner", language: language)).tag(MagazineImageFit.fill)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedPhotoItem) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self),
                               let uiImage = UIImage(data: data) {
                                
                                pages[location.pageIndex].elements[location.elementIndex].image = uiImage
                                pages[location.pageIndex].elements[location.elementIndex].imageFit = .fit
                                pages[location.pageIndex].elements[location.elementIndex].size = fittedSize(for: uiImage)
                            }
                        }
                    }
                    
                    Text(t(
                        "Tap an empty picture box to upload. After uploading, drag it to move or pull the corner handle to resize.",
                        "Tippe auf ein leeres Bildfeld zum Hochladen. Danach kannst du es ziehen oder über die Ecke vergrößern.",
                        "Tocca un riquadro immagine vuoto per caricare. Dopo puoi trascinarlo o ridimensionarlo dall’angolo.",
                        "Toca un cuadro de imagen vacío para subir. Después puedes moverlo o cambiar tamaño desde la esquina.",
                        "Appuie sur un cadre image vide pour importer. Ensuite tu peux le déplacer ou le redimensionner par le coin.",
                        language: language
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                
                if pages[location.pageIndex].elements[location.elementIndex].type == .title ||
                    pages[location.pageIndex].elements[location.elementIndex].type == .text {
                    
                    TextEditor(
                        text: $pages[location.pageIndex].elements[location.elementIndex].text
                    )
                    .frame(height: 120)
                    .padding(8)
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                
                if pages[location.pageIndex].elements[location.elementIndex].type == .title {
                    
                    Picker(
                        t("Title font", "Titelschrift", "Font titolo", "Fuente título", "Police titre", language: language),
                        selection: $pages[location.pageIndex].titleStyle
                    ) {
                        ForEach(TitleStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    ColorPicker(
                        t("Title colour", "Titelfarbe", "Colore titolo", "Color título", "Couleur titre", language: language),
                        selection: Binding(
                            get: {
                                Color(uiColor: pages[location.pageIndex].titleColor)
                            },
                            set: { newValue in
                                pages[location.pageIndex].titleColor = UIColor(newValue)
                            }
                        )
                    )
                }
                
                if pages[location.pageIndex].elements[location.elementIndex].type == .text {
                    
                    ColorPicker(
                        t("Text colour", "Textfarbe", "Colore testo", "Color texto", "Couleur texte", language: language),
                        selection: Binding(
                            get: {
                                Color(uiColor: pages[location.pageIndex].textColor)
                            },
                            set: { newValue in
                                pages[location.pageIndex].textColor = UIColor(newValue)
                            }
                        )
                    )
                    
                    ColorPicker(t("Text box background", "Textfeld-Hintergrund", "Sfondo casella testo", "Fondo cuadro texto", "Fond zone texte", language: language), selection: $selectedTextBackgroundColor)
                        .onChange(of: selectedTextBackgroundColor) { _, newValue in
                            pages[location.pageIndex].elements[location.elementIndex].textBackgroundColor = UIColor(newValue)
                        }
                }
                
                if pages[location.pageIndex].elements[location.elementIndex].type == .shape {
                    
                    ColorPicker(t("Shape/icon colour", "Form/Icon-Farbe", "Colore forma/icona", "Color forma/icono", "Couleur forme/icône", language: language), selection: $selectedShapeColor)
                        .onChange(of: selectedShapeColor) { _, newValue in
                            pages[location.pageIndex].elements[location.elementIndex].shapeColor = UIColor(newValue)
                        }
                    
                    Picker(
                        t("Shape", "Form", "Forma", "Forma", "Forme", language: language),
                        selection: $pages[location.pageIndex].elements[location.elementIndex].shape
                    ) {
                        ForEach(MagazineShape.allCases, id: \.self) { shape in
                            Text(shape.label).tag(shape)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                VStack(alignment: .leading) {
                    Text(t("Width", "Breite", "Larghezza", "Ancho", "Largeur", language: language))
                    Slider(
                        value: $pages[location.pageIndex].elements[location.elementIndex].size.width,
                        in: 25...340
                    )
                    
                    Text(t("Height", "Höhe", "Altezza", "Altura", "Hauteur", language: language))
                    Slider(
                        value: $pages[location.pageIndex].elements[location.elementIndex].size.height,
                        in: 20...250
                    )
                }
            }
            .padding()
            .background(Color.gray.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
    
    private var selectedElementLocation: (pageIndex: Int, elementIndex: Int)? {
        for pageIndex in pages.indices {
            if let elementIndex = pages[pageIndex].elements.firstIndex(where: { $0.id == selectedElementID }) {
                return (pageIndex, elementIndex)
            }
        }
        return nil
    }
    
    private func fittedSize(for image: UIImage) -> CGSize {
        let maxWidth: CGFloat = 120
        let maxHeight: CGFloat = 120
        
        guard image.size.width > 0, image.size.height > 0 else {
            return CGSize(width: 90, height: 90)
        }
        
        let scale = min(maxWidth / image.size.width, maxHeight / image.size.height)
        
        return CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
    }
}

// ============================================================
// MARK: - MODELS
// ============================================================

struct MagazinePage: Identifiable {
    let id = UUID()
    var title: String
    var sectionTitle: String
    var layout: FreeMagazineLayout
    var elements: [MagazineElement]
    var titleStyle: TitleStyle
    var backgroundColor: UIColor
    var titleColor: UIColor
    var textColor: UIColor
}

struct MagazineElement: Identifiable {

    let id = UUID()

    var type: MagazineElementType
    var text: String = ""

    var image: UIImage? = nil

    var position: CGPoint
    var size: CGSize

    var shape: MagazineShape = .rectangle

    var textBackgroundColor: UIColor =
        UIColor.white.withAlphaComponent(0.35)

    var shapeColor: UIColor =
        UIColor.systemPink.withAlphaComponent(0.65)

    var isTextLocked: Bool = false
    var imageFit: MagazineImageFit = .fit
}

enum MagazineImageFit {
    case fit
    case fill
}

enum MagazineElementType {
    case title
    case text
    case image
    case shape
    case drawing
}

enum MagazineShape: String, CaseIterable {
    case circle, rectangle, triangle, wave, beams, flower, heart, star, sun, moon
    case musicNote, musicKey, microphone, film, book, sparkle
    
    var label: String {
        switch self {
        case .circle: return "Circle"
        case .rectangle: return "Rectangle"
        case .triangle: return "Triangle"
        case .wave: return "Wave"
        case .beams: return "Beams"
        case .flower: return "Flower"
        case .heart: return "Heart"
        case .star: return "Star"
        case .sun: return "Sun"
        case .moon: return "Moon"
        case .musicNote: return "Music Note"
        case .musicKey: return "Music Key"
        case .microphone: return "Microphone"
        case .film: return "Film"
        case .book: return "Book"
        case .sparkle: return "Sparkle"
        }
    }
    
    var systemImage: String? {
        switch self {
        case .flower: return "camera.macro"
        case .heart: return "heart.fill"
        case .star: return "star.fill"
        case .sun: return "sun.max.fill"
        case .moon: return "moon.fill"
        case .musicNote: return "music.note"
        case .musicKey: return "music.quarternote.3"
        case .microphone: return "mic.fill"
        case .film: return "film.fill"
        case .book: return "book.closed.fill"
        case .sparkle: return "sparkles"
        default: return nil
        }
    }
}

// ============================================================
// MARK: - LAYOUTS
// ============================================================

enum FreeMagazineLayout: String, CaseIterable, Identifiable {
    
    case layout1 = "Layout 1"
    case layout2 = "Layout 2"
    case layout3 = "Layout 3"
    case layout4 = "Layout 4"
    case layout5 = "Layout 5"
    case layout6 = "Layout 6"
    case layout7 = "Layout 7"
    case layout8 = "Layout 8"
    case layout9 = "Layout 9"
    case layout10 = "Layout 10"
    
    var id: String { rawValue }
    
    func makeElements(title: String, includeTitle: Bool) -> [MagazineElement] {
        
        var elements: [MagazineElement] = []
        
        func addTitle(_ position: CGPoint, _ size: CGSize) {
            if includeTitle {
                elements.append(
                    MagazineElement(
                        type: .title,
                        text: title,
                        position: position,
                        size: size
                    )
                )
            }
        }
        
        switch self {
        case .layout1:
            addTitle(CGPoint(x: 85, y: 35), CGSize(width: 95, height: 35))
            elements += [
                MagazineElement(type: .image, position: CGPoint(x: 35, y: 35), size: CGSize(width: 28, height: 28)),
                MagazineElement(type: .image, position: CGPoint(x: 135, y: 35), size: CGSize(width: 28, height: 28)),
                MagazineElement(type: .image, position: CGPoint(x: 65, y: 130), size: CGSize(width: 60, height: 90)),
                MagazineElement(type: .text, text: "Write here", position: CGPoint(x: 125, y: 135), size: CGSize(width: 65, height: 95))
            ]
        case .layout2:
            elements += [
                MagazineElement(type: .text, text: "Write here", position: CGPoint(x: 45, y: 60), size: CGSize(width: 55, height: 60)),
                MagazineElement(type: .image, position: CGPoint(x: 120, y: 55), size: CGSize(width: 75, height: 45)),
                MagazineElement(type: .image, position: CGPoint(x: 60, y: 155), size: CGSize(width: 60, height: 60)),
                MagazineElement(type: .image, position: CGPoint(x: 125, y: 155), size: CGSize(width: 28, height: 28)),
                MagazineElement(type: .image, position: CGPoint(x: 155, y: 155), size: CGSize(width: 28, height: 28)),
                MagazineElement(type: .image, position: CGPoint(x: 125, y: 190), size: CGSize(width: 28, height: 28)),
                MagazineElement(type: .image, position: CGPoint(x: 155, y: 190), size: CGSize(width: 28, height: 28))
            ]
        case .layout3:
            addTitle(CGPoint(x: 95, y: 95), CGSize(width: 120, height: 35))
            elements += [
                MagazineElement(type: .image, position: CGPoint(x: 60, y: 45), size: CGSize(width: 65, height: 50)),
                MagazineElement(type: .image, position: CGPoint(x: 45, y: 175), size: CGSize(width: 45, height: 70)),
                MagazineElement(type: .image, position: CGPoint(x: 95, y: 175), size: CGSize(width: 45, height: 70)),
                MagazineElement(type: .image, position: CGPoint(x: 145, y: 175), size: CGSize(width: 45, height: 70))
            ]
        case .layout4:
            addTitle(CGPoint(x: 35, y: 60), CGSize(width: 35, height: 70))
            elements += [
                MagazineElement(type: .text, text: "Write here", position: CGPoint(x: 100, y: 60), size: CGSize(width: 115, height: 60)),
                MagazineElement(type: .image, position: CGPoint(x: 50, y: 150), size: CGSize(width: 55, height: 55)),
                MagazineElement(type: .text, text: "Write here", position: CGPoint(x: 120, y: 150), size: CGSize(width: 70, height: 55)),
                MagazineElement(type: .image, position: CGPoint(x: 150, y: 150), size: CGSize(width: 28, height: 28))
            ]
        case .layout5:
            elements += [
                MagazineElement(type: .shape, position: CGPoint(x: 65, y: 130), size: CGSize(width: 18, height: 210), shape: .wave),
                MagazineElement(type: .text, text: "Write here", position: CGPoint(x: 45, y: 75), size: CGSize(width: 50, height: 60)),
                MagazineElement(type: .image, position: CGPoint(x: 45, y: 190), size: CGSize(width: 45, height: 50)),
                MagazineElement(type: .image, position: CGPoint(x: 120, y: 80), size: CGSize(width: 45, height: 45))
            ]
            addTitle(CGPoint(x: 110, y: 130), CGSize(width: 80, height: 45))
            elements += [
                MagazineElement(type: .text, text: "Write here", position: CGPoint(x: 115, y: 190), size: CGSize(width: 65, height: 55))
            ]
        case .layout6:
            addTitle(CGPoint(x: 45, y: 45), CGSize(width: 60, height: 35))
            elements += [
                MagazineElement(type: .text, text: "Write here", position: CGPoint(x: 45, y: 120), size: CGSize(width: 60, height: 95)),
                MagazineElement(type: .image, position: CGPoint(x: 125, y: 75), size: CGSize(width: 45, height: 45)),
                MagazineElement(type: .image, position: CGPoint(x: 105, y: 190), size: CGSize(width: 75, height: 65))
            ]
        case .layout7:
            addTitle(CGPoint(x: 45, y: 40), CGSize(width: 60, height: 35))
            elements += [
                MagazineElement(type: .text, text: "Write here", position: CGPoint(x: 45, y: 100), size: CGSize(width: 60, height: 85)),
                MagazineElement(type: .image, position: CGPoint(x: 45, y: 200), size: CGSize(width: 50, height: 50)),
                MagazineElement(type: .shape, position: CGPoint(x: 75, y: 140), size: CGSize(width: 18, height: 210), shape: .wave),
                MagazineElement(type: .image, position: CGPoint(x: 125, y: 120), size: CGSize(width: 65, height: 110))
            ]
        case .layout8:
            elements += [
                MagazineElement(type: .image, position: CGPoint(x: 45, y: 45), size: CGSize(width: 55, height: 55)),
                MagazineElement(type: .image, position: CGPoint(x: 105, y: 45), size: CGSize(width: 38, height: 38)),
                MagazineElement(type: .image, position: CGPoint(x: 145, y: 45), size: CGSize(width: 38, height: 38)),
                MagazineElement(type: .image, position: CGPoint(x: 100, y: 125), size: CGSize(width: 120, height: 75))
            ]
        case .layout9:
            addTitle(CGPoint(x: 55, y: 45), CGSize(width: 75, height: 35))
            elements += [
                MagazineElement(type: .text, text: "Write here", position: CGPoint(x: 55, y: 155), size: CGSize(width: 65, height: 110)),
                MagazineElement(type: .image, position: CGPoint(x: 120, y: 140), size: CGSize(width: 75, height: 145)),
                MagazineElement(type: .image, position: CGPoint(x: 145, y: 65), size: CGSize(width: 50, height: 55))
            ]
        case .layout10:
            addTitle(CGPoint(x: 85, y: 40), CGSize(width: 90, height: 30))
            elements += [
                MagazineElement(type: .shape, position: CGPoint(x: 85, y: 75), size: CGSize(width: 145, height: 30), shape: .wave),
                MagazineElement(type: .text, text: "Write here", position: CGPoint(x: 85, y: 105), size: CGSize(width: 125, height: 45)),
                MagazineElement(type: .shape, position: CGPoint(x: 85, y: 135), size: CGSize(width: 145, height: 30), shape: .wave),
                MagazineElement(type: .image, position: CGPoint(x: 45, y: 200), size: CGSize(width: 50, height: 75)),
                MagazineElement(type: .image, position: CGPoint(x: 100, y: 200), size: CGSize(width: 50, height: 75))
            ]
        }
        
        return elements
    }
}

// ============================================================
// MARK: - THUMBNAILS
// ============================================================

struct FreeLayoutThumbnail: View {
    
    let layout: FreeMagazineLayout
    let isSelected: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            
            FreeLayoutPreview(
                layout: layout,
                title: "TITLE"
            )
            .frame(height: 135)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? Color.black : Color.gray.opacity(0.25),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            
            Text(layout.rawValue)
                .font(.caption)
        }
    }
}

struct FreeLayoutPreview: View {
    
    let layout: FreeMagazineLayout
    let title: String
    
    var body: some View {
        GeometryReader { geo in
            
            let scaleX = geo.size.width / 170
            let scaleY = geo.size.height / 250
            
            ZStack {
                Color.white
                
                Rectangle()
                    .stroke(Color.black.opacity(0.45), lineWidth: 1)
                    .padding(5)
                
                ForEach(layout.makeElements(title: title, includeTitle: true)) { element in
                    PreviewElement(element: element)
                        .frame(
                            width: element.size.width * scaleX,
                            height: element.size.height * scaleY
                        )
                        .position(
                            x: element.position.x * scaleX,
                            y: element.position.y * scaleY
                        )
                }
            }
        }
    }
}

struct PreviewElement: View {
    
    let element: MagazineElement
    
    var body: some View {
        switch element.type {
        case .title:
            Text(element.text)
                .font(.system(size: 9, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(Rectangle().stroke(Color.black.opacity(0.35)))
        case .text:
            VStack(alignment: .leading, spacing: 3) {
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.black.opacity(0.35))
                        .frame(
                            width: CGFloat([50, 40, 48, 35, 44][index]),
                            height: 3
                        )
                }
            }
        case .image:
            Rectangle()
                .fill(Color.white)
                .overlay(Rectangle().stroke(Color.black.opacity(0.45)))
        case .shape:
            ShapeOrIconView(
                shape: element.shape,
                color: .black.opacity(0.45)
            )
        case .drawing:
            EmptyView()
        }
    }
}

// ============================================================
// MARK: - TITLE STYLES
// ============================================================

enum TitleStyle: String, CaseIterable, Identifiable {
    case editorial = "Editorial"
    case futuristic = "Futuristic"
    case handwritten = "Handwritten"
    case brutalist = "Brutalist"
    case elegant = "Elegant"
    case magazine = "Magazine"
    case minimal = "Minimal"
    case typewriter = "Typewriter"
    
    var id: String { rawValue }
    
    var font: Font {
        switch self {
        case .editorial:
            return .system(size: 22, weight: .light, design: .serif)
        case .futuristic:
            return .system(size: 21, weight: .bold, design: .rounded)
        case .handwritten:
            return .custom("Snell Roundhand", size: 24)
        case .brutalist:
            return .system(size: 25, weight: .black)
        case .elegant:
            return .custom("Didot", size: 24)
        case .magazine:
            return .custom("Baskerville", size: 24)
        case .minimal:
            return .system(size: 22, weight: .thin)
        case .typewriter:
            return .system(size: 19, weight: .regular, design: .monospaced)
        }
    }
}

struct TitleStyleButton: View {
    
    let style: TitleStyle
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            Text("Title")
                .font(style.font)
                .minimumScaleFactor(0.45)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isSelected ? Color.black : Color.clear,
                            lineWidth: 2
                        )
                )
            
            Text(style.rawValue)
                .font(.caption)
        }
    }
}

// ============================================================
// MARK: - BUTTONS
// ============================================================

struct EditorActionButton: View {
    
    let icon: String
    let title: String
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.headline)
            
            Text(title)
                .font(.caption)
        }
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// ============================================================
// MARK: - SHAPES / ICONS
// ============================================================

struct ShapeOrIconView: View {
    
    let shape: MagazineShape
    let color: Color
    
    var body: some View {
        switch shape {
        case .circle:
            Circle().fill(color)
        case .rectangle:
            Rectangle().fill(color)
        case .triangle:
            TriangleShape().fill(color)
        case .wave:
            WaveShape().stroke(color, lineWidth: 5)
        case .beams:
            BeamsShape().stroke(color, lineWidth: 4)
        default:
            if let systemImage = shape.systemImage {
                Image(systemName: systemImage)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(color)
                    .padding(6)
            }
        }
    }
}

// ============================================================
// MARK: - DRAWING CANVAS
// ============================================================

struct DrawingCanvasPage: View, LanguageSupporting {
    
    var onSave: (UIImage) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var canvasView = PKCanvasView()
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    
    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .english
    }
    
    var body: some View {
        NavigationStack {
            PencilCanvas(canvasView: $canvasView)
                .navigationTitle(t("Draw Decoration", "Dekoration zeichnen", "Disegna decorazione", "Dibujar decoración", "Dessiner une décoration", language: language))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(t("Cancel", "Abbrechen", "Annulla", "Cancelar", "Annuler", language: language)) {
                            dismiss()
                        }
                    }
                    
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(t("Use Drawing", "Zeichnung verwenden", "Usa disegno", "Usar dibujo", "Utiliser le dessin", language: language)) {
                            let image = canvasView.drawing.image(
                                from: canvasView.bounds,
                                scale: 1.0
                            )
                            onSave(image)
                            dismiss()
                        }
                    }
                }
        }
    }
}

struct PencilCanvas: UIViewRepresentable {
    
    @Binding var canvasView: PKCanvasView
    
    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .clear
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 4)
        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}

// ============================================================
// MARK: - CUSTOM SHAPES
// ============================================================

struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct WaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        
        for x in stride(from: rect.minX, through: rect.maxX, by: 10) {
            let y = rect.midY + sin((x - rect.minX) / 18) * 18
            path.addLine(to: CGPoint(x: x, y: y))
        }
        
        return path
    }
}

struct BeamsShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        
        for angle in stride(from: 0.0, to: 360.0, by: 30.0) {
            let radians = angle * .pi / 180
            let end = CGPoint(
                x: center.x + cos(radians) * rect.width / 2,
                y: center.y + sin(radians) * rect.height / 2
            )
            path.move(to: center)
            path.addLine(to: end)
        }
        
        return path
    }
}
