// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

struct MapEditor: View {
    init(
        editController: EditController,
        image: AKImage,
        photoDegrees: Double,
        map: MapModel,
        viewMode: MapDisplayMode,
        isTileEditor: Bool = false,
        containerSize: CGSize,
        mapMode: MapMode = .edit,
        playerPinId: UUID? = nil,
        closeAction: (() -> Void)? = nil,
        sendMapUpdates: (() -> Void)? = nil,
        sendPinUpdate: ((UUID) -> Void)? = nil,
        focused: (() -> Void)? = nil
    ) {
        self.editController = editController
        self.image = image
        self.photoDegrees = photoDegrees
        self.map = map
        self.viewMode = viewMode
        self.isTileEditor = isTileEditor
        self.containerSize = containerSize
        self.closeAction = closeAction
        self.sendMapUpdatesAction = sendMapUpdates
        self.sendPinUpdateAction = sendPinUpdate
        self.focusedAction = focused
        self.mapEditController = MapEditController(editController: editController)

        self._viewModel = State(wrappedValue: MapEditorModel(
            map: map, image: image, photoDegrees: photoDegrees,
            containerSize: containerSize, displayMode: viewMode,
            mapMode: mapMode, playerPinId: playerPinId
        ))
    }

    let editController: EditController
    let image: AKImage
    let photoDegrees: Double
    let map: MapModel
    let viewMode: MapDisplayMode
    let isTileEditor: Bool
    let containerSize: CGSize
    let closeAction: (() -> Void)?
    let sendMapUpdatesAction: (() -> Void)?
    let sendPinUpdateAction: ((UUID) -> Void)?
    let focusedAction: (() -> Void)?
    let mapEditController: MapEditController

    @State private var viewModel: MapEditorModel
    @State private var coverMapImage: AKImage?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(MapRootModel.self) private var root
    @Environment(DropPinModel.self) private var dropPinModel

    private var canvasConfiguration: MapCanvasConfiguration {
        MapCanvasConfiguration(
            imageIdentifier: ObjectIdentifier(image),
            imageSize: image.fixedSize,
            degrees: photoDegrees,
            mapSize: CGSize(width: map.width, height: map.height),
            usesCoverTile: map.displayConfig.tileCoordinates.count == 4
        )
    }

