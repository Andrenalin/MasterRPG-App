// @copyright André Trettin

import CoreRPG
import SwiftUI

@MainActor @Observable
final class MapEditorSession {
    // MARK: - View State

    let configuration: MapEditorConfiguration
    let actions: MapEditorActions
    let viewport: ViewportModel
    var pins: MapPinViewModel
    let rooms: MapRoomStore
    let selection = MapEditorSelectionStore()
    var entries: MapEntryViewerModel { rooms.passive }
    var editEntries: MapEntryViewerModel { rooms.active }
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

    var mapMode: MapMode { configuration.mode }
    var playerPinId: UUID? { configuration.playerPinId }
    var isStreaming: Bool = false
    var isPointing: Bool = false

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

    // MARK: - Dependencies

    private var image: AKImage
    private var photoDegrees: Double
    private var canvasSize: CGSize
    private var containerSize: CGSize
    private var pendingInitialFitMapId: UUID?
    private var presentationIsActive = false
    @ObservationIgnored private var actionRouter: MapEditorActionRouter?

    // MARK: - Initialization

    init(
        map: MapModel,
        image: AKImage,
        photoDegrees: Double,
        containerSize: CGSize = .zero,
        configuration: MapEditorConfiguration,
        actions: MapEditorActions = MapEditorActions()
    ) {
        self.configuration = configuration
        self.actions = actions
        self.image = image
        self.photoDegrees = photoDegrees
        let resolvedCanvasSize = Self.resolvedCanvasSize(
            mapSize: CGSize(width: map.width, height: map.height),
            image: image,
            degrees: photoDegrees
        )
        self.canvasSize = resolvedCanvasSize
        self.containerSize = containerSize
        self.pinScale = map.pinScale
        self.hexScale = map.hexMapScale
        self.lastPinScale = map.pinScale
        self.lastHexScale = map.hexMapScale
        self.isHexMap = map.entries.contains(where: { $0.isHexGrid })
        self.displayMode = configuration.displayMode
        self.mapId = map.id
        self.pendingInitialFitMapId = Self.isValidSize(containerSize)
            && Self.isValidSize(resolvedCanvasSize)
            ? nil
            : map.id

        let viewportConfiguration = ViewportConfiguration(
            id: map.id,
            contentSize: resolvedCanvasSize,
            containerSize: containerSize,
            maximumScaleMultiplier: 8,
            panPolicy: .minimumVisible(44)
        )
        let viewportModel = ViewportModel(configuration: viewportConfiguration)
        self.viewport = viewportModel
        self.pins = MapPinViewModel(mapPins: map.mapPins, pointer: map.pointer)
        // Game mode seeds entries immediately (no working-copy merge needed); edit mode
        // starts empty and lets firstAppear/resetEntries do the merge against the working copy.
        self.rooms = MapRoomStore(
            mapId: map.id,
            passiveEntries: configuration.mode == .edit ? [] : map.entries
        )

        pins.configureInteractionHandler { [weak self] event in
            self?.handlePinSelection(event)
        }
        rooms.active.configureNeedleSelectionHandler { [weak self] point in
            self?.handleNeedleSelection(point)
        }
    }

    convenience init(
        map: MapModel,
        image: AKImage,
        photoDegrees: Double,
        containerSize: CGSize,
        displayMode: MapDisplayMode = .master,
        mapMode: MapMode = .edit,
        playerPinId: UUID? = nil
    ) {
        self.init(
            map: map,
            image: image,
            photoDegrees: photoDegrees,
            containerSize: containerSize,
            configuration: MapEditorConfiguration(
                mode: mapMode,
                displayMode: displayMode,
                playerPinId: playerPinId
            )
        )
    }

    private func handlePinSelection(_ event: MapPinInteractionEvent) {
        switch event {
        case let .tap(pin, _):
            rooms.active.selectNeedle(nil)
            selection.selectPin(pins.isExpandedId == pin.id ? pin.id : nil)
        case .doubleTap:
            rooms.active.selectNeedle(nil)
            selection.selectPin(nil)
        case .beginMove:
            rooms.active.selectNeedle(nil)
            selection.selectPin(nil)
        case .move, .action:
            break
        }
        actionRouter?.handle(.pin(event))
    }

