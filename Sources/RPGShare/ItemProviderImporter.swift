// @copyright André Trettin

import CoreRPG
import ImageIO
import os.log
import SwiftUI
import UniformTypeIdentifiers

struct ImageItem: Identifiable, Hashable {
    let id = UUID()
    var imageData: Data
}

@MainActor
final class ItemProviderImporter {
    enum Error: Swift.Error {
        case noItems
        case failedToLoad
    }
    
    func loadImages(from items: [NSItemProvider]) async throws -> [ImageItem] {
        let permissibleTypes: [UTType] = [.image, .url]
        let providersAndTypes = Self.providersAndTypes(from: items, permissibleTypes: permissibleTypes)

        var images: [ImageItem] = []
        var totalPayloadSize = 0
        for (provider, type) in providersAndTypes {
            try Task.checkCancellation()
            // Caps total in-flight payload across multiple shared attachments — the Share
            // Extension's tight (~120MB) memory budget is shared across every image held in
            // `images`, not just the largest one. See CODE_AUDIT §6.3.
            guard totalPayloadSize < Self.maximumTotalImagePayloadSize else {
                logger.warning("\(#function): dropping remaining image(s); total payload budget reached")
                break
            }
            do {
                let image = try await Self.loadImage(provider: provider, type: type)
                totalPayloadSize += image.imageData.count
                images.append(image)
            } catch {
                logger.error("\(#function): \(error)")
            }
        }

        guard !images.isEmpty else {
            let error = Error.noItems
            logger.warning("\(#function): \(error)")
            throw error
        }

        return images
    }

    func loadTexts(from items: [NSItemProvider]) async throws -> [String] {
        let permissibleTypes: [UTType] = [.text, .plainText]
        let providersAndTypes = Self.providersAndTypes(from: items, permissibleTypes: permissibleTypes)

        var texts: [String] = []
        for (provider, type) in providersAndTypes {
            try Task.checkCancellation()
            do {
                texts.append(try await Self.loadText(provider: provider, type: type))
            } catch {
                logger.error("\(#function): \(error)")
            }
        }

        guard !texts.isEmpty else {
            let error = Error.noItems
            logger.warning("\(#function): \(error)")
            throw error
        }

        return texts
    }
}

@MainActor
fileprivate let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "RPGShare",
    category: "ItemProviderImporter"
)

private extension ItemProviderImporter {
    enum LoadedItem: Sendable {
        case data(Data)
        case text(String)
        case url(URL)
    }

    nonisolated static func providersAndTypes(from items: [NSItemProvider], permissibleTypes: [UTType]) -> [(NSItemProvider, UTType)] {
        items.compactMap { provider in
            for type in permissibleTypes where provider.hasItemConformingToTypeIdentifier(type.identifier) {
                return (provider, type)
            }
            return nil
        }
    }

    nonisolated static func loadImage(provider: NSItemProvider, type: UTType) async throws -> ImageItem {
        let item = try await loadItem(provider: provider, type: type)
        try Task.checkCancellation()

        if case .data(let data) = item {
            return ImageItem(imageData: downsampledIfNeeded(data))
        }

        guard case .url(let url) = item else {
            throw Error.noItems
        }

        let data = try await data(from: url)
        try Task.checkCancellation()
        return ImageItem(imageData: downsampledIfNeeded(data))
    }

    /// A single large photo (ProRAW, HEIC panorama) can on its own exceed the Share
    /// Extension's ~120MB budget. Downsamples via ImageIO's thumbnail generator — which
    /// decodes directly at the target size rather than fully decoding the source and scaling
    /// afterward — so the oversized original is never fully materialized in memory. Small
    /// images pass through untouched. See CODE_AUDIT §6.3.
    nonisolated static func downsampledIfNeeded(_ data: Data) -> Data {
        guard data.count > maximumRawImageByteSize,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return data
        }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumDownsampledPixelDimension,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return data
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return data
        }
        CGImageDestinationAddImage(
            destination,
            thumbnail,
            [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            return data
        }
        return output as Data
    }

    nonisolated static let maximumRawImageByteSize = 8 * 1_024 * 1_024
    nonisolated static let maximumDownsampledPixelDimension: CGFloat = 4_096
    nonisolated static let maximumTotalImagePayloadSize = 60 * 1_024 * 1_024

    nonisolated static func loadText(provider: NSItemProvider, type: UTType) async throws -> String {
        let item = try await loadItem(provider: provider, type: type)
        try Task.checkCancellation()

        if case .text(let text) = item {
            return text
        }
        if case .data(let data) = item, let text = String(data: data, encoding: .utf8) {
            return text
        }
        if case .url(let url) = item {
            let data = try await data(from: url)
            if let text = String(data: data, encoding: .utf8) {
                return text
            }
        }

        throw Error.noItems
    }

    nonisolated static func loadItem(provider: NSItemProvider, type: UTType) async throws -> LoadedItem {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let item else {
                    continuation.resume(throwing: Error.noItems)
                    return
                }
                if let data = item as? Data {
                    continuation.resume(returning: .data(data))
                } else if let data = item as? NSData {
                    continuation.resume(returning: .data(data as Data))
                } else if let text = item as? String {
                    continuation.resume(returning: .text(text))
                } else if let text = item as? NSString {
                    continuation.resume(returning: .text(text as String))
                } else if let url = item as? URL {
                    continuation.resume(returning: .url(url))
                } else {
                    continuation.resume(throwing: Error.noItems)
                }
            }
        }
    }

    nonisolated static func data(from url: URL) async throws -> Data {
        if url.isFileURL {
            let task = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                return try Data(contentsOf: url)
            }
            return try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }
}
