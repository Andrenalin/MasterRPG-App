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
            mapId: map.id,
            imageIdentifier: ObjectIdentifier(image),
            imageSize: image.fixedSize,
            degrees: photoDegrees,
            mapSize: CGSize(width: map.width, height: map.height),
            usesCoverTile: map.displayConfig.tileCoordinates.count == 4
        )
    }

    var body: some View {
        ManagedNavigationStack(name: "MapEditor") { navigator in
            MapCanvasViewport(
                model: viewModel,
                containerSize: containerSize,
                isActive: viewModel.mapMode != .viewer,
                singleTapAction: handleCanvasSingleTap(at:),
                doubleTapAction: viewModel.onDoubleTapped(with:)
            ) {
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
            }
            .background {
                Rectangle().fill(Color.black.gradient)
                    .ignoresSafeArea()
            }
            .overlay {
                backColor.opacity(viewModel.appeared ? 0 : 1)
            }
            .onChange(of: editController.editorModel.sheetEditorModel.itemId) {
                viewModel.changeImage(map: map)
                if viewModel.mapMode == .edit {
                    if isTileEditor {
                        setupTileEditor()
                    } else {
                        mapEditController.prepareWorkingCopy(from: map, editorModel: viewModel)
                        mapEditController.changeMap(
                            map: map,
                            currentEntryId: editController.editorModel.sheetEditorModel.entryId,
                            editorModel: viewModel
                        )
                    }
                }
                viewModel.firstAppear(map: map)
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
                mapEditController.mergeExternalPins(newMap: map, editorModel: viewModel)
                let pins = viewModel.mapMode == .edit
                    ? viewModel.workingCopy?.mapPins ?? map.mapPins
                    : map.mapPins
                viewModel.resetPlayerAndPins(newPins: pins, map: map, pinScale: viewModel.pinScale)
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
                viewModel.pins.configureInteractionHandler(handlePinInteraction(_:))
                let editorModel = viewModel
                editorModel.editEntries.configureNeedleSelectionHandler { [weak editorModel] point in
                    guard point != nil else { return }
                    editorModel?.pins.isExpandedId = nil
                }
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
                viewModel.disappear()
                viewModel.pins.configureInteractionHandler(nil)
                viewModel.editEntries.configureNeedleSelectionHandler(nil)
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
                        .zIndex(MapLayer.entryPins)
                    drawTileEntryPinMenu()
                        .zIndex(MapLayer.entryPinMenu)
                }

                needleCrosshairLayer
                    .zIndex(MapLayer.crosshair)
            } else {
                // Room fills/covers are always painted before editor controls so their
                // shapes cannot obscure pin/needle hit targets.
                drawEntryViews(isShowing: true)
                drawEntryViews(isShowing: false)

                if viewModel.mapMode == .edit,
                   let editEntry = viewModel.editEntries.entries.first {
                    drawEntryView(entries: viewModel.editEntries, entry: editEntry)
                        .zIndex(MapLayer.activeEntry)
                }

                drawPins

                // Pointer pin (game mode)
                drawPointer()

                // Edit-mode only overlays
                if viewModel.mapMode == .edit {
                    if viewModel.displayMode == .master || viewModel.displayMode == .reader {
                        drawEntryPins()
                            .zIndex(MapLayer.entryPins)
                        drawEntryPinMenu()
                            .zIndex(MapLayer.entryPinMenu)
                    }

                    needleCrosshairLayer
                        .zIndex(MapLayer.crosshair)
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
        MapPinLayerView(
            model: viewModel.pins,
            displayMode: viewModel.displayMode,
            mapMode: viewModel.mapMode,
            playerPinId: viewModel.playerPinId,
            pinScale: viewModel.pinScale,
            showsActionMenus: showsPinActionMenus
        )
    }

    func drawPointer() -> some View {
        MapPinLayerItemView(
            model: viewModel.pins.pointerNode,
            displayMode: viewModel.displayMode,
            mapMode: viewModel.mapMode,
            playerPinId: viewModel.playerPinId,
            pinScale: viewModel.pinScale,
            showsActionMenus: false,
            layoutDown: true,
            forcedLayer: MapLayer.pointer
        )
    }

    func handlePinInteraction(_ event: MapPinInteractionEvent) {
        switch event {
        case let .tap(pin, isPointer):
            viewModel.editEntries.selectNeedle(nil)
            handlePinSingleTap(pinId: pin.id, isPointer: isPointer)
        case let .doubleTap(pin, isPointer):
            viewModel.editEntries.selectNeedle(nil)
            handlePinDoubleTap(pinId: pin.id, isPointer: isPointer)
        case let .move(pin, isPointer):
            handlePinDragEnd(pin: pin, isPointer: isPointer)
        case let .action(type, pin, isPointer, context):
            guard !isPointer else { return }
            if context == .editor {
                viewModel.workingCopy?.mapPins = viewModel.pins.mapPins
                return
            }
            guard context == .gameMaster else { return }
            switch type {
            case .dead:
                performGameMasterMutation(pinId: pin.id) {
                    root.gameController.toggleDeadPin(itemId: map.id, pinId: pin.id)
                }
            case .visibility:
                performGameMasterMutation(pinId: pin.id) {
                    root.gameController.togglePin(itemId: map.id, pinId: pin.id)
                }
            case .resize:
                performGameMasterMutation(pinId: pin.id) {
                    root.gameController.resizePin(itemId: map.id, pinId: pin.id)
                }
            case .zoom:
                performGameMasterMutation(pinId: pin.id) {
                    root.gameController.zoomPin(itemId: map.id, pinId: pin.id)
                }
            case .remove, .copy, .photo:
                break
            }
        }
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
            MapNeedleLayer(entries: viewModel.editEntries, entryId: entry.id)
        }
    }

    @ViewBuilder
    func drawEntryPinMenu() -> some View {
        if let entry = viewModel.editEntries.entries.first {
            MapNeedleMenuLayer(entries: viewModel.editEntries, entryId: entry.id)
        }
    }

    @ViewBuilder
    func drawTileEntryPins() -> some View {
        if let entry = viewModel.editEntries.entries.first {
            MapNeedleLayer(
                entries: viewModel.editEntries,
                entryId: entry.id,
                coordinatesChanged: { updatedCoordinates in
                    mapEditController.syncTileCoordinates(updatedCoordinates, editorModel: viewModel)
                }
            )
        }
    }

    @ViewBuilder
    func drawTileEntryPinMenu() -> some View {
        if let entry = viewModel.editEntries.entries.first {
            MapNeedleMenuLayer(
                entries: viewModel.editEntries,
                entryId: entry.id,
                coordinatesChanged: { updatedCoordinates in
                    mapEditController.syncTileCoordinates(updatedCoordinates, editorModel: viewModel)
                }
            )
        }
    }
}

