// @copyright André Trettin

import AVFoundation
import CoreRPG
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Describes the only media representations that can be installed by a Foundry import.
///
/// Planning is synchronous so callers can publish the final filename and content type during
/// review without loading the resource. Conversion remains lazy and runs when the attachment is
/// committed.
struct FoundryMediaNormalizationPlan: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case image
        case audio
    }

    let kind: Kind
    let suggestedFilename: String
    let contentTypeIdentifier: String

    fileprivate let sourceFilenameExtension: String

    func normalize(_ data: Data) async throws -> Data {
        try await Self.convert(data, kind: kind, sourceFilenameExtension: sourceFilenameExtension)
    }

    /// Off the caller's executor and structured, so cancellation propagates without a
    /// detached task and handler. See CODE_AUDIT_18 §4.4.
    @concurrent
    private static func convert(_ data: Data, kind: Kind, sourceFilenameExtension: String) async throws -> Data {
        try Task.checkCancellation()
        switch kind {
        case .image:
            return try FoundryMediaNormalizer.makeJPEG(from: data)
        case .audio:
            return try await FoundryMediaNormalizer.makeMPEG4Audio(
                from: data,
                sourceFilenameExtension: sourceFilenameExtension
            )
        }
    }
}

enum FoundryMediaNormalizationError: Error, Equatable, LocalizedError, Sendable {
    case invalidImage
    case vectorImage
    case jpegEncodingFailed
    case audioExportUnavailable
    case invalidAudio
    case emptyAudioOutput

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "The Foundry image could not be decoded as a supported raster image."
        case .vectorImage:
            "Vector images cannot be imported as RPG media."
        case .jpegEncodingFailed:
            "The Foundry image could not be converted to JPEG."
        case .audioExportUnavailable:
            "The Foundry audio format cannot be converted to MPEG-4 audio on this device."
        case .invalidAudio:
            "The Foundry audio could not be converted to MPEG-4 audio."
        case .emptyAudioOutput:
            "The converted Foundry audio is empty."
        }
    }
}

enum FoundryMediaNormalizer {
    /// Returns `nil` for vector and unsupported media, preventing those resources from being
    /// represented as importable PhotoRPG or AudioRPG items.
    static func plan(
        for sourcePath: String,
        expectedKind: FoundryMediaNormalizationPlan.Kind? = nil
    ) -> FoundryMediaNormalizationPlan? {
        let canonicalPath = canonicalPath(sourcePath)
        let sourceURL = URL(filePath: canonicalPath)
        let filenameExtension = sourceURL.pathExtension.lowercased()
        let stem = sourceURL.deletingPathExtension().lastPathComponent

        if rasterImageFilenameExtensions.contains(filenameExtension) {
            return FoundryMediaNormalizationPlan(
                kind: .image,
                suggestedFilename: normalizedFilename(stem: stem, fallback: "image", extension: "jpg"),
                contentTypeIdentifier: UTType.jpeg.identifier,
                sourceFilenameExtension: filenameExtension
            )
        }
        if audioFilenameExtensions.contains(filenameExtension)
            || (
                expectedKind == .audio
                    && contextDependentAudioFilenameExtensions.contains(filenameExtension)
            ) {
            return FoundryMediaNormalizationPlan(
                kind: .audio,
                suggestedFilename: normalizedFilename(stem: stem, fallback: "audio", extension: "m4a"),
                contentTypeIdentifier: UTType.mpeg4Audio.identifier,
                sourceFilenameExtension: filenameExtension
            )
        }
        return nil
    }
}

private extension FoundryMediaNormalizer {
    static let rasterImageFilenameExtensions: Set<String> = [
        "apng", "avif", "bmp", "gif", "heic", "heif", "jpeg", "jpg", "png", "tif", "tiff",
        "webp",
    ]

    static let audioFilenameExtensions: Set<String> = [
        "aac", "aif", "aiff", "caf", "flac", "m4a", "mp3", "oga", "ogg", "opus", "wav",
    ]

    /// Foundry can use these containers for either audio or video. They are only accepted when
    /// the reference comes from an explicitly audio-scoped document such as a PlaylistSound.
    static let contextDependentAudioFilenameExtensions: Set<String> = ["mp4", "webm"]

