//
//  OrbitClipboardModels.swift
//  Orbit
//
//  Created by Yuze Pan on 1/10/26.
//

import AppKit
import Foundation
import ImageIO

enum OrbitClipboardItemType: String, Codable {
    case text
    case richText
    case image
    case file
    case url
    case color
    case code
}

struct OrbitClipboardSummary: Codable, Identifiable, Equatable {
    let uniqueId: String
    let itemType: String
    let pasteboardType: String
    let title: String
    let subtitle: String?
    let previewText: String?
    let previewImageData: Data?
    let timestamp: Int64
    let appName: String
    let appPath: String
    let filePaths: [String]?
    let urlString: String?
    let isTemporary: Bool

    var id: String { uniqueId }
}

extension OrbitClipboardSummary {
    var itemTypeValue: OrbitClipboardItemType {
        OrbitClipboardItemType(rawValue: itemType) ?? .text
    }

    var displayTitle: String {
        if let previewText, !previewText.isEmpty {
            return previewText
        }
        return title
    }

    var previewImage: NSImage? {
        let cacheKey = uniqueId as NSString
        if let cached = OrbitClipboardImageCache.previewImages.object(forKey: cacheKey) {
            return cached
        }

        guard let previewImageData else { return nil }
        guard let image = OrbitClipboardImageCache.makeThumbnail(from: previewImageData) else {
            return nil
        }

        OrbitClipboardImageCache.previewImages.setObject(
            image,
            forKey: cacheKey,
            cost: OrbitClipboardImageCache.cacheCost(for: image)
        )
        return image
    }

    var primaryFilePath: String? {
        filePaths?.first
    }
}

private enum OrbitClipboardImageCache {
    static let previewImages: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 32
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()

    static func makeThumbnail(from data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return NSImage(data: data)
        }

        let maxPixelSize = Int(max(CardSize.extraLarge.iconSize * 2, 160))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return NSImage(data: data)
        }

        return NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
    }

    static func cacheCost(for image: NSImage) -> Int {
        let width = max(Int(image.size.width.rounded(.up)), 1)
        let height = max(Int(image.size.height.rounded(.up)), 1)
        return width * height * 4
    }
}

struct OrbitClipboardPayload: Codable, Equatable {
    let uniqueId: String
    let itemType: String
    let pasteboardType: String
    let text: String?
    let urlString: String?
    let filePaths: [String]?
    let imageData: Data?
}

extension OrbitClipboardPayload {
    var itemTypeValue: OrbitClipboardItemType {
        OrbitClipboardItemType(rawValue: itemType) ?? .text
    }
}
