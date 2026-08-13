//
//  ImageCompression.swift
//  TravelingFriends
//
//  Created by Emily on 27/05/2026.
//

import UIKit
import FirebaseAuth
import ImageIO

func compressedBase64Image(from image: UIImage, maxSize: CGFloat = 700, quality: CGFloat = 0.45) -> String? {
    guard let data = compressedImageData(from: image, maxSize: maxSize, quality: quality) else {
        return nil
    }

    return data.base64EncodedString()
}

func compressedImageData(from image: UIImage, maxSize: CGFloat = 700, quality: CGFloat = 0.45, targetMaxBytes: Int? = nil) -> Data? {
    func render(maxSide: CGFloat) -> UIImage {
        let scale = min(maxSide / image.size.width, maxSide / image.size.height, 1)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    var currentMaxSize = maxSize
    var resizedImage = render(maxSide: currentMaxSize)
    var currentQuality = min(quality, 0.56)
    var data = resizedImage.jpegData(compressionQuality: currentQuality)
    if let targetMaxBytes {
        while let currentData = data, currentData.count > targetMaxBytes {
            if currentQuality > 0.36 {
                currentQuality -= 0.08
            } else if currentMaxSize > 760 {
                currentMaxSize *= 0.85
                resizedImage = render(maxSide: currentMaxSize)
                currentQuality = 0.48
            } else {
                break
            }
            data = resizedImage.jpegData(compressionQuality: currentQuality)
        }
    }

    if let data {
        print(
            "IMAGE_COMPRESSED",
            "original", Int(image.size.width), "x", Int(image.size.height),
            "resized", Int(resizedImage.size.width), "x", Int(resizedImage.size.height),
            "bytes", data.count,
            "quality", currentQuality
        )
    }

    return data
}

func imageFromBase64(_ value: String?) -> UIImage? {
    guard Auth.auth().currentUser != nil else {
        print("BLOCKED_QUERY_NO_AUTH", "imageFromBase64")
        return nil
    }

    guard let value else { return nil }
    guard let data = Data(base64Encoded: value) else { return nil }
    return UIImage(data: data)
}

func downsampledImageFromBase64(_ value: String?, maxPixelSize: CGFloat = 1200) -> UIImage? {
    guard Auth.auth().currentUser != nil else {
        print("BLOCKED_QUERY_NO_AUTH", "downsampledImageFromBase64")
        return nil
    }

    guard let value, let data = Data(base64Encoded: value) else { return nil }
    return downsampledImageFromData(data, maxPixelSize: maxPixelSize)
}

func downsampledImageFromData(_ data: Data, maxPixelSize: CGFloat = 1200) -> UIImage? {
    let options = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
        return UIImage(data: data)
    }

    let downsampleOptions = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ] as CFDictionary

    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else {
        return UIImage(data: data)
    }

    return UIImage(cgImage: cgImage)
}

func downsampledImageFromFile(path: String?, maxPixelSize: CGFloat = 1200) -> UIImage? {
    guard let path, !path.isEmpty else { return nil }
    let url = URL(fileURLWithPath: path)
    let options = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else {
        return UIImage(contentsOfFile: path)
    }

    let downsampleOptions = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ] as CFDictionary

    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else {
        return UIImage(contentsOfFile: path)
    }

    return UIImage(cgImage: cgImage)
}

func imageFromBase64MagazinePage(_ value: String?) -> UIImage? {
    return nil
}
