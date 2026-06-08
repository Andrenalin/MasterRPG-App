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
    let focusedAction: (() -> Void)?
    let mapEditController: MapEditController

    @State private var viewModel: MapEditorModel

    @Environment(\.colorScheme) private var colorScheme
    @Environment(MapRootModel.self) private var root
    @Environment(DropPinModel.self) private var dropPinModel

    var body: some View {
        ManagedNavigationStack(name: "MapEditor") { navigator in
            ZStack(alignment: .topLeading) {
                Color.clear

                Image(akImage: image)
                    .overlay(alignment: .topLeading) {
                        overlayMap
                    }
                    .scaleEffect(viewModel.imageModel.scale)
                    .rotationEffect(Angle(degrees: photoDegrees))
                    .offset(x: viewModel.imageModel.offset.x, y: viewModel.imageModel.offset.y)
                    .contentMargins(.all, 50)
                    .frame(width: viewModel.currentSize.width, height: viewModel.currentSize.height)
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
            .dragTapGesture(isActive: viewModel.mapMode != .viewer, pressAction: pressAction(_:), releaseAction: releaseAction(_:), longPressAction: longPressAction(_:), doubleTapAction: doubleTapAction(_:), dragStartAction: dragStartAction(_:), dragAction: dragAction(_:), dragEndAction: dragEndAction(_:), endAction: endAction(_:), magnifierAction: magnifierAction(_:isFirst:))
#endif
            .onChange(of: editController.sheetEditorModel.itemId) {
                viewModel.changeImage(map: map)
            }
            .onChange(of: editController.sheetEditorModel.entryId, initial: true) {
                guard viewModel.mapMode == .edit else { return }
                mapEditController.changeMap(
                    map: map,
                    currentEntryId: editController.sheetEditorModel.entryId,
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
                    mapEditController.prepareWorkingCopy(from: map, editorModel: viewModel)
                }
            }
            .onDisappear {
                viewModel.appeared = false
            }
            .modifier(EditToolBarViewModifier(mapEditController: mapEditController, editorModel: viewModel))
        }
    }
}

