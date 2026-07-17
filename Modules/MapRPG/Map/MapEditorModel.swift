// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

enum MapMode {
    case edit
    case gameMaster
    case player
    case viewer
}

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

    // MARK: - Toolbar State (merged from EditToolBarModel)

    var pinScale: CGFloat
    var hexScale: Double
    // Max room coordinate extent relative to the map image; 1.0 is the image boundary.
    var maxWidthRatio: Double = 1.0
    var maxHeightRatio: Double = 1.0
    var lastPinScale: CGFloat = 1
    var lastHexScale: Double = 1
    var isHexMap: Bool = false
    var displayMode: MapDisplayMode = .master
    var hideCloseButton: Bool = false

    var canReshare: Bool { lastHexScale != hexScale || lastPinScale != pinScale }

    func resetScales(from map: MapModel) {
        pinScale = map.pinScale
        hexScale = map.hexMapScale
        resetReshare()
    }

    func resetReshare() {
        lastPinScale = pinScale
        lastHexScale = hexScale
    }

    // MARK: - Game Mode State

    var mapMode: MapMode = .edit
    var playerPinId: UUID? = nil
    var isStreaming: Bool = false
    var isPointing: Bool = false
    var sendMapUpdates: (() -> Void)? = nil
    var sendPinUpdate: ((UUID) -> Void)? = nil
    var focusedCallback: (() -> Void)? = nil

    var iconDisplayMode: String {
        switch displayMode {
        case .master: "rectangle.3.offgrid.fill"
        case .player: "rectangle.lefthalf.inset.filled"
        case .reader: "rectangle.3.offgrid"
        }
    }

    func toggleDisplayMode() {
        displayMode = switch displayMode {
        case .master: .player
        case .player: .reader
        case .reader: .master
        }
    }

    enum DraggingType: Hashable {
        case nothing
        case image
    }

    var isDragging: DraggingType = .nothing
    var isTapping: DraggingType = .nothing

    // MARK: - Dependencies

    private var image: AKImage
    private var photoDegrees: Double
    private var canvasSize: CGSize
    private var containerSize: CGSize

    // MARK: - Initialization

    init(map: MapModel, image: AKImage, photoDegrees: Double, containerSize: CGSize, displayMode: MapDisplayMode = .master, mapMode: MapMode = .edit, playerPinId: UUID? = nil) {
        self.image = image
        self.photoDegrees = photoDegrees
        self.canvasSize = MapEditorGeometry.canvasSize(
            mapSize: CGSize(width: map.width, height: map.height),
            image: image,
            degrees: photoDegrees
        )
        self.containerSize = containerSize
        self.pinScale = map.pinScale
        self.hexScale = map.hexMapScale
        self.lastPinScale = map.pinScale
        self.lastHexScale = map.hexMapScale
        self.isHexMap = map.entries.contains(where: { $0.isHexGrid })
        self.displayMode = displayMode
        self.mapMode = mapMode
        self.playerPinId = playerPinId

        self.imageModel = ImageViewerModel(offset: .zero, scale: 1)
        self.pins = MapPinViewModel(mapPins: map.mapPins, pointer: map.pointer)
        // Game mode seeds entries immediately (no working-copy merge needed); edit mode
        // starts empty and lets firstAppear/resetEntries do the merge against the working copy.
        self.entries = MapEntryViewerModel(mapId: map.id, entries: mapMode == .edit ? [] : map.entries)
        self.editEntries = MapEntryViewerModel(mapId: map.id, entries: [])
    }

    // MARK: - Container Size Updates

    func updateContainerSize(_ newSize: CGSize) {
        guard containerSize != newSize else { return }
        containerSize = newSize
        resetZoom()
    }

    func updateCanvas(image: AKImage, photoDegrees: Double, mapSize: CGSize) {
        let newCanvasSize = MapEditorGeometry.canvasSize(
            mapSize: mapSize,
            image: image,
            degrees: photoDegrees
        )
        let geometryChanged = self.photoDegrees != photoDegrees
            || canvasSize != newCanvasSize
            || ObjectIdentifier(self.image) != ObjectIdentifier(image)

        self.image = image
        self.photoDegrees = photoDegrees
        canvasSize = newCanvasSize

        guard geometryChanged, appeared else { return }
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
        let activeEntryId = editEntries.entries.first?.id

        // Merge incoming entries: prefer working-copy version for any entry that has
        // been locally edited (active edit entry and anything already flushed into entries).
        let merged = newEntries.map { incoming -> MapEntryModel in
            // Active edit entry: keep what the user is working on, never overwrite with live
            if incoming.id == activeEntryId {
                return editEntries.entries.first ?? incoming
            }
            // Previously-edited entries reflected in display: keep local version if it differs
            // from the live map (it was flushed from editEntries and not yet committed).
            if let local = entries.entries.first(where: { $0.id == incoming.id }),
               workingCopy?.entries.contains(where: { $0.id == incoming.id && $0 != incoming }) == true {
                return local
            }
            return incoming
        }

        // Preserve hex entries that were generated into the working copy but don't exist in
        // the live map yet (they only reach the store on checkmark). Skip in game mode —
        // the live map is the single source of truth, so stale local hex entries must not
        // be re-appended after the user toggles hex off.
        let hexToAppend: [MapEntryModel]
        if workingCopy != nil {
            let localHexEntries = entries.entries.filter { $0.isHexGrid }
            let mergedIds = Set(merged.map { $0.id })
            hexToAppend = localHexEntries.filter { !mergedIds.contains($0.id) }
        } else {
            hexToAppend = []
        }
        let final = merged + hexToAppend

        guard entries.entries != final else { return }

        withAnimation(.bouncy) {
            entries.resetEntries(mapId: map.id, entries: final)
        }
        isHexMap = final.contains(where: { $0.isHexGrid })

        // Update focus if needed
        let focus = final.first(where: { $0.focused })?.id
        if focus != focusId {
            focusId = focus
            focusedMap()
        }
    }

    // MARK: - Change Management (view state only — no save)

    func changeImage(map: MapModel) {
        hexScale = map.hexMapScale
        pinScale = map.pinScale
        resetReshare()

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
            let delay: Duration = mapMode == .edit ? .milliseconds(50) : .milliseconds(150)
            try? await Task.sleep(for: delay)
            await MainActor.run {
                appeared = true
                resetEntries(newEntries: map.entries, map: map)
                withAnimation {
                    if focusId == nil { resetZoom() } else { focusedMap() }
                }
            }
        }
    }

    // MARK: - Zooming

    func resetZoom() {
        let (newScale, newOffset) = MapEditorGeometry.zoomToFit(
            containerSize: containerSize,
            contentSize: canvasSize
        )
        imageModel.normScale = newScale
        zoom(scale: newScale, at: newOffset)
    }

    func zooming(on location: CGPoint) {
        let (newScale, newOffset): (CGFloat, CGPoint)
        if imageModel.scale != imageModel.normScale {
            (newScale, newOffset) = MapEditorGeometry.zoomToFit(
                containerSize: containerSize,
                contentSize: canvasSize
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

        let imgSize = canvasSize
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
        let imgSize = canvasSize
        let offX = max(300, (containerSize.width - imgSize.width * imageModel.scale) / 2)
        let offY = max(300, (containerSize.height - imgSize.height * imageModel.scale) / 2)
        let minX = containerSize.width - (imgSize.width * imageModel.scale) - offX
        let minY = containerSize.height - (imgSize.height * imageModel.scale) - offY

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
    #if !os(tvOS)
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
    #endif
    
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

    // MARK: - Pointer (game mode)

    func resetPointer(map: MapModel) {
        guard pins.pointer != map.pointer else { return }
        if appeared {
            withAnimation(.bouncy) { pins.pointer = map.pointer }
        } else {
            pins.pointer = map.pointer
        }
    }

    func updatePointer(location: CGPoint, map: MapModel, withOutRelocation: Bool = false) {
        guard map.pointer.isShown || isPointing else { return }
        if withOutRelocation {
            map.pointer.location = location
        } else {
            map.pointer.location = (location - imageModel.offset) / imageModel.scale
        }
        map.pointer.timeInterval = max(
            Date.now.timeIntervalSince1970,
            map.pointer.timeInterval.nextUp
        )
        pins.setPinPointer(updatedPin: map.pointer)
        if mapMode == .gameMaster {
            map.pointer.isShown = isPointing
            pins.setPinPointer(updatedPin: map.pointer)
        }
        sendMapUpdates?()
    }

    // MARK: - Computed Properties

    var currentSize: CGSize {
        canvasSize * imageModel.scale
    }

    var mapCanvasSize: CGSize { canvasSize }

    func imageOffset() -> CGSize {
        guard let location = editEntries.selectedNeedleCoordinate else { return .zero }

        let size = canvasSize
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        return CGSize(
            width: -1 * (location.x - center.x),
            height: -1 * (location.y - center.y)
        )
    }
}

// MARK: - Geometry Utilities

struct MapEditorGeometry {
    static func canvasSize(mapSize: CGSize, image: AKImage, degrees: Double) -> CGSize {
        guard mapSize.width.isFinite,
              mapSize.height.isFinite,
              mapSize.width > 0,
              mapSize.height > 0 else {
            return imageSize(image, degrees: degrees)
        }
        return mapSize
    }

    static func imageSize(_ image: AKImage, degrees: Double) -> CGSize {
        let originalSize = image.fixedSize
        guard originalSize.width.isFinite,
              originalSize.height.isFinite,
              originalSize.width > 0,
              originalSize.height > 0 else { return .zero }

        let normalizedDegrees = normalizedDegrees(degrees)
        let radians = normalizedDegrees * .pi / 180
        let cosine = CGFloat(abs(cos(radians)))
        let sine = CGFloat(abs(sin(radians)))
        return CGSize(
            width: originalSize.width * cosine + originalSize.height * sine,
            height: originalSize.width * sine + originalSize.height * cosine
        )
    }

    static func zoomToFit(
        containerSize: CGSize,
        contentSize: CGSize
    ) -> (scale: CGFloat, offset: CGPoint) {
        let scale = normScale(screenSize: containerSize, contentSize: contentSize)
        let x = (containerSize.width - contentSize.width * scale) / 2.0
        let y = (containerSize.height - contentSize.height * scale) / 2.0
        let offset = CGPoint(x: x, y: y)
        return (scale, offset)
    }

    static func normScale(screenSize: CGSize, contentSize: CGSize) -> CGFloat {
        guard screenSize.width.isFinite,
              screenSize.height.isFinite,
              screenSize.width > 0,
              screenSize.height > 0,
              contentSize.width.isFinite,
              contentSize.height.isFinite,
              contentSize.width > 0,
              contentSize.height > 0 else { return 1 }
        let wScale = screenSize.width / contentSize.width
        let hScale = screenSize.height / contentSize.height
        return min(wScale, hScale)
    }

    static func normalizedDegrees(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder < 0 ? remainder + 360 : remainder
    }
}
