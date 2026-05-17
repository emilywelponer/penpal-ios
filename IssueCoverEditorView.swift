import SwiftUI
import PhotosUI

struct IssueCoverEditorView: View {
    
    @StateObject private var issueStore = IssueDraftStore.shared
    
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.english.rawValue
    
    @State private var coverPage = CoverDesignPage.frontDefault
    @State private var backPage = CoverDesignPage.backDefault
    
    @State private var selectedItemID: UUID?
    @State private var selectedPhotoItem: PhotosPickerItem?
    
    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .english
    }
    
    var body: some View {
        
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                
                Text(t(
                    "Finish your issue",
                    "Beende deine Ausgabe",
                    "Completa il tuo numero",
                    "Termina tu edición",
                    "Finalise ton numéro"
                ))
                .font(.system(size: 30, weight: .light, design: .serif))
                
                Text(t(
                    "Customise your Penpal cover and back page.",
                    "Passe dein Penpal-Cover und die Rückseite an.",
                    "Personalizza la copertina e il retro del tuo Penpal.",
                    "Personaliza la portada y contraportada de tu Penpal.",
                    "Personnalise la couverture et la quatrième de couverture de ton Penpal."
                ))
                .foregroundStyle(.secondary)
                
                Divider()
                
                HStack(spacing: 0) {
                    CoverPageCanvas(
                        page: $coverPage,
                        selectedItemID: $selectedItemID
                    )
                    .frame(width: 170, height: 250)
                    
                    CoverPageCanvas(
                        page: $backPage,
                        selectedItemID: $selectedItemID
                    )
                    .frame(width: 170, height: 250)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(radius: 4)
                .frame(maxWidth: .infinity)
                
                Divider()
                
                Text(t(
                    "Page colours",
                    "Seitenfarben",
                    "Colori pagina",
                    "Colores de página",
                    "Couleurs des pages"
                ))
                .font(.headline)
                
                VStack(alignment: .leading, spacing: 14) {
                    ColorPicker(
                        t(
                            "Cover background",
                            "Cover-Hintergrund",
                            "Sfondo copertina",
                            "Fondo portada",
                            "Fond couverture"
                        ),
                        selection: $coverPage.backgroundColor
                    )
                    
                    ColorPicker(
                        t(
                            "Back cover background",
                            "Rückseiten-Hintergrund",
                            "Sfondo retro",
                            "Fondo contraportada",
                            "Fond quatrième de couverture"
                        ),
                        selection: $backPage.backgroundColor
                    )
                }
                .padding()
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                
                Divider()
                
                Text(t(
                    "Add to cover",
                    "Zum Cover hinzufügen",
                    "Aggiungi alla copertina",
                    "Añadir a la portada",
                    "Ajouter à la couverture"
                ))
                .font(.headline)
                
                HStack(spacing: 12) {
                    Button {
                        addPicture(to: .cover)
                    } label: {
                        CoverActionButton(
                            icon: "photo",
                            title: t("Picture", "Bild", "Immagine", "Imagen", "Image")
                        )
                    }
                    
                    Button {
                        addText(to: .cover)
                    } label: {
                        CoverActionButton(
                            icon: "text.alignleft",
                            title: t("Text", "Text", "Testo", "Texto", "Texte")
                        )
                    }
                }
                
                Text(t(
                    "Add to back cover",
                    "Zur Rückseite hinzufügen",
                    "Aggiungi al retro",
                    "Añadir a la contraportada",
                    "Ajouter à la quatrième de couverture"
                ))
                .font(.headline)
                
                HStack(spacing: 12) {
                    Button {
                        addPicture(to: .back)
                    } label: {
                        CoverActionButton(
                            icon: "photo",
                            title: t("Picture", "Bild", "Immagine", "Imagen", "Image")
                        )
                    }
                    
                    Button {
                        addText(to: .back)
                    } label: {
                        CoverActionButton(
                            icon: "text.alignleft",
                            title: t("Text", "Text", "Testo", "Texto", "Texte")
                        )
                    }
                    
                    Button {
                        deleteSelected()
                    } label: {
                        CoverActionButton(
                            icon: "trash",
                            title: t("Delete", "Löschen", "Elimina", "Eliminar", "Supprimer")
                        )
                    }
                    .disabled(selectedItemID == nil)
                }
                
                Divider()
                
                selectedControls
                
                NavigationLink {
                    PreprintReviewView()
                } label: {
                    Text(t(
                        "Save and review preprint",
                        "Speichern und Preprint prüfen",
                        "Salva e controlla il preprint",
                        "Guardar y revisar preprint",
                        "Sauvegarder et relire le préprint"
                    ))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .simultaneousGesture(
                    TapGesture().onEnded {
                        saveCovers()
                    }
                )
                
                Spacer(minLength: 40)
            }
            .padding()
        }
        .navigationTitle(t(
            "Cover",
            "Cover",
            "Copertina",
            "Portada",
            "Couverture"
        ))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    applyImageToSelected(uiImage)
                }
            }
        }
    }
    
    private var selectedControls: some View {
        
        VStack(alignment: .leading, spacing: 14) {
            
            Text(t(
                "Selected item",
                "Ausgewähltes Element",
                "Elemento selezionato",
                "Elemento seleccionado",
                "Élément sélectionné"
            ))
            .font(.headline)
            
            if let selectedLocation {
                
                let item = selectedLocation.page.items[selectedLocation.index]
                
                if item.kind == .image {
                    
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Text(item.image == nil
                             ? t("Upload picture", "Bild hochladen", "Carica immagine", "Subir imagen", "Importer image")
                             : t("Replace picture", "Bild ersetzen", "Sostituisci immagine", "Reemplazar imagen", "Remplacer image"))
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    
                    Picker(
                        t("Image fit", "Bildanpassung", "Adattamento immagine", "Ajuste de imagen", "Ajustement image"),
                        selection: selectedImageFitBinding(
                            pageSide: selectedLocation.side,
                            index: selectedLocation.index
                        )
                    ) {
                        Text(t("Fit full image", "Ganzes Bild", "Immagine intera", "Imagen completa", "Image entière"))
                            .tag(CoverImageFit.fit)
                        
                        Text(t("Fill / crop", "Füllen / zuschneiden", "Riempi / ritaglia", "Rellenar / recortar", "Remplir / rogner"))
                            .tag(CoverImageFit.fill)
                    }
                    .pickerStyle(.segmented)
                    
                    Text(t(
                        "Tap an empty picture field to upload. After uploading, drag it to move or pull the corner handle to resize.",
                        "Tippe auf ein leeres Bildfeld zum Hochladen. Danach kannst du es ziehen oder über die Ecke vergrößern.",
                        "Tocca un campo immagine vuoto per caricare. Dopo puoi trascinarlo o ridimensionarlo dall’angolo.",
                        "Toca un campo de imagen vacío para subir. Después puedes moverlo o cambiar el tamaño desde la esquina.",
                        "Appuie sur un champ image vide pour importer. Ensuite tu peux le déplacer ou le redimensionner par le coin."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                
                if item.kind == .text || item.kind == .lockedTitle {
                    
                    if item.kind == .text {
                        TextEditor(
                            text: selectedTextBinding(
                                pageSide: selectedLocation.side,
                                index: selectedLocation.index
                            )
                        )
                        .frame(height: 120)
                        .padding(8)
                        .background(Color.gray.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    } else {
                        Text(t(
                            "This text itself is fixed. You can move it, resize it, change colour and change font.",
                            "Dieser Text ist fest. Du kannst ihn verschieben, vergrößern, Farbe und Schrift ändern.",
                            "Questo testo è fisso. Puoi spostarlo, ridimensionarlo, cambiare colore e font.",
                            "Este texto es fijo. Puedes moverlo, cambiar tamaño, color y fuente.",
                            "Ce texte est fixe. Tu peux le déplacer, le redimensionner, changer la couleur et la police."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    
                    ColorPicker(
                        t("Text colour", "Textfarbe", "Colore testo", "Color texto", "Couleur texte"),
                        selection: selectedColorBinding(
                            pageSide: selectedLocation.side,
                            index: selectedLocation.index
                        )
                    )
                    
                    Picker(
                        t("Font style", "Schriftstil", "Stile font", "Estilo de fuente", "Style de police"),
                        selection: selectedFontBinding(
                            pageSide: selectedLocation.side,
                            index: selectedLocation.index
                        )
                    ) {
                        ForEach(TitleStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
            } else {
                Text(t(
                    "Tap an item on the cover or back cover to edit it.",
                    "Tippe auf ein Element auf Cover oder Rückseite, um es zu bearbeiten.",
                    "Tocca un elemento sulla copertina o sul retro per modificarlo.",
                    "Toca un elemento en la portada o contraportada para editarlo.",
                    "Appuie sur un élément de la couverture ou du dos pour le modifier."
                ))
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    
    private enum PageSide {
        case cover
        case back
    }
    
    private func addPicture(to side: PageSide) {
        let newItem = CoverDesignItem(
            kind: .image,
            position: CGPoint(x: 85, y: 140),
            size: CGSize(width: 100, height: 100),
            imageFit: .fit
        )
        
        switch side {
        case .cover:
            coverPage.items.append(newItem)
        case .back:
            backPage.items.append(newItem)
        }
        
        selectedItemID = newItem.id
    }
    
    private func addText(to side: PageSide) {
        let newItem = CoverDesignItem(
            kind: .text,
            text: "",
            position: CGPoint(x: 85, y: 180),
            size: CGSize(width: 120, height: 60),
            font: .editorial,
            color: .black
        )
        
        switch side {
        case .cover:
            coverPage.items.append(newItem)
        case .back:
            backPage.items.append(newItem)
        }
        
        selectedItemID = newItem.id
    }
    
    private func deleteSelected() {
        guard let selectedItemID else { return }
        
        coverPage.items.removeAll {
            $0.id == selectedItemID && !$0.kind.isLocked
        }
        
        backPage.items.removeAll {
            $0.id == selectedItemID && !$0.kind.isLocked
        }
        
        self.selectedItemID = nil
    }
    
    private func applyImageToSelected(_ image: UIImage) {
        guard let selectedItemID else { return }
        
        if let index = coverPage.items.firstIndex(where: { $0.id == selectedItemID }) {
            coverPage.items[index].image = image
            coverPage.items[index].size = fittedSize(for: image)
            coverPage.items[index].imageFit = .fit
        }
        
        if let index = backPage.items.firstIndex(where: { $0.id == selectedItemID }) {
            backPage.items[index].image = image
            backPage.items[index].size = fittedSize(for: image)
            backPage.items[index].imageFit = .fit
        }
    }
    
    private func fittedSize(for image: UIImage) -> CGSize {
        let maxWidth: CGFloat = 130
        let maxHeight: CGFloat = 130
        
        guard image.size.width > 0, image.size.height > 0 else {
            return CGSize(width: 110, height: 110)
        }
        
        let scale = min(maxWidth / image.size.width, maxHeight / image.size.height)
        
        return CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
    }
    
    private func saveCovers() {
        let cover = coverPage.makeMagazinePage(sectionTitle: "Cover")
        let back = backPage.makeMagazinePage(sectionTitle: "Back Cover")
        
        issueStore.pages.removeAll {
            $0.sectionTitle == "Cover" || $0.sectionTitle == "Back Cover"
        }
        
        issueStore.pages.insert(cover, at: 0)
        issueStore.pages.append(back)
    }
    
    private var selectedLocation: (side: PageSide, page: CoverDesignPage, index: Int)? {
        guard let selectedItemID else { return nil }
        
        if let index = coverPage.items.firstIndex(where: { $0.id == selectedItemID }) {
            return (.cover, coverPage, index)
        }
        
        if let index = backPage.items.firstIndex(where: { $0.id == selectedItemID }) {
            return (.back, backPage, index)
        }
        
        return nil
    }
    
    private func selectedTextBinding(pageSide: PageSide, index: Int) -> Binding<String> {
        Binding(
            get: {
                pageSide == .cover ? coverPage.items[index].text : backPage.items[index].text
            },
            set: { newValue in
                if pageSide == .cover {
                    coverPage.items[index].text = newValue
                } else {
                    backPage.items[index].text = newValue
                }
            }
        )
    }
    
    private func selectedColorBinding(pageSide: PageSide, index: Int) -> Binding<Color> {
        Binding(
            get: {
                pageSide == .cover ? coverPage.items[index].color : backPage.items[index].color
            },
            set: { newValue in
                if pageSide == .cover {
                    coverPage.items[index].color = newValue
                } else {
                    backPage.items[index].color = newValue
                }
            }
        )
    }
    
    private func selectedFontBinding(pageSide: PageSide, index: Int) -> Binding<TitleStyle> {
        Binding(
            get: {
                pageSide == .cover ? coverPage.items[index].font : backPage.items[index].font
            },
            set: { newValue in
                if pageSide == .cover {
                    coverPage.items[index].font = newValue
                } else {
                    backPage.items[index].font = newValue
                }
            }
        )
    }
    
    private func selectedImageFitBinding(pageSide: PageSide, index: Int) -> Binding<CoverImageFit> {
        Binding(
            get: {
                pageSide == .cover ? coverPage.items[index].imageFit : backPage.items[index].imageFit
            },
            set: { newValue in
                if pageSide == .cover {
                    coverPage.items[index].imageFit = newValue
                } else {
                    backPage.items[index].imageFit = newValue
                }
            }
        )
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

// ============================================================
// MARK: - COVER PAGE CANVAS
// ============================================================

struct CoverPageCanvas: View {
    
    @Binding var page: CoverDesignPage
    @Binding var selectedItemID: UUID?
    
    var body: some View {
        ZStack {
            page.backgroundColor
            
            Rectangle()
                .stroke(Color.black.opacity(0.18), lineWidth: 1)
                .padding(6)
            
            ForEach($page.items) { $item in
                CoverCanvasItemView(
                    item: $item,
                    isSelected: selectedItemID == item.id
                )
                .onTapGesture {
                    selectedItemID = item.id
                }
            }
        }
        .clipped()
    }
}

// ============================================================
// MARK: - COVER ITEM VIEW
// ============================================================

struct CoverCanvasItemView: View {
    
    @Binding var item: CoverDesignItem
    
    let isSelected: Bool
    
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var dragStartPosition: CGPoint?
    @State private var resizeStartSize: CGSize?
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            
            content
                .frame(width: item.size.width, height: item.size.height)
                .contentShape(Rectangle())
                .gesture(moveGesture)
            
            if isSelected {
                Rectangle()
                    .stroke(Color.black, lineWidth: 2)
                    .frame(width: item.size.width, height: item.size.height)
                
                resizeHandle
            }
        }
        .position(item.position)
    }
    
    @ViewBuilder
    private var content: some View {
        switch item.kind {
            
        case .image:
            ZStack {
                if let image = item.image {
                    if item.imageFit == .fill {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: item.size.width, height: item.size.height)
                            .clipped()
                    } else {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: item.size.width, height: item.size.height)
                            .clipped()
                    }
                } else {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        ZStack {
                            Rectangle()
                                .fill(Color.white.opacity(0.75))
                            
                            Rectangle()
                                .stroke(Color.black.opacity(0.35))
                            
                            Image(systemName: "plus.circle")
                                .font(.title3)
                                .foregroundStyle(.black.opacity(0.6))
                        }
                    }
                    .buttonStyle(.plain)
                    .onChange(of: selectedPhotoItem) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self),
                               let uiImage = UIImage(data: data) {
                                item.image = uiImage
                                item.size = fittedSize(for: uiImage)
                                item.imageFit = .fit
                            }
                        }
                    }
                }
            }
            
        case .text:
            Text(item.text.isEmpty ? " " : item.text)
                .font(item.font.font)
                .foregroundStyle(item.color)
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.25)
                .lineLimit(nil)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(5)
                .background(Color.clear)
            
        case .lockedTitle:
            Text(item.text)
                .font(item.font.font)
                .foregroundStyle(item.color)
                .minimumScaleFactor(0.2)
                .lineLimit(nil)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(4)
        }
    }
    
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragStartPosition == nil {
                    dragStartPosition = item.position
                }
                
                guard let dragStartPosition else { return }
                
                item.position = CGPoint(
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
            .padding(6)
            .background(Color.white)
            .clipShape(Circle())
            .shadow(radius: 2)
            .offset(x: -6, y: -6)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if resizeStartSize == nil {
                            resizeStartSize = item.size
                        }
                        
                        guard let resizeStartSize else { return }
                        
                        item.size = CGSize(
                            width: max(25, resizeStartSize.width + value.translation.width),
                            height: max(22, resizeStartSize.height + value.translation.height)
                        )
                    }
                    .onEnded { _ in
                        resizeStartSize = nil
                    }
            )
    }
    
    private func fittedSize(for image: UIImage) -> CGSize {
        let maxWidth: CGFloat = 130
        let maxHeight: CGFloat = 130
        
        let imageWidth = image.size.width
        let imageHeight = image.size.height
        
        guard imageWidth > 0, imageHeight > 0 else {
            return CGSize(width: 110, height: 110)
        }
        
        let scale = min(maxWidth / imageWidth, maxHeight / imageHeight)
        
        return CGSize(
            width: imageWidth * scale,
            height: imageHeight * scale
        )
    }
}

// ============================================================
// MARK: - COVER MODELS
// ============================================================

struct CoverDesignPage {
    var backgroundColor: Color
    var items: [CoverDesignItem]
    
    static var frontDefault: CoverDesignPage {
        CoverDesignPage(
            backgroundColor: Color(red: 0.97, green: 0.94, blue: 0.86),
            items: [
                CoverDesignItem(
                    kind: .lockedTitle,
                    text: "Penpal",
                    position: CGPoint(x: 85, y: 35),
                    size: CGSize(width: 135, height: 45),
                    font: .editorial,
                    color: .black
                ),
                CoverDesignItem(
                    kind: .image,
                    position: CGPoint(x: 85, y: 135),
                    size: CGSize(width: 120, height: 120),
                    imageFit: .fit
                )
            ]
        )
    }
    
    static var backDefault: CoverDesignPage {
        CoverDesignPage(
            backgroundColor: Color(red: 0.97, green: 0.94, blue: 0.86),
            items: [
                CoverDesignItem(
                    kind: .lockedTitle,
                    text: "THE END",
                    position: CGPoint(x: 85, y: 45),
                    size: CGSize(width: 135, height: 55),
                    font: .brutalist,
                    color: .black
                ),
                CoverDesignItem(
                    kind: .text,
                    text: """
Dear reader,

I hope you enjoyed this issue of Penpal.
This is a small collection of thoughts, memories, favourites, moods and little moments I wanted to keep.
""",
                    position: CGPoint(x: 85, y: 165),
                    size: CGSize(width: 135, height: 110),
                    font: .editorial,
                    color: .black
                )
            ]
        )
    }
    
    func makeMagazinePage(sectionTitle: String) -> MagazinePage {
        MagazinePage(
            title: sectionTitle,
            sectionTitle: sectionTitle,
            layout: .layout1,
            elements: items.map { $0.makeMagazineElement() },
            titleStyle: firstTitleStyle,
            backgroundColor: UIColor(backgroundColor),
            titleColor: UIColor(firstTitleColor),
            textColor: UIColor(firstTextColor)
        )
    }
    
    private var firstTitleStyle: TitleStyle {
        items.first(where: { $0.kind == .lockedTitle })?.font ?? .editorial
    }
    
    private var firstTitleColor: Color {
        items.first(where: { $0.kind == .lockedTitle })?.color ?? .black
    }
    
    private var firstTextColor: Color {
        items.first(where: { $0.kind == .text })?.color ?? .black
    }
}

struct CoverDesignItem: Identifiable {
    let id = UUID()
    
    var kind: CoverItemKind
    var text: String = ""
    var image: UIImage? = nil
    
    var position: CGPoint
    var size: CGSize
    
    var font: TitleStyle = .editorial
    var color: Color = .black
    
    var imageFit: CoverImageFit = .fit
    
    func makeMagazineElement() -> MagazineElement {
        MagazineElement(
            type: magazineType,
            text: text,
            image: image,
            position: position,
            size: size,
            textBackgroundColor: UIColor.clear,
            isTextLocked: kind.isLocked
        )
    }
    
    private var magazineType: MagazineElementType {
        switch kind {
        case .image:
            return .image
        case .text:
            return .text
        case .lockedTitle:
            return .title
        }
    }
}

enum CoverItemKind {
    case image
    case text
    case lockedTitle
    
    var isLocked: Bool {
        switch self {
        case .lockedTitle:
            return true
        case .image, .text:
            return false
        }
    }
}

enum CoverImageFit {
    case fill
    case fit
}

// ============================================================
// MARK: - COVER BUTTON
// ============================================================

struct CoverActionButton: View {
    
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