    var body: some View {
        ManagedNavigationStack(name: "MapEditor") { navigator in
            ZStack(alignment: .topLeading) {
                Color.clear

                ZStack(alignment: .topLeading) {
                    MapOrientedImage(
                        image: image,
                        degrees: photoDegrees,
                        canvasSize: viewModel.mapCanvasSize
                    )
                    .allowsHitTesting(false)

                    overlayMap
                }
                    .frame(
                        width: viewModel.mapCanvasSize.width,
                        height: viewModel.mapCanvasSize.height,
                        alignment: .topLeading
                    )
                    .scaleEffect(viewModel.imageModel.scale, anchor: .topLeading)
                    .offset(x: viewModel.imageModel.offset.x, y: viewModel.imageModel.offset.y)
            }
            .frame(width: containerSize.width, height: containerSize.height, alignment: .topLeading)
            .background {
                Rectangle().fill(Color.black.gradient)
                    .ignoresSafeArea()
            }
            .overlay {
                backColor.opacity(viewModel.appeared ? 0 : 1)
            }
#if !os(tvOS)
            .dragTapGesture(isActive: viewModel.mapMode != .viewer, pressAction: pressAction(_:), releaseAction: releaseAction(_:), doubleTapAction: doubleTapAction(_:), dragStartAction: dragStartAction(_:), dragAction: dragAction(_:), dragEndAction: dragEndAction(_:), endAction: endAction(_:), magnifierAction: magnifierAction(_:isFirst:))
#endif
            .onChange(of: editController.editorModel.sheetEditorModel.itemId) {
                viewModel.changeImage(map: map)
            }
            .onChange(of: editController.editorModel.sheetEditorModel.entryId, initial: true) {
                guard viewModel.mapMode == .edit else { return }
                mapEditController.changeMap(
                    map: map,
                    currentEntryId: editController.editorModel.sheetEditorModel.entryId,
                    editorModel: viewModel
                )
            }
            .onChange(of: map.mapPins) {
                viewModel.resetPlayerAndPins(newPins: map.mapPins, map: map, pinScale: viewModel.pinScale)
                mapEditController.mergeExternalPins(newMap: map, editorModel: viewModel)
            }
            .onChange(of: map.entries) {
                viewModel.resetEntries(newEntries: map.entries, map: map)
                mapEditController.mergeExternalEntries(newMap: map, editorModel: viewModel)
            }
            .onChange(of: map.pointer) {
                viewModel.resetPointer(map: map)
            }
            .onChange(of: containerSize) {
                viewModel.updateContainerSize(containerSize)
            }
            .onChange(of: canvasConfiguration, initial: true) {
                viewModel.updateCanvas(
                    image: image,
                    photoDegrees: photoDegrees,
                    mapSize: CGSize(width: map.width, height: map.height)
                )
            }
            .task(id: canvasConfiguration) {
                renderCoverMapImage()
            }
            .onChange(of: dropPinModel.items) {
                dropPin()
            }
            // Game mode: propagate scale changes to the live map, and receive them back
            .onChange(of: map.pinScale) {
                guard viewModel.mapMode != .edit, map.pinScale != viewModel.pinScale else { return }
                viewModel.pinScale = map.pinScale
            }
            .onChange(of: viewModel.pinScale) {
                guard viewModel.mapMode != .edit else { return }
                map.pinScale = viewModel.pinScale
            }
            .onChange(of: viewModel.hexScale) {
                guard viewModel.mapMode != .edit,
                      viewModel.hexScale != 0,
                      viewModel.hexScale != map.hexMapScale else { return }
                editController.createHexMap(model: map, hexMapScale: viewModel.hexScale)
            }
            .onAppear {
                viewModel.sendMapUpdates = sendMapUpdatesAction
                viewModel.sendPinUpdate = sendPinUpdateAction
                viewModel.focusedCallback = focusedAction
                if viewModel.mapMode != .edit {
                    // Copy persistent game state from the previous map session
                    if let prev = root.rootModel.gameEditorModel, prev !== viewModel {
                        viewModel.isStreaming = prev.isStreaming
                        viewModel.isPointing = prev.isPointing
                        if viewModel.mapMode == .gameMaster {
                            viewModel.displayMode = prev.displayMode
                        }
                    }
                    root.rootModel.gameEditorModel = viewModel
                    viewModel.resetReshare()
                }
                viewModel.firstAppear(map: map)
                if viewModel.mapMode == .edit {
                    if isTileEditor {
                        setupTileEditor()
                    } else {
                        mapEditController.prepareWorkingCopy(from: map, editorModel: viewModel)
                    }
                }
            }
            .onDisappear {
                viewModel.appeared = false
            }
            .modifier(EditToolBarViewModifier(
                mapEditController: mapEditController,
                editorModel: viewModel,
                isTileEditor: isTileEditor
            ))
        }
    }
}

private extension MapEditor {
    var overlayMap: some View {
        ZStack(alignment: .topLeading) {
            // Tile Editor Mode: Only show tile entry for editing
            if isTileEditor, let tileEntry = viewModel.editEntries.entries.first {
                drawEntryView(entries: viewModel.editEntries, entry: tileEntry)
                
                if viewModel.displayMode == .master || viewModel.displayMode == .reader {
                    drawTileEntryPins()
                }
                
                if let magnifyPoint = viewModel.editEntries.selectedNeedleCoordinate {
                    drawCrosshair(location: magnifyPoint)
                        .zIndex(MapLayer.crosshair)
                }
            } else {
                // A single stable sibling tree uses zIndex for player fog, zoomed pins,
                // and the active menu. Pins never move between separate ForEach branches.
                drawEntryViews(isShowing: true)
                drawEntryViews(isShowing: false)
                drawPins

                // Pointer pin (game mode)
                if viewModel.pins.pointer.isShown {
                    drawPin(pin: viewModel.pins.pointer, isPointer: true)
                        .zIndex(MapLayer.pointer)
                }

                // Edit-mode only overlays
                if viewModel.mapMode == .edit {
                    if let editEntry = viewModel.editEntries.entries.first {
                        drawEntryView(entries: viewModel.editEntries, entry: editEntry)
                            .zIndex(MapLayer.activeEntry)
                    }

                    if viewModel.displayMode == .master || viewModel.displayMode == .reader {
                        drawEntryPins()
                            .zIndex(MapLayer.entryPins)
                    }

                    if let magnifyPoint = viewModel.editEntries.selectedNeedleCoordinate {
                        drawCrosshair(location: magnifyPoint)
                            .zIndex(MapLayer.crosshair)
                    }
                }
            }
        }
    }

