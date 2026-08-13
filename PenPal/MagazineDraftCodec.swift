import Foundation
import UIKit
import Compression
import FirebaseAuth

enum MagazineDraftCodec {
    static func encode(_ pages: [MagazinePage]) -> String? {
        let imageCount = pages.reduce(0) { count, page in
            count + page.elements.filter { $0.type == .image && $0.image != nil }.count
        }
        if imageCount > 0 {
            print("MagazineDraftCodec encode image count:", imageCount)
        }
        let payload = MagazineDraftPayload(pages: pages.map(MagazineDraftPage.init(page:)))
        do {
            let data = try JSONEncoder().encode(payload)
            return String(data: data, encoding: .utf8)
        } catch {
            print("MagazineDraftCodec encode error:", error)
            return nil
        }
    }

    static func decode(_ value: String?, decodeImages: Bool = true) -> [MagazinePage] {
        guard Auth.auth().currentUser?.uid != nil else {
            print("BLOCKED_QUERY_NO_AUTH", "MagazineDraftCodec.decode")
            return []
        }

        guard let value, !value.isEmpty else {
            print("MagazineDraftCodec decode error: empty pageDraftData")
            return []
        }

        guard let data = draftData(from: value) else {
            print("MagazineDraftCodec decode error: value is neither JSON nor base64 encoded draft data")
            return []
        }

        let decoder = JSONDecoder()

        do {
            let payload = try decoder.decode(MagazineDraftPayload.self, from: data)
            return payload.pages.map { $0.makeMagazinePage(decodeImages: decodeImages) }
        } catch {
            print("MagazineDraftCodec wrapper decode error:", error)
        }

        do {
            let draftPages = try decoder.decode([MagazineDraftPage].self, from: data)
            return draftPages.map { $0.makeMagazinePage(decodeImages: decodeImages) }
        } catch {
            print("MagazineDraftCodec array decode error:", error)
        }

        do {
            let nestedValue = try decoder.decode(String.self, from: data)
            return decode(nestedValue, decodeImages: decodeImages)
        } catch {
            print("MagazineDraftCodec nested string decode error:", error)
        }

        return []
    }
}

private func draftData(from value: String) -> Data? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") || trimmed.hasPrefix("\"") {
        return Data(trimmed.utf8)
    }

    guard let encodedData = Data(base64Encoded: trimmed, options: .ignoreUnknownCharacters) else {
        return nil
    }

    return decompressed(encodedData) ?? encodedData
}

private func compressed(_ data: Data) -> Data? {
    guard !data.isEmpty else { return data }

    return data.withUnsafeBytes { sourceBuffer in
        guard let sourcePointer = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else { return nil }
        let destinationSize = max(64, data.count)
        let destinationPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationSize)
        defer { destinationPointer.deallocate() }

        let compressedSize = compression_encode_buffer(
            destinationPointer,
            destinationSize,
            sourcePointer,
            data.count,
            nil,
            COMPRESSION_ZLIB
        )

        guard compressedSize > 0 else { return nil }
        return Data(bytes: destinationPointer, count: compressedSize)
    }
}

private func decompressed(_ data: Data) -> Data? {
    guard !data.isEmpty else { return data }

    return data.withUnsafeBytes { sourceBuffer in
        guard let sourcePointer = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else { return nil }

        var destinationSize = max(1024, data.count * 4)
        for _ in 0..<6 {
            let destinationPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationSize)
            defer { destinationPointer.deallocate() }

            let decompressedSize = compression_decode_buffer(
                destinationPointer,
                destinationSize,
                sourcePointer,
                data.count,
                nil,
                COMPRESSION_ZLIB
            )

            if decompressedSize > 0 {
                return Data(bytes: destinationPointer, count: decompressedSize)
            }

            destinationSize *= 2
        }

        return nil
    }
}

private struct MagazineDraftPayload: Codable {
    var pages: [MagazineDraftPage]
}

private struct MagazineDraftPage: Codable {
    var title: String
    var sectionTitle: String
    var elements: [MagazineDraftElement]
    var titleStyle: String
    var backgroundColor: String
    var titleColor: String
    var textColor: String