    private func handleNeedleSelection(_ point: MapNeedlePointModel?) {
        selection.selectNeedle(point?.id)
        if point != nil {
            pins.isExpandedId = nil
        }
    }

    func beginNeedleDrag(_ point: MapNeedlePointModel) {
        pins.isExpandedId = nil
        editEntries.selectNeedle(point)
        selection.selectNeedle(point.id)
    }

    func installActionRouter(_ router: MapEditorActionRouter?) {
        actionRouter = router
    }

    func route(_ event: MapEditorEvent) {
        actionRouter?.handle(event)
    }

    func clearSelections() {
        selection.clear()
        pins.isExpandedId = nil
        editEntries.selectNeedle(nil)
    }

    // MARK: - Container Size Updates

    func updateContainerSize(_ newSize: CGSize) {
        guard Self.isValidSize(newSize) else { return }
        guard containerSize != newSize else { return }
        containerSize = newSize
        if completePendingInitialFitIfPossible() {
            return
        }
        viewport.resize(to: makeViewportConfiguration())
    }

    func updateCanvas(map: MapModel, image: AKImage, photoDegrees: Double) {
        if mapId != map.id {
            changeImage(map: map)
        }
        let newCanvasSize = Self.resolvedCanvasSize(
            mapSize: CGSize(width: map.width, height: map.height),
            image: image,
            degrees: photoDegrees
        )
        let geometryChanged = self.photoDegrees != photoDegrees
            || canvasSize != newCanvasSize
            || ObjectIdentifier(self.image) != ObjectIdentifier(image)

        self.image = image
        self.photoDegrees = photoDegrees
        canvasSize = newCanvasSize

        if completePendingInitialFitIfPossible() {
            return
        }
        if geometryChanged {
            viewport.configure(makeViewportConfiguration())
        }
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

    func resetEntries(
        newEntries: [MapEntryModel],
        map: MapModel,
        appliesFocus: Bool = true
    ) {
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

        // Seed persisted focus regardless of whether game-mode entries were
        // already installed at session creation. Initial synchronization keeps
        // the focus value but deliberately does not zoom to it.
        let focus = final.first(where: { $0.focused })?.id
        let focusChanged = focus != focusId
        if focusChanged {
            focusId = focus
        }

        if entries.entries != final {
            withAnimation(.bouncy) {
                entries.resetEntries(mapId: map.id, entries: final)
            }
            isHexMap = final.contains(where: { $0.isHexGrid })
        }

        if focusChanged, appliesFocus, appeared {
            focusedMap()
        }
    }

    // MARK: - Change Management (view state only — no save)

    func changeImage(map: MapModel) {
        let changedMap = mapId != map.id
        mapId = map.id
        hexScale = map.hexMapScale
        pinScale = map.pinScale
        resetReshare()

        if changedMap {
            appeared = false
            pendingInitialFitMapId = map.id
            focusId = nil
            workingCopy = nil
            clearSelections()
            pins.mapPins = map.mapPins
            pins.pointer = map.pointer
            rooms.reset(
                mapId: map.id,
                passiveEntries: mapMode == .edit ? [] : map.entries
            )
            // Content identity is part of viewport state. Reset even when the
            // replacement map happens to have the same image dimensions.
            viewport.configure(makeViewportConfiguration())
        }
        changeMap(map: map)
    }

    func changeMap(map: MapModel) {
        editEntries.needleInteraction.dragCoordinate = nil
        clearSelections()

        if appeared {
            resetZoom()
        }
    }

    // MARK: - First Appear

    func firstAppear(map: MapModel) {
        guard mapId == map.id else { return }
        presentationIsActive = true
        appeared = false
        pendingInitialFitMapId = map.id
        resetEntries(newEntries: map.entries, map: map, appliesFocus: false)
        _ = completePendingInitialFitIfPossible()
    }

    func disappear() {
        presentationIsActive = false
        appeared = false
        editEntries.needleInteraction.dragCoordinate = nil
    }

    // MARK: - Zooming

    func resetZoom() {
        viewport.reset()
    }

    func focusedMap() {
        guard let focusId else {
            resetZoom()
            return
        }

        guard let focusRoom = entries.roomNode(for: focusId) else {
            resetZoom()
            return
        }

        focus(on: focusRoom.bounds)
    }

    /// Explicit editor room navigation focuses the active working-copy room.
    /// Persisted game focus is still retained without overriding initial fit.
    func focusActiveEntry() {
        guard let activeEntryId = editEntries.entries.first?.id,
              let activeRoom = editEntries.roomNode(for: activeEntryId) else {
            resetZoom()
            return
        }
        focus(on: activeRoom.bounds)
    }

    private func focus(on bounds: CGRect) {
        guard bounds.width.isFinite,
              bounds.height.isFinite,
              bounds.width > 0,
              bounds.height > 0,
              Self.isValidSize(containerSize) else {
            resetZoom()
            return
        }
        let sw = containerSize.width / (bounds.width + 50)
        let sh = containerSize.height / (bounds.height + 50)
        let newScale = min(sw, sh)

        withAnimation {
            let scale = viewport.geometry.clampedScale(newScale)
            viewport.commit(ViewportTransform(
                scale: scale,
                offset: CGPoint(
                    x: viewport.geometry.containerCenter.x - bounds.midX * scale,
                    y: viewport.geometry.containerCenter.y - bounds.midY * scale
                )
            ))
        }
    }

    func contentPoint(fromViewport point: CGPoint) -> CGPoint {
        viewport.geometry.contentPoint(fromViewport: point, transform: viewport.transform)
    }

    func viewportPoint(fromContent point: CGPoint) -> CGPoint {
        viewport.geometry.viewportPoint(fromContent: point, transform: viewport.transform)
    }

    private func makeViewportConfiguration() -> ViewportConfiguration {
        ViewportConfiguration(
            id: mapId,
            contentSize: canvasSize,
            containerSize: containerSize,
            maximumScaleMultiplier: 8,
            panPolicy: .minimumVisible(44)
        )
    }

    @discardableResult
    private func applyPendingInitialFitIfPossible() -> Bool {
        guard pendingInitialFitMapId == mapId,
              Self.isValidSize(containerSize),
              Self.isValidSize(canvasSize) else { return false }
        let configuration = makeViewportConfiguration()
        if viewport.configuration != configuration {
            viewport.configure(configuration)
        } else {
            viewport.reset()
        }
        pendingInitialFitMapId = nil
        return true
    }

    @discardableResult
    private func completePendingInitialFitIfPossible() -> Bool {
        guard applyPendingInitialFitIfPossible() else { return false }
        if presentationIsActive {
            appeared = true
        }
        return true
    }

    private static func isValidSize(_ size: CGSize) -> Bool {
        size.width.isFinite
            && size.height.isFinite
            && size.width > 0
            && size.height > 0
    }

    private static func resolvedCanvasSize(
        mapSize: CGSize,
        image: AKImage,
        degrees: Double
    ) -> CGSize {
        guard mapSize.width.isFinite,
              mapSize.height.isFinite,
              mapSize.width > 0,
              mapSize.height > 0 else {
            return ViewportGeometry.rotatedContentSize(
                image.fixedSize,
                rotationDegrees: degrees
            )
        }
        return mapSize
    }

    // MARK: - Helper Methods

    func entry(for location: CGPoint, in _: MapModel) -> MapEntryModel? {
        entries.roomNodes.last { $0.path.contains(location) }?.entry
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
            map.pointer.location = contentPoint(fromViewport: location)
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
        actions.sendMapUpdates?()
    }

    var mapCanvasSize: CGSize { canvasSize }
}