// MARK: - Magnifier glass with Crosshair

private extension MapEditor {
    var needleCrosshairLayer: some View {
        MapNeedleCrosshairLayer(
            interaction: viewModel.editEntries.needleInteraction,
            image: image,
            degrees: photoDegrees,
            canvasSize: viewModel.mapCanvasSize,
            viewportScale: viewModel.imageModel.scale,
            viewportOffset: viewModel.imageModel.offset
        )
    }
}

private struct MapNeedleCrosshairLayer: View {
    let interaction: MapNeedleInteractionModel
    let image: AKImage
    let degrees: Double
    let canvasSize: CGSize
    let viewportScale: CGFloat
    let viewportOffset: CGPoint

    private let crosshairSize = CGSize(width: 160, height: 160)

    var body: some View {
        if let location = interaction.dragCoordinate {
            let scaledSize = crosshairSize / max(viewportScale, 0.1)
            magnifyContent(location: location)
                .frame(width: scaledSize.width, height: scaledSize.height)
                .overlay {
                    ZStack {
                        crosshair(in: CGRect(origin: .zero, size: scaledSize))
                            .stroke(Color.green.opacity(0.8), lineWidth: 5)

                        crosshair(in: CGRect(origin: .zero, size: scaledSize))
                            .stroke(
                                Color.green.opacity(0.8),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round)
                            )
                            .rotationEffect(.degrees(90))

                        Circle().stroke(.black.opacity(0.8), lineWidth: 6)
                    }
                }
                .offset(crosshairOrigin(for: location, size: scaledSize))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func magnifyContent(location: CGPoint) -> some View {
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let imageOffset = CGSize(
            width: -(location.x - center.x),
            height: -(location.y - center.y)
        )
        return MapOrientedImage(image: image, degrees: degrees, canvasSize: canvasSize)
            .offset(imageOffset)
            .scaleEffect(viewportScale * 3)
            .frame(width: crosshairSize.width, height: crosshairSize.height)
            .clipShape(.circle)
    }

    private func crosshairOrigin(for point: CGPoint, size: CGSize) -> CGSize {
        var origin = point - size - CGPoint(x: 0, y: 60)
        if origin.y + viewportOffset.y < 0 { origin.y = point.y + 30 }
        if origin.x + viewportOffset.x < 0 { origin.x = point.x }
        return CGSize(width: origin.x, height: origin.y)
    }

    private func crosshair(in rect: CGRect) -> Path {
        var path = Path()
        let crossHairLength = rect.size.width / 3
        let height = rect.origin.y + rect.size.height / 2
        var start = CGPoint(x: rect.origin.x, y: height).rounded()
        let offset = CGPoint(x: crossHairLength, y: 0).rounded()
        path.move(to: start)
        path.addLine(to: start + offset)
        start = start + offset + offset
        path.move(to: start)
        path.addLine(to: start + offset)
        return path.rotation(.degrees(90)).path(in: rect)
    }
}

// MARK: - Gesture Handlers

private extension MapEditor {
    func handleCanvasSingleTap(at location: CGPoint) {
        viewModel.pins.isExpandedId = nil
        viewModel.editEntries.selectNeedle(nil)

        if isTileEditor {
            let canvasLocation = (location - viewModel.imageModel.offset) / viewModel.imageModel.scale
            mapEditController.addTileCoordinateFromCanvas(canvasLocation, editorModel: viewModel)
        } else if viewModel.mapMode == .edit {
            let hasEditableEntry = !viewModel.editEntries.entries.isEmpty
            mapEditController.releaseAction(
                at: location,
                map: map,
                editorModel: viewModel,
                hasEditableEntry: hasEditableEntry
            )
        } else if viewModel.mapMode != .viewer {
            viewModel.updatePointer(location: location, map: map)
        }
    }
}

private struct MapCanvasViewport<Content: View>: View {
    let model: MapEditorModel
    let containerSize: CGSize
    let isActive: Bool
    let singleTapAction: (CGPoint) -> Void
    let doubleTapAction: (CGPoint) -> Void
    let content: Content

