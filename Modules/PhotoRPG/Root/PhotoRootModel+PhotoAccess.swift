// @copyright André Trettin

import CoreRPG
import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Photo-access API surface (thumbnail/image fetch, list, cleanup, repair) — extracted
/// from PhotoRootModel.swift's own constructor/property-declaration bulk. See CODE_AUDIT §9.10.
public extension PhotoRootModel {
    /// Lightweight source for callers that only need a small preview (e.g. a Map
    /// room-crop thumbnail) — decodes a downsampled image via ImageIO instead of the
    /// full-resolution decode that `fetchPhotoImage` performs, and reports the scale
    /// to map rects defined in the original image's pixel space.
    @MainActor
    func fetchPhotoThumbnailSource(for id: UUID?, maxPixelSize: CGFloat) async -> (image: AKImage, scale: CGFloat, degrees: Double)? {
        guard let id, let item = await itemController.item(for: id), let fileUrl = item.fileUrl,
              let fileUrlDataController else { return nil }
        if !fileUrl.hasUnconvertedData, await !fileUrlDataController.isAvailableWithoutDownloading(fileUrl) {
            return nil
        }
        guard let result = await fileUrlDataController.resolvedImage(
            for: fileUrl,
            decodeData: { AKImage.downsampledThumbnailWithScale(from: $0, maxPixelSize: maxPixelSize) },
            decodeUrl: { AKImage.downsampledThumbnailWithScale(from: $0, maxPixelSize: maxPixelSize) }
        ) else { return nil }
        return (result.image, result.scale, item.degrees)
    }

    @MainActor
    func fetchPhotoImage(for id: UUID?, useGame: Bool) async -> (AKImage, Double)? {
        guard let id else { return nil }
        let model = useGame ? gameController.gameItem(for: id) : itemController.itemOrEmpty(for: id)

        // Await `loadImage` directly instead of wrapping it in an unstructured `Task`:
        // an unstructured `Task` isn't cancelled when this function's own task is
        // (e.g. a `.task(id:)` cancelling on rapid photo navigation), so it would keep
        // decoding/downloading in the background after the caller stopped caring. See
        // CODE_AUDIT §3.1.
        guard let image = await editController.loadImage(cacheType: .image, item: model, itemId: model.id, fileUrl: model.fileUrl) else { return nil }
        return (image, model.degrees)
    }

    /// The size and rotation `fetchPhotoImage` would report, for callers that only measure the
    /// photo (e.g. the map repair, which runs for every map). The size comes from the file header,
    /// so no photo is decoded; a photo that is not downloaded, has no readable header or exceeds the
    /// decode bound goes through `fetchPhotoImage`.
    @MainActor
    func fetchPhotoGeometry(for id: UUID?, useGame: Bool) async -> (size: CGSize, degrees: Double)? {
        guard let id else { return nil }
        let model = useGame ? gameController.gameItem(for: id) : itemController.itemOrEmpty(for: id)
        if let fileUrl = model.fileUrl, let fileUrlDataController,
           await fileUrlDataController.isAvailableWithoutDownloading(fileUrl),
           let size = await fileUrlDataController.resolvedImage(
               for: fileUrl,
               decodeData: { AKImage.boundedDecodedSize(from: $0) },
               decodeUrl: { AKImage.boundedDecodedSize(from: $0) }
           ) {
            return (size, model.degrees)
        }
        guard let (image, degrees) = await fetchPhotoImage(for: id, useGame: useGame) else { return nil }
        return (image.size, degrees)
    }

    func itemDataCleanup() async throws {
        for itemId in itemController.itemDataModel.items {
            guard let model = await itemController.item(for: itemId) else { continue }
            if model.displayState == DisplayStateMask.totalHidden.rawValue {
                await editController.delete(itemId: model.id)
            }
        }
    }

    func checkFolders(reportModel: ValidateRepairModel) async {
        let cc = ConvertController(itemController: itemController, editController: editController)
        await cc.repairHiddenAndFolders(reportModel: reportModel)
    }

    func validateLinks(reportModel: ValidateRepairModel) async {
        await linkController.validateLinks(reportModel: reportModel)
    }
}
