// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

@MainActor @Observable
final class MapEditorModel {
    // MARK: - View State

    var imageModel: ImageViewerModel
    var pins: MapPinViewModel
    var entries: MapEntryViewerModel
    var editEntries: MapEntryViewerModel
    var focusId: MapEntryModel.ID?
    var appeared = false

    // Working copy of MapModel — owned here, mutated by MapEditController
    var workingCopy: MapModel?
    var undoDepthAtOpen: Int = 0

    enum DraggingType: Hashable {
        case nothing
        case image
    }

    var isDragging: DraggingType = .nothing
    var isTapping: DraggingType = .nothing

    // MARK: - Dependencies

    private let image: AKImage
    private let photoDegrees: Double
    private var containerSize: CGSize

    // MARK: - Initialization

    init(map: MapModel, image: AKImage, photoDegrees: Double, containerSize: CGSize) {
        self.image = image
        self.photoDegrees = photoDegrees
        self.containerSize = containerSize

        self.imageModel = ImageViewerModel(offset: .zero, scale: 1)
        self.pins = MapPinViewModel(mapPins: map.mapPins, pointer: .empty)
        self.entries = MapEntryViewerModel(mapId: map.id, entries: [])
        self.editEntries = MapEntryViewerModel(mapId: map.id, entries: [])
    }

    // MARK: - Container Size Updates

    func updateContainerSize(_ newSize: CGSize) {
        containerSize = newSize
        resetZoom()
    }

    // MARK: - Pins Management

    func resetPlayerAndPins(newPins: [MapPinModel], map: MapModel, pinScale: CGFloat) {
        var modified = newPins
        if let entry = map.entries.first {
            var leftCenter = CGPoint(
                x: entry.xOffset + entry.size.width / 4,
                y: entry.yOffset + entry.size.height / 2
            )
            modified = newPins.map { pin in
                var changedPin = pin
                if changedPin.location == .zero {
                    changedPin.location = leftCenter
                    leftCenter = leftCenter + changedPin.size.size.width * pinScale + 5
                }
                return changedPin
            }
        }

        guard pins.mapPins != modified else { return }
        withAnimation(.bouncy) {
            pins.mapPins = modified
        }
    }

    // MARK: - Entries Management

    func resetEntries(newEntries: [MapEntryModel], map: MapModel) {
        // Update edit entry if it exists and has changed
        if let editEntry = editEntries.entries.first,
           let index = newEntries.firstIndex(where: { $0.id == editEntry.id }),
           editEntry != newEntries[index] {
            withAnimation(.bouncy) {
                editEntries.resetEntries(mapId: map.id, entries: [newEntries[index]])
            }
        }

        guard entries.entries != newEntries else { return }

        withAnimation(.bouncy) {
            entries.resetEntries(mapId: map.id, entries: newEntries)
        }

        // Update focus if needed
        let focus = newEntries.first(where: { $0.focused })?.id
        if focus != focusId {
            focusId = focus
            focusedMap()
        }
    }

    // MARK: - Change Management (view state only — no save)