    @ViewBuilder
    var backColor: some View {
        colorScheme == .dark ? Color.black.ignoresSafeArea() : Color.white.ignoresSafeArea()
    }

    var loupeSize: CGFloat {
        12 / MapEditorGeometry.imageSize(image, degrees: photoDegrees).width
    }

    var showsPinActionMenus: Bool {
        viewModel.mapMode == .edit || viewModel.mapMode == .gameMaster
    }

    func dropPin() {
        guard !dropPinModel.items.isEmpty else { return }
        if viewModel.mapMode == .edit {
            mapEditController.dropPin(at: dropPinModel.point, map: map, monsters: dropPinModel.items, editorModel: viewModel)
        } else {
            let location = (dropPinModel.point - viewModel.imageModel.offset) / viewModel.imageModel.scale
            let entry = viewModel.entry(for: location, in: map)
            withAnimation(.bouncy) {
                root.editController.addMonsters(map: map, entryId: entry?.id, location: location, monsters: dropPinModel.items, number: 1)
            }
        }
        dropPinModel.items = []
        dropPinModel.isTarget = false
    }
    
    func setupTileEditor() {
        mapEditController.prepareTileWorkingCopy(from: map, editorModel: viewModel)
    }

    /// `ImagePaint` cannot rotate its source image. Keep one bounded, oriented
    /// raster for textured fog covers so a selected cover tile still matches
    /// the map at 90/180/270 degrees. The main map continues to render directly
    /// from the original image and does not pay this extra rasterization cost.
    func renderCoverMapImage() {
        guard map.displayConfig.tileCoordinates.count == 4 else {
            coverMapImage = nil
            return
        }
        let normalizedDegrees = MapEditorGeometry.normalizedDegrees(photoDegrees)
        guard normalizedDegrees != 0 else {
            coverMapImage = image
            return
        }

        let canvasSize = viewModel.mapCanvasSize
        let longestEdge = max(canvasSize.width, canvasSize.height)
        guard longestEdge.isFinite, longestEdge > 0 else {
            coverMapImage = image
            return
        }
        let rasterScale = min(1, 2_048 / longestEdge)
        let rasterSize = CGSize(
            width: max(1, floor(canvasSize.width * rasterScale)),
            height: max(1, floor(canvasSize.height * rasterScale))
        )
        let renderer = ImageRenderer(
            content: MapOrientedImage(
                image: image,
                degrees: normalizedDegrees,
                canvasSize: rasterSize
            )
        )
        renderer.scale = 1
#if os(macOS)
        coverMapImage = renderer.nsImage ?? image
#else
        coverMapImage = renderer.uiImage ?? image
#endif
    }
}

// MARK: - Drawing MapEntry

extension MapEditor {
    @ViewBuilder
    func drawEntryViews(isShowing: Bool) -> some View {
        ForEach(viewModel.entries.entries.filter { $0.isShown == isShowing && $0.id != viewModel.editEntries.entries.first?.id }) { entry in
            drawEntryView(entries: viewModel.entries, entry: entry)
                .zIndex(entryLayer(isShowing: isShowing))
        }
    }

