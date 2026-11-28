// @copyright André Trettin

import CoreRPG
import Foundation
import ImageIO
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The shared `GenericEditController`; the photo behaviour below needs no stored state of its
/// own. See CODE_AUDIT_Folder §9.3.
typealias EditController = GenericEditController<PhotoModel>

extension EditController {
    var cacheController: CacheController? { itemControllable.cacheControllable as? CacheController }
}

extension EditController {
    /// - Parameter forceSave: `true` from the editor, which persists also during a game.
    @MainActor func convert(itemId: UUID, forceSave: Bool = false) async throws {
        guard let item = editModel(for: itemId), let fileUrl = item.fileUrl else { return }
        // The original file is re-encoded off the main actor and at its own size. The cached image
        // is decoded at 8192 px at most, so converting from it permanently downscaled a bigger
        // photo, and the encode ran on the main actor. See CODE_AUDIT_26 §7.18.
        var data = await originalAsJPEG(fileUrl)
        if data == nil {
            // An image the original path refuses (over the declared-size limits, or a format
            // ImageIO cannot write): the capped cache image, as before.
            await cacheController?.photoId(for: item.id, item: item, shouldDownload: true)
            if let image = await cacheController?.photo(for: item.id) {
                data = await Self.encodedJPEG(image)
            }
        }
        guard let data else { return }

        var dataUrl = fileUrl
        dataUrl.convertFile(data, fileExtension: itemControllable.config.filenameExtension)

        let newFileUrl = try await fileUrlDataController?.createNewFileUrl(fileId: item.id, unconvertedFileUrl: dataUrl, pathExtension: itemControllable.config.filenameExtension)
        await itemControllable.cacheControllable?.remove(itemId: itemId)
        reset(fileUrl: newFileUrl, itemId: item.id, forceSave: forceSave)
    }
    
    /// The JPEG of the file `fileUrl` names, written from the original bitmap by ImageIO (the
    /// orientation and metadata travel with it), after the file is downloaded. `nil` when the file
    /// cannot be read or its declared size is over the limits.
    @MainActor private func originalAsJPEG(_ fileUrl: FileUrl) async -> Data? {
        guard let fileUrlDataController else { return nil }
        if await fileUrlDataController.hasAccess(for: fileUrl) == false {
            try? await fileUrlDataController.download(fileUrl: fileUrl)
        }
        return await fileUrlDataController.resolvedImage(
            for: fileUrl,
            decodeData: { data in
                CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
                    .flatMap(Self.jpegData(from:))
            },
            decodeUrl: { url in
                CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
                    .flatMap(Self.jpegData(from:))
            }
        )
    }

    private static func jpegData(from source: CGImageSource) -> Data? {
        guard case .withinLimits = ImageDownsampler.declaredSize(of: source) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImageFromSource(
            destination,
            source,
            0,
            [kCGImageDestinationLossyCompressionQuality: JPEGQuality.export] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    @MainActor func isNotJpegPhoto(itemId: UUID) -> Bool {
        guard let item = editModel(for: itemId) else { return false }
        guard let fileUrl = item.fileUrl else { return false }
        // Case-insensitive: "IMG.JPG" is a JPEG too. See CODE_AUDIT_26 §5.120.
        let fileExtension = (fileUrl.fileExtension ?? "").lowercased()
        let jpegExtensions: Set = [itemControllable.config.filenameExtension.lowercased(), "jpg", "jpeg", "jpe"]
        return !jpegExtensions.contains(fileExtension)
    }

    func loadImage(cacheType: CacheItemListModel.CacheType, item: Model, itemId: UUID, fileUrl: FileUrl?, reset: Bool = false) async -> AKImage? {
        guard let cacheController, fileUrl != nil else { return nil }
        if reset {
            await cacheController.setCachedImage(nil, for: itemId)
            await cacheController.setCachedThumbnail(nil, for: itemId)
        }
        if let newImage = cacheType == .image ? await cacheController.cachedImage(for: itemId) : await cacheController.cachedThumbnail(for: itemId) {
            return newImage
        }
        var result: AKImage? = nil
        if cacheType == .image {
            await cacheController.photoId(for: itemId, item: item, shouldDownload: true)
            result = await cacheController.photo(for: itemId)
            
            await cacheController.setCachedImage(result, for: itemId)
        }
        await cacheController.thumbnailId(for: itemId, item: item)
        let newThumbnail = await cacheController.thumbnail(for: itemId)
        // Full-resolution detail loading must not clear a list thumbnail when a
        // thumbnail refresh is temporarily unavailable or the task is cancelled.
        if let newThumbnail {
            await cacheController.setCachedThumbnail(newThumbnail, for: itemId)
        }
        return cacheType == .image ? result : newThumbnail
    }
        
    func resetPhoto(image: AKImage?, itemId: UUID, replaced: ReplacedFileDisposal = .delete) async throws {
#if os(macOS)
        let data = image?.jpegData(compressionQuality: JPEGQuality.export)
#else
        // Encoded off the main actor: a 48 MP camera photo hitched the UI.
        // See CODE_AUDIT_21 §7.10.
        let data = await Self.encodedJPEG(image)
#endif
        // The editor stores the photo on the library item also during a game: the replaced file
        // is deleted. See CODE_AUDIT_26 §5.1.
        try await resetFile(data: data, itemId: itemId, path: "", replaced: replaced, forceSave: true)
    }

    /// Stores the picked or dropped image `data` as the item's photo. Returns `false` when the
    /// data is no image. Decoding and encoding run off the main actor, and the image is decoded
    /// at most at the size the app shows images at; the library and drop paths used to decode
    /// and re-encode at full resolution on the main actor. See CODE_AUDIT_21 §7.10.
    func resetPhoto(data: Data, itemId: UUID, replaced: ReplacedFileDisposal = .delete, forceSave: Bool = true) async throws -> Bool {
        guard let jpeg = await Self.importedJPEG(from: data) else { return false }
        try await resetFile(data: jpeg, itemId: itemId, path: "", replaced: replaced, forceSave: forceSave)
        return true
    }

    /// At Default priority, where ImageIO's own workers run (`runAtDefaultPriority`).
    @concurrent
    private static func importedJPEG(from data: Data) async -> Data? {
        await runAtDefaultPriority {
            AKImage.decodedImage(from: data)?
                .jpegData(compressionQuality: JPEGQuality.export)
        }
    }

    @concurrent
    private static func encodedJPEG(_ image: AKImage?) async -> Data? {
        image?.jpegData(compressionQuality: JPEGQuality.export)
    }
}

// MARK: - Apply a photo analysis to a PhotoModel

#if !os(tvOS)
import GeneratorRPG

/// Which values of a photo analysis the person wants to keep.
struct PhotoPropertySelection {
    var applyTitle = true
    var applyDescription = true
    var applyTags = true

    var hasAnySelected: Bool {
        applyTitle || applyDescription || applyTags
    }
}

extension EditController {
    /// - Parameter forceSave: `true` from the editor, which persists also during a game.
    @MainActor func applyAnalysis(_ analysis: PhotoSummaryAnalysis, to itemId: UUID, selection: PhotoPropertySelection, forceSave: Bool = false) {
        if selection.applyTitle {
            reset(name: analysis.title, itemId: itemId, forceSave: forceSave)
        }
        if selection.applyDescription {
            reset(description: analysis.summary, itemId: itemId, forceSave: forceSave)
        }
        if selection.applyTags {
            reset(tags: analysis.tags, itemId: itemId, forceSave: forceSave)
        }
    }
}
#endif
