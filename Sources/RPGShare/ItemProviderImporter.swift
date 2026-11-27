// @copyright André Trettin

import CoreRPG
import ImageIO
import os.log
import SwiftUI
import Synchronization
import UniformTypeIdentifiers

struct ImageItem: Identifiable, Hashable, Sendable {
    let id = UUID()
    var imageData: Data
    /// A preview at about the size the share sheet shows it, made once here. The sheet used to
    /// decode the stored JPEG (up to 4096 px, about 50 MB of bitmap) in every pass of a cell's
    /// body. See CODE_AUDIT_26 §7.25.
    let preview: CGImage?

    init(imageData: Data) {
        self.imageData = imageData
        preview = CGImageSourceCreateWithData(imageData as CFData, nil).flatMap {
            ImageDownsampler.downsampledImage(from: $0, maxPixelSize: Self.previewPixelSize)
        }
    }

    private static let previewPixelSize: CGFloat = 1_200

    // Identity only: the animation of the list compared the whole image data of every item.
    static func == (lhs: ImageItem, rhs: ImageItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// What loading one kind of shared content produced, and how many shared items could not be used.
struct LoadResult<Value: Sendable>: Sendable {
    var values: [Value] = []
    /// Items that failed to load or were dropped (for example by the payload budget). Shown to the
    /// person instead of being lost silently. See CODE_AUDIT_26 §5.46.
    var skippedCount = 0
}

@MainActor
final class ItemProviderImporter {
    enum Error: Swift.Error {
        case noItems
        case failedToLoad
    }
    
    func loadImages(from items: [NSItemProvider]) async throws -> LoadResult<ImageItem> {
        let permissibleTypes: [UTType] = [.image, .url]
        let providersAndTypes = Self.providersAndTypes(from: items, permissibleTypes: permissibleTypes)

        var result = LoadResult<ImageItem>()
        var totalPayloadSize = 0
        for (index, (provider, type)) in providersAndTypes.enumerated() {
            try Task.checkCancellation()
            // Caps total in-flight payload across multiple shared attachments — the Share
            // Extension's tight (~120MB) memory budget is shared across every image held in
            // `images`, not just the largest one. See CODE_AUDIT §6.3.
            guard totalPayloadSize < Self.maximumTotalImagePayloadSize else {
                logger.warning("\(#function): dropping remaining image(s); total payload budget reached")
                result.skippedCount += providersAndTypes.count - index
                break
            }
            do {
                let image = try await Self.loadImage(provider: provider, type: type)
                totalPayloadSize += image.imageData.count
                result.values.append(image)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                logger.error("\(#function): \(error)")
                result.skippedCount += 1
            }
        }
        return result
    }

    func loadTexts(from items: [NSItemProvider]) async throws -> LoadResult<String> {
        let permissibleTypes: [UTType] = [.text, .plainText]
        let providersAndTypes = Self.providersAndTypes(from: items, permissibleTypes: permissibleTypes)

        var result = LoadResult<String>()
        for (provider, type) in providersAndTypes {
            try Task.checkCancellation()
            do {
                result.values.append(try await Self.loadText(provider: provider, type: type))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                logger.error("\(#function): \(error)")
                result.skippedCount += 1
            }
        }
        return result
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
        // An image is taken as a file first: the provider writes it to disk and it is downsampled
        // from there. Handed over as `Data` or through `loadDataRepresentation`, a 100+ MB original
        // is in memory whole before any check, which kills the extension at ~120 MB.
        // See CODE_AUDIT_26 §7.24.
        if type == .image, let fileUrl = try await copyOfFileRepresentation(provider: provider, type: type) {
            defer { try? FileManager.default.removeItem(at: fileUrl) }
            let data = try await imageData(fromFile: fileUrl)
            try Task.checkCancellation()
            // The preview is decoded off the main actor. See CODE_AUDIT_29 §7.9.
            return try await runOffCallerExecutor { ImageItem(imageData: data) }
        }
        let item = try await loadItem(provider: provider, type: type)
        try Task.checkCancellation()

        if case .data(let data) = item {
            // Checked before anything decodes it; the file path above applies the same cap.
            guard data.count <= maximumSourceFileByteSize else { throw Error.failedToLoad }
            // Off the caller's executor: under approachable concurrency this nonisolated
            // function runs on the caller's actor (the main actor here), and decoding an image
            // above the raw-size cap would hitch the extension's UI. See CODE_AUDIT_Folder §3.12.
            return try await runOffCallerExecutor { ImageItem(imageData: try downsampledIfNeeded(data)) }
        }

        guard case .url(let url) = item else {
            throw Error.noItems
        }

        // Files are downsampled straight from disk and remote images are downloaded to disk
        // first, so an oversized original is never read into memory whole (the extension is
        // killed at ~120 MB). See CODE_AUDIT_15 §7.1.
        let data = try await imageData(from: url)
        try Task.checkCancellation()
        return try await runOffCallerExecutor { ImageItem(imageData: data) }
    }

    /// See `SharedImageDownsampling.downsampledIfNeeded`, where the rules live and are tested.
    nonisolated static func downsampledIfNeeded(_ data: Data) throws -> Data {
        do {
            return try SharedImageDownsampling.downsampledIfNeeded(data)
        } catch {
            throw Error.failedToLoad
        }
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
            return try downsampledIfNeeded(try Data(contentsOf: url))
        }
    }

    nonisolated static func imageData(from url: URL) async throws -> Data {
        if url.isFileURL {
            return try await imageData(fromFile: url)
        }
        // Only a link that names an image file is fetched. A shared web page would otherwise be
        // requested (private hosts, one-shot links) up to the download cap before it is found
        // not to be an image. See CODE_AUDIT_23 §6.6.
        guard UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true else {
            throw Error.failedToLoad
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
        SharedImageDownsampling.downsampled(source)
    }

    nonisolated static let maximumRawImageByteSize = SharedImageDownsampling.maximumRawImageByteSize
    nonisolated static let maximumDownsampledPixelDimension = SharedImageDownsampling.maximumDownsampledPixelDimension
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

    /// A copy of the file the provider writes for `type`, or `nil` when it offers none. The
    /// provider's own file disappears when the handler returns, so it is copied to a temporary
    /// file the caller removes. Cancelling the task cancels the provider's `Progress`.
    nonisolated static func copyOfFileRepresentation(provider: NSItemProvider, type: UTType) async throws -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(type.identifier) else { return nil }
        let progress = Mutex<Progress?>(nil)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL?, any Swift.Error>) in
                let loading = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                    guard let url else {
                        // No file for this type: the caller goes on with the other ways to load it.
                        continuation.resume(returning: nil)
                        _ = error
                        return
                    }
                    let copy = FileManager.default.temporaryDirectory
                        .appending(path: "RPGShare-\(UUID().uuidString)")
                        .appendingPathExtension(url.pathExtension)
                    do {
                        try FileManager.default.copyItem(at: url, to: copy)
                        continuation.resume(returning: copy)
                    } catch {
                        continuation.resume(returning: nil)
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