    func drawEntryView(entries: MapEntryViewerModel, entry: MapEntryModel) -> some View {
        let modeAllowsActivation = switch viewModel.mapMode {
        case .edit:
            viewModel.editEntries.entries.isEmpty
        case .gameMaster:
            true
        case .player, .viewer:
            false
        }
        let canActivate = viewModel.displayMode == .master && modeAllowsActivation
        return MapEntryViewer(
            entry: entry,
            displayMode: viewModel.displayMode,
            displayConfig: map.displayConfig,
            activateGestures: canActivate,
            mapImage: coverMapImage,
            mapImageSize: viewModel.mapCanvasSize
        ) {
            viewModel.editEntries.addedNewNeedlePoint = nil
            viewModel.editEntries.eaten = true

            var toggled = entries.entry(entry.id)
            toggled.isShown.toggle()
            entries.setEntry(entry: toggled)

            if viewModel.mapMode == .edit {
                guard let mapModel = editController.editModel(for: map.id) else { return }
                mapModel[entry.id] = toggled
                editController.save(updated: mapModel, message: String(localized: "update entry", bundle: .module).localizedString)
            } else {
                map[entry.id] = toggled
                if viewModel.isStreaming { viewModel.sendMapUpdates?() }
            }
        } longPressAction: {
            viewModel.editEntries.addedNewNeedlePoint = nil
            viewModel.editEntries.eaten = true

            if viewModel.mapMode == .edit {
                guard let mapModel = editController.editModel(for: map.id) else { return }
                mapModel.focused(entries.entry(entry.id))
                editController.save(updated: mapModel, message: String(localized: "focus entry", bundle: .module).localizedString)
            } else {
                map.focused(entries.entry(entry.id))
                viewModel.focusedCallback?()
            }
        }
        .frame(width: entry.size.width, height: entry.size.height)
        .offset(x: entry.xOffset, y: entry.yOffset)
    }

    func entryLayer(isShowing: Bool) -> Double {
        if viewModel.displayMode == .player, !isShowing {
            return MapLayer.playerFog
        }
        return MapLayer.entries
    }
}

// MARK: - Drawing Map Pins

extension MapEditor {
    var drawPins: some View {
        ForEach(viewModel.pins.mapPins) { pin in
            if viewModel.displayMode != .player || pin.isShown {
                drawPin(pin: pin)
                    .zIndex(pinLayer(pin))
            }
        }
    }

    func drawPin(pin: MapPinModel, isPointer: Bool = false) -> some View {
        let presentedPin = pinForPresentation(pin, isPointer: isPointer)
        let scaleFactor: CGFloat = pin.isZoom ? 4.0 : 1.0
        let pinSize = pin.size.size * viewModel.pinScale * scaleFactor
        let location: CGPoint = pin.location - (pinSize / CGFloat(2.0))
        let canDrag = viewModel.mapMode == .edit
            || viewModel.mapMode == .gameMaster
            || (viewModel.mapMode == .player
                && (pin.id == viewModel.playerPinId || isPointer))
        let isExpanded = showsPinActionMenus && viewModel.pins.isExpandedId == pin.id

        return MapPinActionView(
            model: viewModel.pins,
            pin: presentedPin,
            isExpanded: isExpanded,
            layoutDown: true,
            pinSize: pinSize,
            canDrag: canDrag,
            actionContext: pinActionContext(isPointer: isPointer),
            doubleTapAccessibilityLabel: doubleTapAccessibilityLabel(isPointer: isPointer),
            doubleTapAction: {
                handlePinDoubleTap(pinId: pin.id, isPointer: isPointer)
            },
            dragEndAction: { updatedPin in
                handlePinDragEnd(pin: updatedPin, isPointer: isPointer)
            },
            tapAction: {
                handlePinSingleTap(pinId: pin.id, isPointer: isPointer)
            },
            onToggleDead: {
                performGameMasterMutation(pinId: pin.id) {
                    root.gameController.toggleDeadPin(itemId: map.id, pinId: pin.id)
                }
            },
            onToggleVisibility: {
                performGameMasterMutation(pinId: pin.id) {
                    root.gameController.togglePin(itemId: map.id, pinId: pin.id)
                }
            },
            onResize: {
                performGameMasterMutation(pinId: pin.id) {
                    root.gameController.resizePin(itemId: map.id, pinId: pin.id)
                }
            },
            onToggleZoom: {
                performGameMasterMutation(pinId: pin.id) {
                    root.gameController.zoomPin(itemId: map.id, pinId: pin.id)
                }
            }
        )
        .allowsHitTesting(viewModel.displayMode != .player || pin.isShown)
        .accessibilityHidden(viewModel.displayMode == .player && !pin.isShown)
        .offset(x: location.x, y: location.y)
    }