    func changeImage(map: MapModel, hexScale: inout Double, pinScale: inout CGFloat) {
        hexScale = map.hexMapScale
        pinScale = map.pinScale

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            self.changeMap(map: map)
        }
    }

    func changeMap(map: MapModel) {
        isDragging = .nothing
        isTapping = .nothing
        editEntries.eaten = false
        editEntries.addedNewNeedlePoint = nil

        if appeared {
            resetZoom()
        }
    }

    // MARK: - First Appear

    func firstAppear(map: MapModel) {
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            await MainActor.run {
                appeared = true
                resetEntries(newEntries: map.entries, map: map)
                withAnimation {
                    if focusId == nil {
                        resetZoom()
                    } else {
                        focusedMap()
                    }
                }
            }
        }
    }

    // MARK: - Zooming

    func resetZoom() {
        let (newScale, newOffset) = MapEditorGeometry.zoomToFit(
            containerSize: containerSize,
            image: image,
            degrees: photoDegrees
        )
        imageModel.normScale = newScale
        zoom(scale: newScale, at: newOffset)
    }

    func zooming(on location: CGPoint) {
        let (newScale, newOffset): (CGFloat, CGPoint)
        if imageModel.scale != imageModel.normScale {
            (newScale, newOffset) = MapEditorGeometry.zoomToFit(
                containerSize: containerSize,
                image: image,
                degrees: photoDegrees
            )
        } else {
            (newScale, newOffset) = zoomIn(at: location)
        }
        zoom(scale: newScale, at: newOffset)
    }

    func zoom(scale: CGFloat, at offset: CGPoint) {
        withAnimation {
            imageModel.scale = scale
            imageModel.lastScale = imageModel.scale
            imageModel.offset = offset
            imageModel.lastOffset = imageModel.offset
        }
    }

    func zoomIn(at point: CGPoint) -> (CGFloat, CGPoint) {
        let newScale = max(0.1, imageModel.scale * 4)
        let offPoint = (point - imageModel.offset) / imageModel.scale

        updateScale(newScale, updateLast: false)

        let pswidth = (containerSize.width / newScale) / 2
        let psHeight = (containerSize.height / newScale) / 2
        let offset = CGPoint(
            x: -1 * (offPoint.x - pswidth) * imageModel.scale,
            y: -1 * (offPoint.y - psHeight) * imageModel.scale
        )
        return (newScale, offset)
    }

    func focusedMap() {
        guard let focusId else {
            zooming(on: .zero)
            return
        }

        guard let focusMap = entries.entries.first(where: { $0.id == focusId }) else {
            zooming(on: .zero)
            return
        }

        let ss = focusMap.size
        let sw = containerSize.width / (ss.width + 50)
        let sh = containerSize.height / (ss.height + 50)
        let newScale = min(sw, sh)

        withAnimation {
            imageModel.scale = max(0.1, newScale)
            imageModel.lastScale = imageModel.scale
            imageModel.offset = CGPoint(
                x: -1 * (focusMap.xOffset - 25) * imageModel.scale,
                y: -1 * (focusMap.yOffset - 25) * imageModel.scale
            )
            imageModel.lastOffset = imageModel.offset
        }
    }

    // MARK: - Gesture: Scale

    func updateScale(_ value: CGFloat, updateLast: Bool) {
        if updateLast {
            imageModel.lastScale = value
        }

        let delta = value / imageModel.lastScale
        let newScale = imageModel.scale * delta

        guard newScale >= 0.1 else { return }

        let imgSize = MapEditorGeometry.imageSize(image, degrees: photoDegrees)
        let scaleDiff = (newScale - imageModel.scale) / 2
        let imgOff = imgSize * scaleDiff
        let newOffsetNew = CGPoint(x: -imgOff.width, y: -imgOff.height)

        imageModel.lastScale = value
        imageModel.scale = newScale
        updateOffset(with: newOffsetNew, firstOffset: imageModel.offset)
    }

    // MARK: - Gesture: Drag

    func dragPoint(location: CGPoint) -> DraggingType {
        .image
    }

    func updateOffset(with newLocation: CGPoint, firstOffset: CGPoint) {
        let imgSize = MapEditorGeometry.imageSize(image, degrees: photoDegrees)
        let offX = max(300, (containerSize.width - imgSize.width * imageModel.scale) / 2)
        let offY = max(300, (containerSize.height - imgSize.height * imageModel.scale) / 2)
        let minX = containerSize.width - (imgSize.width * imageModel.scale) - offX
        let minY = containerSize.height - (imgSize.height * imageModel.scale) - offX

        var newOffset = firstOffset + newLocation
        newOffset.x = min(max(newOffset.x, minX), offX)
        newOffset.y = min(max(newOffset.y, minY), offY)

        imageModel.lastOffset = firstOffset
        imageModel.offset = newOffset
    }

    // MARK: - Gesture: Double Tap

    func onDoubleTapped(with location: CGPoint) {
        if editEntries.eaten {
            editEntries.eaten = false
            isTapping = .nothing
        } else {
            zooming(on: location)
        }
    }

    // MARK: - Gesture Handlers

    func pressAction(_ value: DragGesture.Value) {
        isTapping = dragPoint(location: value.location)
    }

    func dragStartAction(_ value: DragGesture.Value) {
        isDragging = dragPoint(location: value.startLocation)
        isTapping = .nothing
        imageModel.lastOffset = imageModel.offset
    }

    func dragAction(_ value: DragGesture.Value) {
        switch isDragging {
        case .image:
            updateOffset(
                with: value.location - value.startLocation,
                firstOffset: imageModel.lastOffset
            )
        case .nothing:
            break
        }
    }

    func dragEndAction() {}

    func endAction() {
        isDragging = .nothing
        isTapping = .nothing
    }

    // MARK: - Helper Methods

    func entry(for location: CGPoint, in map: MapModel) -> MapEntryModel? {
        entries.entries.last { entry in
            let path = subPath(for: entry)
            return path.contains(location)
        }
    }

    func subPath(for entry: MapEntryModel) -> Path {
        Path { path in
            guard let firstPoint = entry.coordinates.first else { return }
            path.move(to: firstPoint)
            for point in entry.coordinates[1...] {
                path.addLine(to: point)
            }
            path.addLine(to: firstPoint)
            if entry.coordinates.count >= 2 {
                let secondPoint = entry.coordinates[1]
                path.addLine(to: secondPoint)
            }
        }
    }

    // MARK: - Computed Properties

    var currentSize: CGSize {
        MapEditorGeometry.imageSize(image, degrees: photoDegrees) * imageModel.scale
    }

    func imageOffset() -> CGSize {
        guard let location = editEntries.selectedNeedleCoordinate else { return .zero }

        let size = MapEditorGeometry.imageSize(image, degrees: photoDegrees)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        return CGSize(
            width: -1 * (location.x - center.x),
            height: -1 * (location.y - center.y)
        )
    }
}

// MARK: - Geometry Utilities

struct MapEditorGeometry {
    static func imageSize(_ image: AKImage, degrees: Double) -> CGSize {
        (degrees == 0 || degrees == 180)
            ? image.fixedSize
            : CGSize(width: image.size.height, height: image.size.width)
    }

    static func zoomToFit(
        containerSize: CGSize,
        image: AKImage,
        degrees: Double
    ) -> (scale: CGFloat, offset: CGPoint) {
        let scale = normScale(screenSize: containerSize, image: image, degrees: degrees)
        let imgSize = imageSize(image, degrees: degrees)
        let x = (containerSize.width - imgSize.width * scale) / 2.0
        let y = (containerSize.height - imgSize.height * scale) / 2.0
        let offset = CGPoint(x: x, y: y)
        return (scale, offset)
    }

    static func normScale(screenSize: CGSize, image: AKImage, degrees: Double) -> CGFloat {
        let size = imageSize(image, degrees: degrees)
        let wScale = screenSize.width / size.width
        let hScale = screenSize.height / size.height
        return min(wScale, hScale)
    }
}
