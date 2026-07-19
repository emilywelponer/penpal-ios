import Foundation
import UIKit

struct LocalIssueDraftInfo {
    var id: String
    var title: String
    var updatedAt: Date
    var pageCount: Int
    var previewImagePath: String?
    var colourSchemeRaw: String?
}

enum LocalIssueDraftStore {
    private static let folderName = "LocalIssueDrafts"
    private static let dataFileName = "draft.json"
    private static let metadataFileName = "metadata.json"
    private static let imagesFolderName = "Images"

    static func save(
        pages: [MagazinePage],
        title: String,
        draftID: String = UUID().uuidString,
        colourScheme: PenPalColourScheme? = nil,
        previewImageData: String? = nil
    ) throws -> LocalIssueDraftInfo {
        let directory = try draftDirectory(id: draftID)
        let imagesDirectory = directory.appendingPathComponent(imagesFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)

        var preparedPages = pages
        var firstPreviewPath = existingPreviewPath(in: directory)

        if let previewImageData,
           let data = Data(base64Encoded: previewImageData) {
            let previewURL = directory.appendingPathComponent("preview.jpg")
            try data.write(to: previewURL, options: .atomic)
            firstPreviewPath = previewURL.path
        }

        for pageIndex in preparedPages.indices {
            for elementIndex in preparedPages[pageIndex].elements.indices {
                guard case .image = preparedPages[pageIndex].elements[elementIndex].type else { continue }

                let elementID = preparedPages[pageIndex].elements[elementIndex].id.uuidString
                let fileName = "page-\(pageIndex)-element-\(elementID).jpg"
                let imageURL = imagesDirectory.appendingPathComponent(fileName)

                if let localPath = preparedPages[pageIndex].elements[elementIndex].localImagePath,
                   FileManager.default.fileExists(atPath: localPath) {
                    let fileSize = (try? FileManager.default.attributesOfItem(atPath: localPath)[.size] as? NSNumber)?.intValue ?? 0
                    if fileSize > 500_000,
                       let image = downsampledImageFromFile(path: localPath, maxPixelSize: 1200),
                       let data = compressedImageData(from: image, maxSize: 1200, quality: 0.56, targetMaxBytes: 500_000) {
                        try data.write(to: imageURL, options: .atomic)
                        preparedPages[pageIndex].elements[elementIndex].localImagePath = imageURL.path
                        firstPreviewPath = firstPreviewPath ?? imageURL.path
                    } else {
                        firstPreviewPath = firstPreviewPath ?? localPath
                    }
                    preparedPages[pageIndex].elements[elementIndex].imageData = nil
                } else if let image = preparedPages[pageIndex].elements[elementIndex].image,
                   let data = compressedImageData(from: image, maxSize: 1200, quality: 0.56, targetMaxBytes: 500_000) {
                    try data.write(to: imageURL, options: .atomic)
                    preparedPages[pageIndex].elements[elementIndex].localImagePath = imageURL.path
                    preparedPages[pageIndex].elements[elementIndex].imageData = nil
                    firstPreviewPath = firstPreviewPath ?? imageURL.path
                } else if let imageData = preparedPages[pageIndex].elements[elementIndex].imageData,
                          !imageData.isEmpty,
                          let rawData = Data(base64Encoded: imageData),
                          let image = UIImage(data: rawData),
                          let data = compressedImageData(from: image, maxSize: 1200, quality: 0.56, targetMaxBytes: 500_000) {
                    try data.write(to: imageURL, options: .atomic)
                    preparedPages[pageIndex].elements[elementIndex].localImagePath = imageURL.path
                    preparedPages[pageIndex].elements[elementIndex].imageData = nil
                    firstPreviewPath = firstPreviewPath ?? imageURL.path
                }
            }
        }

        guard let encoded = MagazineDraftCodec.encode(preparedPages) else {
            throw LocalIssueDraftError.encodingFailed
        }

        let updatedAt = Date()
        let info = LocalIssueDraftInfo(
            id: draftID,
            title: title,
            updatedAt: updatedAt,
            pageCount: preparedPages.count,
            previewImagePath: firstPreviewPath,
            colourSchemeRaw: colourScheme?.rawValue
        )
        let metadata = LocalIssueDraftMetadata(
            id: draftID,
            title: title,
            updatedAt: updatedAt,
            pageCount: preparedPages.count,
            previewImagePath: firstPreviewPath,
            colourSchemeRaw: colourScheme?.rawValue
        )

        try encoded.write(to: dataURL(in: directory), atomically: true, encoding: .utf8)
        let metadataData = try JSONEncoder().encode(metadata)
        try metadataData.write(to: metadataURL(in: directory), options: .atomic)

        return info
    }

    static func loadPages(id: String) throws -> [MagazinePage] {
        let data = try String(contentsOf: dataURL(in: draftDirectory(id: id)), encoding: .utf8)
        return MagazineDraftCodec.decode(data, decodeImages: false)
    }

    static func loadPages() throws -> [MagazinePage] {
        guard let first = list().first else { return [] }
        return try loadPages(id: first.id)
    }

    private static func existingPreviewPath(in directory: URL) -> String? {
        guard let data = try? Data(contentsOf: metadataURL(in: directory)),
              let metadata = try? JSONDecoder().decode(LocalIssueDraftMetadata.self, from: data),
              let path = metadata.previewImagePath,
              FileManager.default.fileExists(atPath: path)
        else { return nil }
        return path
    }

    static func list() -> [LocalIssueDraftInfo] {
        guard let root = try? draftsRootDirectory() else { return [] }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls.compactMap { url in
            guard url.hasDirectoryPath,
                  let data = try? Data(contentsOf: metadataURL(in: url)),
                  let metadata = try? JSONDecoder().decode(LocalIssueDraftMetadata.self, from: data)
            else { return nil }

            return LocalIssueDraftInfo(
                id: metadata.id,
                title: metadata.title,
                updatedAt: metadata.updatedAt,
                pageCount: metadata.pageCount,
                previewImagePath: metadata.previewImagePath,
                colourSchemeRaw: metadata.colourSchemeRaw
            )
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    static func info() -> LocalIssueDraftInfo? {
        list().first
    }

    static func delete(id: String) throws {
        let directory = try draftDirectory(id: id)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    static func delete() throws {
        if let first = list().first {
            try delete(id: first.id)
        }
    }

    private static func draftsRootDirectory() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let root = baseURL.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func draftDirectory(id: String) throws -> URL {
        try draftsRootDirectory().appendingPathComponent(id, isDirectory: true)
    }

    private static func dataURL(in directory: URL) -> URL {
        directory.appendingPathComponent(dataFileName)
    }

    private static func metadataURL(in directory: URL) -> URL {
        directory.appendingPathComponent(metadataFileName)
    }
}

private struct LocalIssueDraftMetadata: Codable {
    var id: String
    var title: String
    var updatedAt: Date
    var pageCount: Int
    var previewImagePath: String?
    var colourSchemeRaw: String?
}

enum LocalIssueDraftError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Draft could not be encoded."
        }
    }
}