    func pinLayer(_ pin: MapPinModel) -> Double {
        if showsPinActionMenus, viewModel.pins.isExpandedId == pin.id {
            return MapLayer.expandedPin
        }
        if pin.isZoom {
            return MapLayer.zoomedPin
        }
        return MapLayer.pin
    }

    func pinActionContext(isPointer: Bool) -> MapPinActionContext {
        guard !isPointer else { return .none }
        return switch viewModel.mapMode {
        case .edit: .editor
        case .gameMaster: .gameMaster
        case .player, .viewer: .none
        }
    }

    func pinForPresentation(_ pin: MapPinModel, isPointer: Bool) -> MapPinModel {
        guard isPointer else { return pin }
        var presentedPin = pin
        presentedPin.isDead = false
        presentedPin.isHighlighted = false
        return presentedPin
    }

    func doubleTapAccessibilityLabel(isPointer: Bool) -> LocalizedStringResource {
        if isPointer || viewModel.mapMode == .edit {
            return LocalizedStringResource("Toggle Player Visibility", bundle: .module)
        }
        return LocalizedStringResource("Toggle Pin Zoom", bundle: .module)
    }

    func handlePinSingleTap(pinId: UUID, isPointer: Bool) {
        guard viewModel.mapMode == .player, !isPointer else { return }
        performPlayerMutation(pinId: pinId) {
            root.gameController.toggleHighlightPin(itemId: map.id, pinId: pinId)
        }
    }

    func handlePinDoubleTap(pinId: UUID, isPointer: Bool) {
        if isPointer {
            if viewModel.mapMode == .edit {
                mapEditController.togglePinVisibility(pinId: pinId, editorModel: viewModel)
            } else if viewModel.mapMode == .gameMaster {
                togglePointerVisibility(pinId: pinId)
            }
            return
        }

        switch viewModel.mapMode {
        case .edit:
            mapEditController.togglePinVisibility(pinId: pinId, editorModel: viewModel)
        case .gameMaster:
            performGameMasterMutation(pinId: pinId) {
                root.gameController.zoomPin(itemId: map.id, pinId: pinId)
            }
        case .player:
            performPlayerMutation(pinId: pinId) {
                root.gameController.zoomPin(itemId: map.id, pinId: pinId)
            }
        case .viewer:
            break
        }
    }

    func handlePinDragEnd(pin updatedPin: MapPinModel, isPointer: Bool) {
        let pinId = updatedPin.id
        if isPointer {
            viewModel.updatePointer(location: updatedPin.location, map: map, withOutRelocation: true)
        } else if viewModel.mapMode == .edit {
            mapEditController.updatePinMove(pin: updatedPin, editorModel: viewModel)
        } else if viewModel.mapMode == .gameMaster {
            performGameMasterMutation(pinId: pinId) {
                root.gameController.movePin(itemId: map.id, pinId: pinId, location: updatedPin.location)
            }
        } else if viewModel.mapMode == .player, pinId == viewModel.playerPinId {
            performPlayerMutation(pinId: pinId) {
                root.gameController.movePin(itemId: map.id, pinId: pinId, location: updatedPin.location)
            }
        }
    }

    func performPlayerMutation(pinId: UUID, mutation: () -> Bool) {
        guard viewModel.mapMode == .player,
              viewModel.pins.pinPointer(for: pinId)?.isShown == true,
              mutation() else { return }
        synchronizePinFromMap(pinId: pinId)
        viewModel.sendPinUpdate?(pinId)
    }

    func performGameMasterMutation(pinId: UUID, mutation: () -> Bool) {
        guard viewModel.mapMode == .gameMaster, mutation() else { return }
        synchronizePinFromMap(pinId: pinId)
        if viewModel.isStreaming {
            viewModel.sendMapUpdates?()
        }
    }

    func synchronizePinFromMap(pinId: UUID) {
        guard let updatedPin = map.mapPins.first(where: { $0.id == pinId }) else { return }
        viewModel.pins.setPinPointer(updatedPin: updatedPin)
    }