    /// Per-axis bound on an image's declared pixel dimensions, checked from the header before
    /// anything is decoded.
    static let maximumDecodedImageDimension = 16_384
    /// Bound on the declared pixel count. The image is decoded downsampled (see
    /// `maximumOutputPixelSize`), but a decoder that cannot downsample while decoding may still
    /// need the full bitmap once: 150 MP is about 600 MB. 400 MP allowed a small, highly
    /// compressible file to claim 1.6 GB, twice (decode and redraw), which killed the app during
    /// the commit and bypassed its rollback. See CODE_AUDIT §6.1, CODE_AUDIT_Folder §6.4.
    static let maximumDecodedImagePixelCount = 150_000_000
    /// Longest edge of the stored JPEG: the size the app decodes images at anyway.
    static var maximumOutputPixelSize: CGFloat { AKImage.maximumDecodedPixelSize }

    static func canonicalPath(_ path: String) -> String {
        let decoded = path.removingPercentEncoding ?? path
        let withoutQuery = decoded.split(separator: "?", maxSplits: 1).first.map(String.init) ?? decoded
        return withoutQuery.split(separator: "#", maxSplits: 1).first.map(String.init) ?? withoutQuery
    }

    static func normalizedFilename(stem: String, fallback: String, extension: String) -> String {
        let decodedStem = FoundryTextDecoder.decodedText(stem)
        let visibleStem = decodedStem.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0)
        }
        let trimmedStem = String(String.UnicodeScalarView(visibleStem))
            .replacing("/", with: "-")
            .replacing("\\", with: "-")
            .replacing(":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let safeStem = trimmedStem.isEmpty || trimmedStem == "." || trimmedStem == ".."
            ? fallback
            : trimmedStem
        return "\(safeStem).\(`extension`)"
    }

    static func makeJPEG(from data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary) else {
            throw FoundryMediaNormalizationError.invalidImage
        }
        if let sourceType = CGImageSourceGetType(source),
           let uniformType = UTType(sourceType as String),
           uniformType.conforms(to: .svg) {
            throw FoundryMediaNormalizationError.vectorImage
        }
        guard CGImageSourceGetCount(source) > 0 else {
            throw FoundryMediaNormalizationError.invalidImage
        }

        // Read the declared dimensions from the header before decoding — the actual
        // decompression bomb this guards against never gets the chance to allocate.
        guard let headerProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (headerProperties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (headerProperties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0,
              width <= maximumDecodedImageDimension,
              height <= maximumDecodedImageDimension,
              width * height <= maximumDecodedImagePixelCount else {
            throw FoundryMediaNormalizationError.invalidImage
        }

        // Decoded downsampled by ImageIO, never above the size the app displays, with the
        // orientation applied. The full-size decode plus a full-size redraw needed two bitmaps of
        // the declared size. See CODE_AUDIT_Folder §6.4.
        let longestEdge = CGFloat(max(width, height))
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: min(longestEdge, maximumOutputPixelSize),
            ] as CFDictionary),
              decoded.width > 0,
              decoded.height > 0 else {
            throw FoundryMediaNormalizationError.invalidImage
        }

        let opaqueImage = try hasAlpha(decoded) ? flattenedOnWhite(decoded) : decoded

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw FoundryMediaNormalizationError.jpegEncodingFailed
        }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: JPEGQuality.export,
        ]
        CGImageDestinationAddImage(destination, opaqueImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw FoundryMediaNormalizationError.jpegEncodingFailed
        }
        return output as Data
    }

    static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }

    /// JPEG has no transparency: transparent areas become white instead of black.
    static func flattenedOnWhite(_ image: CGImage) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw FoundryMediaNormalizationError.jpegEncodingFailed
        }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(bounds)
        context.interpolationQuality = .high
        context.draw(image, in: bounds)
        guard let flattened = context.makeImage() else {
            throw FoundryMediaNormalizationError.jpegEncodingFailed
        }
        return flattened
    }

    static func makeMPEG4Audio(
        from data: Data,
        sourceFilenameExtension: String
    ) async throws -> Data {
        let workspace = URL.temporaryDirectory.appending(
            path: "MasterRPG-FoundryMedia-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: workspace,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sourceURL = workspace
            .appending(path: "source")
            .appendingPathExtension(sourceFilenameExtension)
        let outputURL = workspace
            .appending(path: "normalized")
            .appendingPathExtension("m4a")
        try data.write(to: sourceURL, options: .atomic)
        try Task.checkCancellation()

        let asset = AVURLAsset(url: sourceURL)
        guard let exporter = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw FoundryMediaNormalizationError.audioExportUnavailable
        }
        do {
            try await exporter.export(to: outputURL, as: .m4a)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw FoundryMediaNormalizationError.invalidAudio
        }
        try Task.checkCancellation()
        let output = try Data(contentsOf: outputURL)
        guard !output.isEmpty else {
            throw FoundryMediaNormalizationError.emptyAudioOutput
        }
        return output
    }
}