    init(page: MagazinePage) {
        title = page.title
        sectionTitle = page.sectionTitle
        elements = page.elements.map(MagazineDraftElement.init(element:))
        titleStyle = page.titleStyle.rawValue
        backgroundColor = rgbaString(from: page.backgroundColor)
        titleColor = rgbaString(from: page.titleColor)
        textColor = rgbaString(from: page.textColor)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        sectionTitle = try container.decodeIfPresent(String.self, forKey: .sectionTitle) ?? ""
        elements = try container.decodeIfPresent([MagazineDraftElement].self, forKey: .elements) ?? []
        titleStyle = try container.decodeIfPresent(String.self, forKey: .titleStyle) ?? TitleStyle.editorial.rawValue
        backgroundColor = try container.decodeIfPresent(String.self, forKey: .backgroundColor) ?? rgbaString(from: .white)
        titleColor = try container.decodeIfPresent(String.self, forKey: .titleColor) ?? rgbaString(from: .black)
        textColor = try container.decodeIfPresent(String.self, forKey: .textColor) ?? rgbaString(from: .black)
    }

    func makeMagazinePage(decodeImages: Bool = true) -> MagazinePage {
        MagazinePage(
            title: title,
            sectionTitle: sectionTitle,
            elements: elements.map { $0.makeMagazineElement(decodeImages: decodeImages) },
            titleStyle: TitleStyle(rawValue: titleStyle) ?? .editorial,
            backgroundColor: uiColor(from: backgroundColor),
            titleColor: uiColor(from: titleColor),
            textColor: uiColor(from: textColor),
            layout: .layout1
        )
    }
}

private struct MagazineDraftElement: Codable {
    var type: String
    var text: String
    var imageData: String?
    var localImagePath: String?
    var imageStoragePath: String?
    var positionX: Double
    var positionY: Double
    var width: Double
    var height: Double
    var fontSize: Double
    var fontName: String
    var isBold: Bool
    var isEditableText: Bool
    var imageZoom: Double
    var imageOffsetWidth: Double
    var imageOffsetHeight: Double
    var textBackgroundColor: String
    var isTextLocked: Bool
    var imageFit: String
    var textAlignment: String
    var verticalAlignment: String
    var textInsetWidth: Double
    var textInsetHeight: Double
    var isMarked: Bool
    var interactionValue: Double

    init(element: MagazineElement) {
        type = string(from: element.type)
        text = element.text
        localImagePath = element.localImagePath
        imageStoragePath = element.imageStoragePath
        if let imageStoragePath, !imageStoragePath.isEmpty {
            imageData = nil
        } else if let image = element.image {
            imageData = compressedBase64Image(from: image, maxSize: 850, quality: 0.68)
            if imageData == nil {
                print("MagazineDraftCodec image encode error for element at", element.position, "size", element.size)
            }
        } else {
            imageData = element.imageData
        }
        positionX = element.position.x
        positionY = element.position.y
        width = element.size.width
        height = element.size.height
        fontSize = element.fontSize
        fontName = element.fontName
        isBold = element.isBold
        isEditableText = element.isEditableText
        imageZoom = element.imageZoom
        imageOffsetWidth = element.imageOffset.width
        imageOffsetHeight = element.imageOffset.height
        textBackgroundColor = rgbaString(from: element.textBackgroundColor)
        isTextLocked = element.isTextLocked
        imageFit = element.imageFit == .fit ? "fit" : "fill"
        textAlignment = string(from: element.textAlignment)
        verticalAlignment = string(from: element.verticalAlignment)
        textInsetWidth = element.textInset.width
        textInsetHeight = element.textInset.height
        isMarked = element.isMarked
        interactionValue = element.interactionValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "text"
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        imageData = try container.decodeIfPresent(String.self, forKey: .imageData)
        localImagePath = try container.decodeIfPresent(String.self, forKey: .localImagePath)
        imageStoragePath = try container.decodeIfPresent(String.self, forKey: .imageStoragePath)
        positionX = try container.decodeIfPresent(Double.self, forKey: .positionX) ?? 0
        positionY = try container.decodeIfPresent(Double.self, forKey: .positionY) ?? 0
        width = try container.decodeIfPresent(Double.self, forKey: .width) ?? 0
        height = try container.decodeIfPresent(Double.self, forKey: .height) ?? 0
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 8
        fontName = try container.decodeIfPresent(String.self, forKey: .fontName) ?? "Helvetica"
        isBold = try container.decodeIfPresent(Bool.self, forKey: .isBold) ?? false
        isEditableText = try container.decodeIfPresent(Bool.self, forKey: .isEditableText) ?? false
        imageZoom = try container.decodeIfPresent(Double.self, forKey: .imageZoom) ?? 1
        imageOffsetWidth = try container.decodeIfPresent(Double.self, forKey: .imageOffsetWidth) ?? 0
        imageOffsetHeight = try container.decodeIfPresent(Double.self, forKey: .imageOffsetHeight) ?? 0
        textBackgroundColor = try container.decodeIfPresent(String.self, forKey: .textBackgroundColor) ?? rgbaString(from: .clear)
        isTextLocked = try container.decodeIfPresent(Bool.self, forKey: .isTextLocked) ?? false
        imageFit = try container.decodeIfPresent(String.self, forKey: .imageFit) ?? "fill"
        textAlignment = try container.decodeIfPresent(String.self, forKey: .textAlignment) ?? "left"
        verticalAlignment = try container.decodeIfPresent(String.self, forKey: .verticalAlignment) ?? "top"
        textInsetWidth = try container.decodeIfPresent(Double.self, forKey: .textInsetWidth) ?? 3.09
        textInsetHeight = try container.decodeIfPresent(Double.self, forKey: .textInsetHeight) ?? 1.47
        isMarked = try container.decodeIfPresent(Bool.self, forKey: .isMarked) ?? false
        interactionValue = try container.decodeIfPresent(Double.self, forKey: .interactionValue) ?? 0
    }

