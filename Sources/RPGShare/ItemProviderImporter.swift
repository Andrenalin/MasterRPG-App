// @copyright André Trettin

import CoreRPG
import ImageIO
import os.log
import SwiftUI
import Synchronization
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
            // Off the caller's executor: under approachable concurrency this nonisolated
            // function runs on the caller's actor (the main actor here), and decoding an image
            // above the raw-size cap would hitch the extension's UI. See CODE_AUDIT_Folder §3.12.
            let imageData = try await runOffCallerExecutor { downsampledIfNeeded(data) }
            return ImageItem(imageData: imageData)
        }

        guard case .url(let url) = item else {
            throw Error.noItems
        }

        // Files are downsampled straight from disk and remote images are downloaded to disk
        // first, so an oversized original is never read into memory whole (the extension is
        // killed at ~120 MB). See CODE_AUDIT_15 §7.1.
        let data = try await imageData(from: url)
        try Task.checkCancellation()
        return ImageItem(imageData: data)
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
        return downsampled(source) ?? data
    }

    /// Reads the image at `url` with a bounded memory footprint: a large file is downsampled
    /// from disk by ImageIO, only a small one is read into memory (and then passed through).
    nonisolated static func imageData(fromFile url: URL) async throws -> Data {
        // Structured (CODE_AUDIT_18 §4.4). A file above the raw-image cap is only ever
        // downsampled from disk: if ImageIO can't read it, the import fails instead of
        // falling back to reading up to 256 MB into the extension's ~120 MB memory budget.
        // See CODE_AUDIT_18 §6.4.
        try await runOffCallerExecutor { () throws -> Data in
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= maximumSourceFileByteSize else { throw Error.failedToLoad }
            if size > maximumRawImageByteSize {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let downsampledData = downsampled(source) else {
                    throw Error.failedToLoad
                }
                return downsampledData
            }
            return downsampledIfNeeded(try Data(contentsOf: url))
        }
    }

    nonisolated static func imageData(from url: URL) async throws -> Data {
        if url.isFileURL {
            return try await imageData(fromFile: url)
        }
        // A shared web page URL is not an image: download to disk (not memory), capped while it
        // downloads and with checked redirects, then require an image content type before
        // decoding anything. The user shared this URL, so private hosts stay allowed, as for
        // text. See CODE_AUDIT_18 §6.4, CODE_AUDIT_19 §6.2.
        let (downloadedUrl, response) = try await GuardedRemoteDownload.downloadWithResponse(
            from: url,
            maximumBytes: maximumSourceFileByteSize,
            allowsPrivateHosts: true
        )
        defer { try? FileManager.default.removeItem(at: downloadedUrl) }
        guard response.mimeType?.hasPrefix("image/") == true else { throw Error.failedToLoad }
        return try await imageData(fromFile: downloadedUrl)
    }

    private nonisolated static func downsampled(_ source: CGImageSource) -> Data? {
        // The header is checked before anything is decoded: an image declaring more pixels than
        // the shared limit is not decoded inside the extension's memory budget at all.
        // See CODE_AUDIT_21 §9.5.
        guard ImageDownsampler.declaredSize(of: source) != .overLimits,
              let thumbnail = ImageDownsampler.downsampledImage(
                  from: source,
                  maxPixelSize: maximumDownsampledPixelDimension
              ) else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(
            destination,
            thumbnail,
            [kCGImageDestinationLossyCompressionQuality: JPEGQuality.downsampledImport] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return output as Data
    }

    nonisolated static let maximumRawImageByteSize = 8 * ByteUnit.mebibyte
    nonisolated static let maximumDownsampledPixelDimension: CGFloat = 4_096
    nonisolated static let maximumTotalImagePayloadSize = 60 * ByteUnit.mebibyte
    /// Largest image file (or download) the extension will even open.
    nonisolated static let maximumSourceFileByteSize = ByteLimits.maximumSourceFileBytes
    /// Text shared into an entry is small; anything larger is not text worth loading.
    nonisolated static let maximumTextByteSize = 5 * ByteUnit.mebibyte

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
        // The SDK's async overload instead of a hand-written continuation. See CODE_AUDIT_18 §4.3.
        let item = try await provider.loadItem(forTypeIdentifier: type.identifier)
        if let data = item as? Data {
            return .data(data)
        } else if let data = item as? NSData {
            return .data(data as Data)
        } else if let text = item as? String {
            return .text(text)
        } else if let text = item as? NSString {
            return .text(text as String)
        } else if let url = item as? URL {
            return .url(url)
        }
        // Anything else is an object of the host app, an image object for example. The provider
        // can still give the type's data; this used to end in `noItems` and the share showed
        // no photo. See CODE_AUDIT_21 §5.27.
        return .data(try await loadDataRepresentation(provider: provider, type: type))
    }

    /// The provider's data for `type`. `NSItemProvider` offers this only with a completion
    /// handler (it returns a `Progress`), so there is no async variant to call.
    /// Cancelling the task cancels the provider's `Progress`, which ends the load with an error,
    /// instead of leaving a large item loading for a share that was dismissed.
    nonisolated static func loadDataRepresentation(provider: NSItemProvider, type: UTType) async throws -> Data {
        let progress = Mutex<Progress?>(nil)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let loading = provider.loadDataRepresentation(for: type) { data, error in
                    if let data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: error ?? Error.noItems)
                    }
                }
                let cancelled = progress.withLock { stored in
                    stored = loading
                    return Task.isCancelled
                }
                if cancelled { loading.cancel() }
            }
        } onCancel: {
            progress.withLock { $0 }?.cancel()
        }
    }

    nonisolated static func data(from url: URL) async throws -> Data {
        if url.isFileURL {
            return try await runOffCallerExecutor { () throws -> Data in
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= maximumTextByteSize else { throw Error.failedToLoad }
                return try Data(contentsOf: url)
            }
        }

        // Capped while downloading (the user shared this URL, so private hosts stay allowed).
        // See CODE_AUDIT_18 §6.4.
        let downloadedUrl = try await GuardedRemoteDownload.download(
            from: url,
            maximumBytes: maximumTextByteSize,
            allowsPrivateHosts: true
        )
        defer { try? FileManager.default.removeItem(at: downloadedUrl) }
        let size = try downloadedUrl.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maximumTextByteSize else { throw Error.failedToLoad }
        return try Data(contentsOf: downloadedUrl)
    }
}
