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
        let kind = kind
        let sourceFilenameExtension = sourceFilenameExtension
        let conversion = Task.detached(priority: .userInitiated) {
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
        return try await withTaskCancellationHandler {
            try await conversion.value
        } onCancel: {
            conversion.cancel()
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

    /// Per-axis bound on a decoded image's declared pixel dimensions, mirroring
    /// `FoundryImportLimits.maximumUniversalVTTPixelDimension`'s per-axis shape.
    static let maximumDecodedImageDimension = 20_000
    /// A JPEG-quality battle map or portrait tops out in the tens of megapixels; this generously
    /// allows well past that (400 MP, e.g. ~20,000×20,000) while still rejecting a maliciously
    /// small, highly-compressible file that declares an enormous width×height — a
    /// decompression-bomb vector, since `makeJPEG` otherwise allocates a `CGContext` sized
    /// exactly to whatever the (untrusted) header claims, 4 bytes per pixel, before any actual
    /// image data has been validated. See CODE_AUDIT §6.1.
    static let maximumDecodedImagePixelCount = 400_000_000

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
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
           let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue {
            guard width > 0, height > 0,
                  width <= maximumDecodedImageDimension,
                  height <= maximumDecodedImageDimension,
                  width * height <= maximumDecodedImagePixelCount else {
                throw FoundryMediaNormalizationError.invalidImage
            }
        }

        guard let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary),
              sourceImage.width > 0,
              sourceImage.height > 0,
              sourceImage.width <= maximumDecodedImageDimension,
              sourceImage.height <= maximumDecodedImageDimension,
              sourceImage.width * sourceImage.height <= maximumDecodedImagePixelCount else {
            throw FoundryMediaNormalizationError.invalidImage
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: sourceImage.width,
            height: sourceImage.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw FoundryMediaNormalizationError.jpegEncodingFailed
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height))
        context.interpolationQuality = .high
        context.draw(
            sourceImage,
            in: CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height)
        )
        guard let opaqueImage = context.makeImage() else {
            throw FoundryMediaNormalizationError.jpegEncodingFailed
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw FoundryMediaNormalizationError.jpegEncodingFailed
        }
        var properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.9,
        ]
        if let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let orientation = sourceProperties[kCGImagePropertyOrientation] {
            properties[kCGImagePropertyOrientation] = orientation
        }
        CGImageDestinationAddImage(destination, opaqueImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw FoundryMediaNormalizationError.jpegEncodingFailed
        }
        return output as Data
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