    @GestureState private var panTransform: MapViewportTransform?
    @GestureState private var magnificationTransform: MapViewportTransform?
    @State private var isPanActive = false
    @State private var isMagnifying = false
    @State private var suppressCurrentPan = false

    init(
        model: MapEditorModel,
        containerSize: CGSize,
        isActive: Bool,
        singleTapAction: @escaping (CGPoint) -> Void,
        doubleTapAction: @escaping (CGPoint) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.model = model
        self.containerSize = containerSize
        self.isActive = isActive
        self.singleTapAction = singleTapAction
        self.doubleTapAction = doubleTapAction
        self.content = content()
    }

    private var displayedTransform: MapViewportTransform {
        if isMagnifying || suppressCurrentPan {
            return magnificationTransform ?? model.viewportTransform
        }
        return panTransform ?? model.viewportTransform
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            content
                .scaleEffect(displayedTransform.scale, anchor: .topLeading)
                .offset(
                    x: displayedTransform.offset.x,
                    y: displayedTransform.offset.y
                )
        }
        .frame(width: containerSize.width, height: containerSize.height, alignment: .topLeading)
        .contentShape(.rect)
#if !os(tvOS)
        .gesture(canvasGesture, including: isActive ? .all : .none)
        .simultaneousGesture(
            magnificationGesture,
            including: isActive ? .all : .none
        )
#endif
    }

#if !os(tvOS)
    private var canvasGesture: some Gesture {
        let taps = SpatialTapGesture(count: 2)
            .exclusively(before: SpatialTapGesture(count: 1))
        return taps
            .exclusively(before: DragGesture(minimumDistance: 5))
            .updating($panTransform) { value, state, _ in
                guard !isMagnifying,
                      !suppressCurrentPan,
                      case let .second(drag) = value else { return }
                state = model.pannedViewportTransform(
                    from: model.viewportTransform,
                    translation: drag.translation
                )
            }
            .onChanged { value in
                guard case .second = value else { return }
                isPanActive = true
                if isMagnifying {
                    suppressCurrentPan = true
                }
            }
            .onEnded { value in
                defer {
                    isPanActive = false
                    suppressCurrentPan = false
                }
                switch value {
                case let .first(.first(doubleTap)):
                    doubleTapAction(doubleTap.location)
                case let .first(.second(singleTap)):
                    singleTapAction(singleTap.location)
                case let .second(drag):
                    guard !isMagnifying, !suppressCurrentPan else { return }
                    let transform = model.pannedViewportTransform(
                        from: model.viewportTransform,
                        translation: drag.translation
                    )
                    model.commitViewportTransform(transform)
                }
            }
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .updating($magnificationTransform) { value, state, _ in
                state = model.magnifiedViewportTransform(
                    from: model.viewportTransform,
                    magnification: value.magnification,
                    startAnchor: value.startAnchor
                )
            }
            .onChanged { _ in
                isMagnifying = true
                if isPanActive {
                    suppressCurrentPan = true
                }
            }
            .onEnded { value in
                let transform = model.magnifiedViewportTransform(
                    from: model.viewportTransform,
                    magnification: value.magnification,
                    startAnchor: value.startAnchor
                )
                model.commitViewportTransform(transform)
                isMagnifying = false
                if !isPanActive {
                    suppressCurrentPan = false
                }
            }
    }
#endif
}