    func togglePointerVisibility(pinId: UUID) {
        guard var updatedPointer = viewModel.pins.pinPointer(for: pinId) else { return }
        updatedPointer.isShown.toggle()
        updatedPointer.timeInterval = max(
            Date.now.timeIntervalSince1970,
            updatedPointer.timeInterval.nextUp
        )
        viewModel.pins.setPinPointer(updatedPin: updatedPointer)
        map.setPinPointer(updatedPin: updatedPointer)
        if viewModel.mapMode == .gameMaster, viewModel.isStreaming {
            viewModel.sendMapUpdates?()
        }
    }
}

// MARK: - MapEntry Pins

private extension MapEditor {
    @ViewBuilder
    func drawEntryPins() -> some View {
        if let entry = viewModel.editEntries.entries.first {
            ForEach(entry.coordinates.indexed(), id: \.index) { (index, point) in
                NeedleMapPin(entries: viewModel.editEntries, entryId: entry.id, index: index, map: map, mapEditController: mapEditController)
                    .offset(x: point.x - 22, y: point.y - 110)
            }
        }
    }
    
    @ViewBuilder
    func drawTileEntryPins() -> some View {
        if let entry = viewModel.editEntries.entries.first {
            ForEach(entry.coordinates.indexed(), id: \.index) { (index, point) in
                NeedleMapPin(
                    entries: viewModel.editEntries,
                    entryId: entry.id,
                    index: index,
                    map: map,
                    mapEditController: mapEditController,
                    coordinatesChanged: { updatedCoordinates in
                        mapEditController.syncTileCoordinates(updatedCoordinates, editorModel: viewModel)
                    }
                )
                .offset(x: point.x - 22, y: point.y - 110)
            }
        }
    }
}

// MARK: - Magnifier glass with Crosshair

private extension MapEditor {
    func drawCrosshair(location: CGPoint) -> some View {
        let origin = crosshairPosition(for: location)
        return magnifyContent
            .frame(width: crosshairSizeScaled.width, height: crosshairSizeScaled.height)
            .overlay {
                ZStack {
                    crosshair(in: CGRect(origin: .zero, size: crosshairSizeScaled))
                        .stroke(Color.green.opacity(0.8), lineWidth: 5)

                    crosshair(in: CGRect(origin: .zero, size: crosshairSizeScaled))
                        .stroke(Color.green.opacity(0.8), style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(Angle(degrees: 90))

                    Circle().stroke(.black.opacity(0.8), lineWidth: 6)
                }
            }
            .offset(x: origin.x, y: origin.y)
    }

    func crosshairPosition(for point: CGPoint) -> CGPoint {
        let size = crosshairSizeScaled
        var origin = point - size - CGPoint(x: 0, y: 60)
        if origin.y + viewModel.imageModel.offset.y < 0 { origin.y = point.y + 30 }
        if origin.x + viewModel.imageModel.offset.x < 0 { origin.x = point.x }
        return origin
    }

    func crosshair(in rect: CGRect) -> Path {
        var p = Path()
        let crossHairLength = rect.size.width / 3.0
        let height = rect.origin.y + rect.size.height / 2.0
        var start = CGPoint(x: rect.origin.x, y: height).rounded()
        let offset = CGPoint(x: crossHairLength, y: 0).rounded()
        p.move(to: start)
        p.addLine(to: start + offset)
        start = start + offset + offset
        p.move(to: start)
        p.addLine(to: start + offset)
        p = p.rotation(Angle(degrees: 90)).path(in: rect)
        return p
    }

    var magnifyContent: some View {
        MapOrientedImage(
            image: image,
            degrees: photoDegrees,
            canvasSize: viewModel.mapCanvasSize
        )
            .offset(viewModel.imageOffset())
            .scaleEffect(viewModel.imageModel.scale * 3)
            .frame(width: crosshairSize.width, height: crosshairSize.height)
            .clipShape(Circle())
    }

    var crosshairSize: CGSize { CGSize(width: 160, height: 160) }

    var crosshairSizeScaled: CGSize { crosshairSize / viewModel.imageModel.scale }
}

// MARK: - Gesture Handlers

private extension MapEditor {
#if !os(tvOS)
    func pressAction(_ value: DragGesture.Value) {
        if isTileEditor {
            viewModel.editEntries.eaten = false
        }
        viewModel.pressAction(value)
    }