private extension MapEditor {
    var overlayMap: some View {
        ZStack(alignment: .topLeading) {
            // Player mode: shown entries → pins → hidden entries (pins appear between layers)
            if viewModel.displayMode == .player {
                drawEntryViews(isShowing: true)
                drawPins
                drawEntryViews(isShowing: false)
            } else {
                drawEntryViews(isShowing: true)
                drawEntryViews(isShowing: false)
                drawPins
            }

            // Pointer pin (game mode)
            if map.pointer.isShown {
                drawPin(id: viewModel.pins.pointer.id)
            }

            // Expanded pin always on top
            if let scalePinId = viewModel.pins.isExpandedId {
                drawPin(id: scalePinId)
            }

            // Edit-mode only overlays
            if viewModel.mapMode == .edit {
                if let editEntry = viewModel.editEntries.entries.first {
                    drawEntryView(entries: viewModel.editEntries, entry: editEntry)
                }

                if viewModel.displayMode == .master || viewModel.displayMode == .reader {
                    drawEntryPins()
                }

                if let magnifyPoint = viewModel.editEntries.selectedNeedleCoordinate {
                    drawCrosshair(location: magnifyPoint)
                        .zIndex(500)
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
}

// MARK: - Drawing MapEntry

extension MapEditor {
    @ViewBuilder
    func drawEntryViews(isShowing: Bool) -> some View {
        ForEach(viewModel.entries.entries.filter { $0.isShown == isShowing && $0.id != viewModel.editEntries.entries.first?.id }) { entry in
            drawEntryView(entries: viewModel.entries, entry: entry)
        }
    }

    func drawEntryView(entries: MapEntryViewerModel, entry: MapEntryModel) -> some View {
        let canActivate = viewModel.displayMode == .master
            && (viewModel.mapMode != .edit || viewModel.editEntries.entries.isEmpty)
        return MapEntryViewer(entry: entry, displayMode: viewModel.displayMode, displayConfig: map.displayConfig, activateGestures: canActivate, mapImage: image) {
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
        .frame(width: entry.width, height: entry.height)
        .offset(x: entry.xOffset, y: entry.yOffset)
    }
}

// MARK: - Drawing Map Pins

extension MapEditor {
    var drawPins: some View {
        ForEach(viewModel.pins.mapPins.filter({ $0.id != viewModel.pins.isExpandedId && (viewModel.displayMode != .player || $0.isShown) })) { pin in
            drawPin(id: pin.id)
        }
    }

    @ViewBuilder
    func drawPin(id: UUID) -> some View {
        if let pin = viewModel.pins.pinPointer(for: id) {
            let scaleFact: CGFloat = viewModel.pins.isExpandedId == id ? 4.0 : 1.0
            let pinSize = pin.size.size * viewModel.pinScale * scaleFact
            let location: CGPoint = pin.location - (pinSize / CGFloat(2.0))
            let canDrag = viewModel.mapMode == .edit
                || viewModel.mapMode == .gameMaster
                || id == viewModel.playerPinId
                || id == map.pointer.id

            MapPinActionView(
                model: viewModel.pins,
                pinId: id,
                layoutDown: true,
                pinSize: pinSize,
                isShown: pin.isShown,
                borderColor: borderColorForPin(position: pin),
                canDrag: canDrag,
                showActions: viewModel.mapMode == .edit
            ) {
                if viewModel.mapMode == .edit {
                    mapEditController.togglePinVisibility(pinId: pin.id, editorModel: viewModel)
                } else if viewModel.mapMode == .gameMaster {
                    guard var updatedPin = viewModel.pins.pinPointer(for: id) else { return }
                    updatedPin.isShown.toggle()
                    viewModel.pins.setPinPointer(updatedPin: updatedPin)
                    map.setPinPointer(updatedPin: updatedPin)
                    if viewModel.isStreaming { viewModel.sendMapUpdates?() }
                }
            } dragEndAction: {
                guard let updatedPin = viewModel.pins.pinPointer(for: pin.id) else { return }
                if map.pointer.id == updatedPin.id {
                    viewModel.updatePointer(location: updatedPin.location, map: map, withOutRelocation: true)
                } else if viewModel.mapMode == .edit {
                    mapEditController.updatePinMove(pin: updatedPin, editorModel: viewModel)
                } else if viewModel.mapMode == .gameMaster || updatedPin.id == viewModel.playerPinId {
                    map[MapPinId.id, updatedPin.id] = updatedPin
                    if let idx = root.gameController.mapGameModel.playerPins.firstIndex(where: { $0.id == updatedPin.id }) {
                        root.gameController.mapGameModel.playerPins[idx] = updatedPin
                    }
                    if viewModel.displayMode == .player || viewModel.isStreaming {
                        viewModel.sendMapUpdates?()
                    }
                }
            }
            .equatable()
            .opacity(viewModel.displayMode == .player ? (pin.isShown ? 1 : 0) : 1)
            .offset(x: location.x, y: location.y)
        }
    }

    func borderColorForPin(position: MapPinModel) -> Color {
        position.location != map.mapPins.first(where: { $0.id == position.id })?.location ? .red : .gray
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
        Image(akImage: image)
            .rotationEffect(Angle(degrees: photoDegrees))
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
        viewModel.pressAction(value)
    }

    func releaseAction(_ value: DragGesture.Value) {
        if viewModel.mapMode == .edit {
            let hasEditableEntry = !viewModel.editEntries.entries.isEmpty
            mapEditController.releaseAction(value, map: map, editorModel: viewModel, hasEditableEntry: hasEditableEntry)
        } else {
            viewModel.updatePointer(location: value.location, map: map)
        }
    }

    func longPressAction(_ value: DragGesture.Value) {}

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
#endif

    func magnifierAction(_ value: CGFloat, isFirst: Bool) {
        viewModel.updateScale(value, updateLast: isFirst)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(MapRootModel.self) var root

    Group {
#if os(macOS)
        MapEditor(editController: root.editController, image: AKImage(named: "photo")!, photoDegrees: 0, map: MapModel.preview, viewMode: .master, containerSize: CGSize(width: 300, height: 800))
#else
        MapEditor(editController: root.editController, image: AKImage(systemName: "photo")!, photoDegrees: 0, map: MapModel.preview, viewMode: .master, containerSize: CGSize(width: 300, height: 800))
#endif
    }
    .onAppear {
        root.editController.setCurrentItem(to: ItemRowTreeModel(itemId: root.itemController.itemDataModel.items[0], typeId: .map))
    }
    .environment(DropPinModel())
}
