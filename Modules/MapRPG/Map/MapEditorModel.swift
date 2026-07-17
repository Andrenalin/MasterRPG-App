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
    private(set) var mapId: UUID

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
    @ObservationIgnored private var legacyMagnificationBaseline: MapViewportTransform?
    @ObservationIgnored private var appearanceTask: Task<Void, Never>?

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
        self.mapId = map.id

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
        if mapMode == .edit {
            pins.mapPins = modified
        } else {
            withAnimation(.bouncy) {
                pins.mapPins = modified
            }
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
        appearanceTask?.cancel()
        appearanceTask = nil
        let changedMap = mapId != map.id
        mapId = map.id
        hexScale = map.hexMapScale
        pinScale = map.pinScale
        resetReshare()

        if changedMap {
            appeared = false
            focusId = nil
            workingCopy = nil
            pins.isExpandedId = nil
            editEntries.needleInteraction.dragCoordinate = nil
            pins.mapPins = map.mapPins
            pins.pointer = map.pointer
            entries.resetEntries(
                mapId: map.id,
                entries: mapMode == .edit ? [] : map.entries
            )
            editEntries.resetEntries(mapId: map.id, entries: [])
        }
        changeMap(map: map)
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
        appearanceTask?.cancel()
        let expectedMapId = map.id
        appearanceTask = Task { [weak self] in
            guard let self else { return }
            let delay: Duration = mapMode == .edit ? .milliseconds(50) : .milliseconds(150)
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled, self.mapId == expectedMapId else { return }
            appeared = true
            resetEntries(newEntries: map.entries, map: map)
            withAnimation {
                if focusId == nil { resetZoom() } else { focusedMap() }
            }
            appearanceTask = nil
        }
    }

    func disappear() {
        appearanceTask?.cancel()
        appearanceTask = nil
        appeared = false
        isDragging = .nothing
        isTapping = .nothing
        editEntries.eaten = false
        editEntries.addedNewNeedlePoint = nil
        editEntries.needleInteraction.dragCoordinate = nil
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

    /// The absolute transform to capture when a pan or magnification begins.
    var viewportTransform: MapViewportTransform {
        imageModel.viewportTransform
    }

    /// Derives a transient transform from one immutable gesture baseline.
    /// `startAnchor` maps directly to `MagnifyGesture.Value.startAnchor`.
    func magnifiedViewportTransform(
        from baseline: MapViewportTransform,
        magnification: CGFloat,
        startAnchor: UnitPoint
    ) -> MapViewportTransform {
        magnifiedViewportTransform(
            from: baseline,
            magnification: magnification,
            anchor: viewportPoint(for: startAnchor)
        )
    }

    /// Point-based overload for tests and non-SwiftUI input sources.
    func magnifiedViewportTransform(
        from baseline: MapViewportTransform,
        magnification: CGFloat,
        anchor: CGPoint
    ) -> MapViewportTransform {
        let proposed = baseline.magnified(by: magnification, around: anchor)
        return constrainedViewportTransform(proposed)
    }

    /// Derives a transient pan without mutating the observable model.
    func pannedViewportTransform(
        from baseline: MapViewportTransform,
        translation: CGSize
    ) -> MapViewportTransform {
        constrainedViewportTransform(baseline.translated(by: translation))
    }

    /// Commits the final transient transform once a gesture succeeds.
    func commitViewportTransform(_ transform: MapViewportTransform) {
        applyViewportTransform(transform)
        imageModel.lastScale = transform.scale
        imageModel.lastOffset = transform.offset
        legacyMagnificationBaseline = nil
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
            commitViewportTransform(MapViewportTransform(scale: scale, offset: offset))
        }
    }

    func zoomIn(at point: CGPoint) -> (CGFloat, CGPoint) {
        let baseline = viewportTransform
        guard baseline.scale.isFinite, baseline.scale > 0 else {
            return (MapViewportTransform.minimumScale, baseline.offset)
        }

        let newScale = max(MapViewportTransform.minimumScale, baseline.scale * 4)
        let centeredPoint = CGPoint(
            x: containerSize.width / 2,
            y: containerSize.height / 2
        )
        let centered = baseline
            .magnified(by: newScale / baseline.scale, around: point)
            .translated(by: CGSize(
                width: centeredPoint.x - point.x,
                height: centeredPoint.y - point.y
            ))
        let constrained = constrainedViewportTransform(centered)
        return (constrained.scale, constrained.offset)
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
            let scale = max(MapViewportTransform.minimumScale, newScale)
            commitViewportTransform(MapViewportTransform(
                scale: scale,
                offset: CGPoint(
                    x: -1 * (focusMap.xOffset - 25) * scale,
                    y: -1 * (focusMap.yOffset - 25) * scale
                )
            ))
        }
    }

    // MARK: - Gesture: Scale

    func updateScale(_ value: CGFloat, updateLast: Bool) {
        if updateLast || legacyMagnificationBaseline == nil {
            legacyMagnificationBaseline = viewportTransform
        }
        guard let baseline = legacyMagnificationBaseline else { return }
        let transform = magnifiedViewportTransform(
            from: baseline,
            magnification: value,
            startAnchor: .center
        )
        applyViewportTransform(transform)
        imageModel.lastScale = transform.scale
    }

    // MARK: - Gesture: Drag

    func dragPoint(location: CGPoint) -> DraggingType {
        .image
    }

    func updateOffset(with newLocation: CGPoint, firstOffset: CGPoint) {
        let baseline = MapViewportTransform(scale: imageModel.scale, offset: firstOffset)
        let transform = pannedViewportTransform(
            from: baseline,
            translation: CGSize(width: newLocation.x, height: newLocation.y)
        )
        applyViewportTransform(transform)
        imageModel.lastOffset = firstOffset
    }

    // MARK: - Gesture: Double Tap

    func onDoubleTapped(with location: CGPoint) {
        zooming(on: location)
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
        imageModel.lastScale = imageModel.scale
        imageModel.lastOffset = imageModel.offset
        legacyMagnificationBaseline = nil
    }

    private func viewportPoint(for unitPoint: UnitPoint) -> CGPoint {
        CGPoint(
            x: containerSize.width * unitPoint.x,
            y: containerSize.height * unitPoint.y
        )
    }

    private func constrainedViewportTransform(
        _ transform: MapViewportTransform
    ) -> MapViewportTransform {
        MapEditorGeometry.constrainedViewportTransform(
            transform,
            containerSize: containerSize,
            contentSize: canvasSize
        )
    }

    private func applyViewportTransform(_ transform: MapViewportTransform) {
        imageModel.scale = transform.scale
        imageModel.offset = transform.offset
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

    static func constrainedViewportTransform(
        _ transform: MapViewportTransform,
        containerSize: CGSize,
        contentSize: CGSize,
        overscroll: CGFloat = 300
    ) -> MapViewportTransform {
        let minimumScale = MapViewportTransform.minimumScale
        let scale = transform.scale.isFinite
            ? max(minimumScale, transform.scale)
            : minimumScale
        let offset = CGPoint(
            x: transform.offset.x.isFinite ? transform.offset.x : 0,
            y: transform.offset.y.isFinite ? transform.offset.y : 0
        )

        guard containerSize.width.isFinite,
              containerSize.height.isFinite,
              containerSize.width > 0,
              containerSize.height > 0,
              contentSize.width.isFinite,
              contentSize.height.isFinite,
              contentSize.width > 0,
              contentSize.height > 0 else {
            return MapViewportTransform(scale: scale, offset: offset)
        }

        let boundedOverscroll = overscroll.isFinite ? max(0, overscroll) : 0
        let maxX = max(
            boundedOverscroll,
            (containerSize.width - contentSize.width * scale) / 2
        )
        let maxY = max(
            boundedOverscroll,
            (containerSize.height - contentSize.height * scale) / 2
        )
        let minX = containerSize.width - contentSize.width * scale - maxX
        let minY = containerSize.height - contentSize.height * scale - maxY

        return MapViewportTransform(
            scale: scale,
            offset: CGPoint(
                x: min(max(offset.x, minX), maxX),
                y: min(max(offset.y, minY), maxY)
            )
        )
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