    func releaseAction(_ value: DragGesture.Value) {
        if isTileEditor {
            handleTileEditorRelease(value)
        } else if viewModel.mapMode == .edit {
            let hasEditableEntry = !viewModel.editEntries.entries.isEmpty
            mapEditController.releaseAction(value, map: map, editorModel: viewModel, hasEditableEntry: hasEditableEntry)
        } else {
            defer { viewModel.editEntries.eaten = false }
            // A room long press focuses that room. Its simultaneous canvas
            // recognizer must not also relocate the shared pointer on release.
            guard !viewModel.editEntries.eaten else { return }
            viewModel.updatePointer(location: value.location, map: map)
        }
    }

    func doubleTapAction(_ value: DragGesture.Value) {
        viewModel.onDoubleTapped(with: value.location)
    }

    func dragStartAction(_ value: DragGesture.Value) {
        viewModel.dragStartAction(value)
    }

    func dragAction(_ value: DragGesture.Value) {
        viewModel.dragAction(value)
    }

    func dragEndAction(_: DragGesture.Value) {
        viewModel.dragEndAction()
    }

    func endAction(_: DragGesture.Value) {
        viewModel.endAction()
    }

    func magnifierAction(_ value: MagnifyGesture.Value, isFirst: Bool) {
        viewModel.updateScale(value.magnification, updateLast: isFirst)
    }
#endif

#if !os(tvOS)
    func handleTileEditorRelease(_ value: DragGesture.Value) {
        let location = (value.location - viewModel.imageModel.offset) / viewModel.imageModel.scale
        mapEditController.addTileCoordinateFromCanvas(location, editorModel: viewModel)
    }
    #endif
}

private enum MapLayer {
    static let entries = 0.0
    static let pin = 100.0
    static let activeEntry = 150.0
    static let playerFog = 200.0
    static let pointer = 250.0
    static let zoomedPin = 300.0
    static let expandedPin = 400.0
    static let entryPins = 500.0
    static let crosshair = 600.0
}

private struct MapCanvasConfiguration: Equatable {
    let imageIdentifier: ObjectIdentifier
    let imageSize: CGSize
    let degrees: Double
    let mapSize: CGSize
    let usesCoverTile: Bool
}

private struct MapOrientedImage: View {
    let image: AKImage
    let degrees: Double
    let canvasSize: CGSize

    private var originalSize: CGSize { image.fixedSize }
    private var rotatedSize: CGSize { MapEditorGeometry.imageSize(image, degrees: degrees) }

    private var horizontalScale: CGFloat {
        guard rotatedSize.width > 0 else { return 1 }
        return canvasSize.width / rotatedSize.width
    }

    private var verticalScale: CGFloat {
        guard rotatedSize.height > 0 else { return 1 }
        return canvasSize.height / rotatedSize.height
    }

    var body: some View {
        ZStack {
            Image(akImage: image)
                .resizable()
                .frame(width: originalSize.width, height: originalSize.height)
                .rotationEffect(.degrees(MapEditorGeometry.normalizedDegrees(degrees)))
        }
        .frame(width: rotatedSize.width, height: rotatedSize.height)
        .scaleEffect(x: horizontalScale, y: verticalScale)
        .frame(width: canvasSize.width, height: canvasSize.height)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(MapRootModel.self) var root

    Group {
#if os(macOS)
        MapEditor(editController: root.editController, image: AKImage(named: "photo") ?? AKImage(), photoDegrees: 0, map: MapModel.preview, viewMode: .master, containerSize: CGSize(width: 300, height: 800), mapMode: .viewer)
#else
        MapEditor(editController: root.editController, image: AKImage(systemName: "photo") ?? AKImage(), photoDegrees: 0, map: MapModel.preview, viewMode: .master, containerSize: CGSize(width: 300, height: 800), mapMode: .viewer)
#endif
    }
    .onAppear {
        root.editController.setCurrentItem(to: ItemRowTreeModel(itemId: root.itemController.itemDataModel.items[0], typeId: .map))
    }
    .environment(DropPinModel())
}
