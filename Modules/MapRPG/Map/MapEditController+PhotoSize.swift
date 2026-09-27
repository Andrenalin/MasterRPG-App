// @copyright André Trettin

import CoreGraphics
import CoreRPG
import Foundation

// Split out of MapEditController.swift — see CODE_AUDIT §9.13.

extension MapEditController {
    /// True when the loaded photo's own pixel size — corrected for the orientation the map
    /// was actually authored against — disagrees with the map's persisted `width`/`height`
    /// by more than the map/photo aspect-ratio tolerance `MapCanvasGeometryResolver` uses.
    /// Surfaces the "Fix Map Size" button only when there's something to fix.
    @MainActor
    func isMapSizeOutOfSyncWithPhoto(editorModel: MapEditorSession) -> Bool {
        guard let copy = editorModel.workingCopy, copy.photoId != nil else { return false }
        let mapSize = CGSize(width: copy.width, height: copy.height)
        return MapEditController.realPhotoSize(matching: mapSize, photoSize: editorModel.image.fixedSize) != mapSize
    }

    /// Resizes the map's canvas to the photo's real size and rescales every room, pin, wall,
    /// the pointer and the tile crop to match — reusing `MapModel.resetImage`, the same
    /// resize-and-remap primitive an ordinary photo replacement already goes through.
    ///
    /// On macOS, a photo whose file predates a since-fixed import bug can report a raw,
    /// un-rotated pixel size (`AKImage.fixedSize`) that disagrees with how it actually
    /// displays — while iOS measures the same file correctly, so this affects macOS maps
    /// only. The displayed photo and the map's own aspect ratio are the reliable signal:
    /// `realPhotoSize` swaps width/height only when doing so makes the photo's aspect ratio
    /// agree with the map's, i.e. the same test `MapCanvasGeometryResolver` already uses.
    @MainActor
    @discardableResult
    func fixMapSizeToPhoto(editorModel: MapEditorSession) -> Bool {
        guard let copy = editorModel.workingCopy, let photoId = copy.photoId else { return false }
        synchronizeWorkingCopy(editorModel: editorModel)

        let oldCanvasSize = CGSize(width: copy.width, height: copy.height)
        let realSize = MapEditController.realPhotoSize(matching: oldCanvasSize, photoSize: editorModel.image.fixedSize)
        copy.resetImage(with: photoId, size: realSize, degrees: editorModel.photoDegrees)
        guard CGSize(width: copy.width, height: copy.height) != oldCanvasSize else { return false }

        let rescaledActive = editorModel.editEntries.entries.map { copy[$0.id] }
        editorModel.editEntries.resetEntries(mapId: copy.id, entries: rescaledActive)
        editorModel.pins.mapPins = copy.mapPins
        syncDisplayEntries(from: copy, editorModel: editorModel)
        editorModel.updateCanvas(map: copy, image: editorModel.image, photoDegrees: editorModel.photoDegrees)

        return recordMutation(
            String(localized: "Fix map size to photo", bundle: .module),
            editorModel: editorModel
        )
    }

    /// `photoSize`, or its width/height swapped, whichever aspect ratio is closer to
    /// `mapSize`'s — the same aspect-agreement test `MapCanvasGeometryResolver.resolve`
    /// applies when deciding whether a map's stored size still matches its photo.
    static func realPhotoSize(matching mapSize: CGSize, photoSize: CGSize) -> CGSize {
        guard mapSize.isFiniteAndPositive, photoSize.isFiniteAndPositive else { return photoSize }
        let swapped = CGSize(width: photoSize.height, height: photoSize.width)
        let mapAspectRatio = mapSize.width / mapSize.height
        let directError = abs(log(mapAspectRatio / (photoSize.width / photoSize.height)))
        let swappedError = abs(log(mapAspectRatio / (swapped.width / swapped.height)))
        return swappedError < directError ? swapped : photoSize
    }
}