private struct MapPinLayerView: View {
    let model: MapPinViewModel
    let displayMode: MapDisplayMode
    let mapMode: MapMode
    let playerPinId: UUID?
    let pinScale: CGFloat
    let showsActionMenus: Bool

    var body: some View {
        ForEach(model.mapPinNodes) { node in
            MapPinLayerItemView(
                model: node,
                displayMode: displayMode,
                mapMode: mapMode,
                playerPinId: playerPinId,
                pinScale: pinScale,
                showsActionMenus: showsActionMenus
            )
        }
    }
}

private struct MapPinLayerItemView: View {
    let model: MapPinNode
    let displayMode: MapDisplayMode
    let mapMode: MapMode
    let playerPinId: UUID?
    let pinScale: CGFloat
    let showsActionMenus: Bool
    var layoutDown = true
    var forcedLayer: Double?

    private var isVisible: Bool {
        if model.isPointer, !model.pin.isShown { return false }
        return displayMode != .player || model.pin.isShown
    }

    private var canDrag: Bool {
        mapMode == .edit
            || mapMode == .gameMaster
            || (mapMode == .player && (model.id == playerPinId || model.isPointer))
    }

    private var actionContext: MapPinActionContext {
        guard !model.isPointer else { return .none }
        return switch mapMode {
        case .edit: .editor
        case .gameMaster: .gameMaster
        case .player, .viewer: .none
        }
    }

    private var doubleTapAccessibilityLabel: LocalizedStringResource {
        if model.isPointer || mapMode == .edit {
            return LocalizedStringResource("Toggle Player Visibility", bundle: .module)
        }
        return LocalizedStringResource("Toggle Pin Zoom", bundle: .module)
    }

    private var layer: Double {
        if let forcedLayer { return forcedLayer }
        if showsActionMenus, model.isExpanded { return MapLayer.expandedPin }
        if model.pin.isZoom { return MapLayer.zoomedPin }
        return MapLayer.pin
    }

    var body: some View {
        if isVisible {
            MapPinActionView(
                model: model,
                layoutDown: layoutDown,
                pinScale: pinScale,
                canDrag: canDrag,
                actionContext: actionContext,
                doubleTapAccessibilityLabel: doubleTapAccessibilityLabel
            )
            .zIndex(layer)
        }
    }
}

private enum MapLayer {
    static let entries = 0.0
    static let activeEntry = 1.0
    static let pin = 100.0
    static let playerFog = 200.0
    static let pointer = 250.0
    static let zoomedPin = 300.0
    static let expandedPin = 550.0
    static let entryPins = 350.0
    static let entryPinMenu = 500.0
    static let crosshair = 600.0
}

private struct MapCanvasConfiguration: Equatable {
    let mapId: UUID
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