    func makeMagazineElement(decodeImages: Bool = true) -> MagazineElement {
        return MagazineElement(
            type: magazineElementType(from: type),
            text: text,
            image: decodeImages ? decodedImage() : nil,
            imageData: imageData,
            localImagePath: localImagePath,
            imageStoragePath: imageStoragePath,
            position: CGPoint(x: positionX, y: positionY),
            size: CGSize(width: width, height: height),
            fontSize: fontSize,
            fontName: fontName,
            isBold: isBold,
            isEditableText: isEditableText,
            imageZoom: imageZoom,
            imageOffset: CGSize(width: imageOffsetWidth, height: imageOffsetHeight),
            textBackgroundColor: uiColor(from: textBackgroundColor),
            isTextLocked: isTextLocked,
            imageFit: imageFit == "fit" ? .fit : .fill,
            textAlignment: textAlignmentValue(from: textAlignment),
            verticalAlignment: verticalAlignmentValue(from: verticalAlignment),
            textInset: CGSize(width: textInsetWidth, height: textInsetHeight),
            isMarked: isMarked,
            interactionValue: interactionValue
        )
    }

    private func decodedImage() -> UIImage? {
        guard let imageData, !imageData.isEmpty else { return nil }
        let image = downsampledImageFromBase64(imageData, maxPixelSize: 850)
        if image == nil {
            print("MagazineDraftCodec image decode error for element at", positionX, positionY, "chars", imageData.count)
        }
        return image
    }
}

private func rgbaString(from color: UIColor) -> String {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return "\(red),\(green),\(blue),\(alpha)"
}

private func uiColor(from value: String) -> UIColor {
    let parts = value.split(separator: ",").compactMap { Double($0) }
    guard parts.count == 4 else { return .clear }
    return UIColor(red: parts[0], green: parts[1], blue: parts[2], alpha: parts[3])
}

private func string(from type: MagazineElementType) -> String {
    switch type {
    case .title: return "title"
    case .text: return "text"
    case .image: return "image"
    case .line: return "line"
    case .box: return "box"
    }
}

private func magazineElementType(from value: String) -> MagazineElementType {
    switch value {
    case "title": return .title
    case "image": return .image
    case "line": return .line
    case "box": return .box
    default: return .text
    }
}

private func string(from alignment: PPTTextHorizontalAlignment) -> String {
    switch alignment {
    case .left: return "left"
    case .center: return "center"
    case .right: return "right"
    }
}

private func textAlignmentValue(from value: String) -> PPTTextHorizontalAlignment {
    switch value {
    case "center": return .center
    case "right": return .right
    default: return .left
    }
}

private func string(from alignment: PPTTextVerticalAlignment) -> String {
    switch alignment {
    case .top: return "top"
    case .middle: return "middle"
    case .bottom: return "bottom"
    }
}

private func verticalAlignmentValue(from value: String) -> PPTTextVerticalAlignment {
    switch value {
    case "middle": return .middle
    case "bottom": return .bottom
    default: return .top
    }
}
