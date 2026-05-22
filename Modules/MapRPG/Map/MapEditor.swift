// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

struct MapEditor: View {
    init(editController: EditController, image: AKImage, photoDegrees: Double, map: MapModel, viewMode: MapDisplayMode, tile: MapEntryModel? = nil, isPinEdit: Bool, containerSize: CGSize, closeAction: (() -> Void)? = nil) {
        self.editController = editController
        self.image = image
        self.photoDegrees = photoDegrees
        self.map = map
        self._toolBarModel = State(wrappedValue: EditToolBarModel(mapModel: map, pinScale: map.pinScale, hexScale: map.hexMapScale, hideCloseButton: false))
        self.viewMode = viewMode
        self.tile = tile
        self.isPinEdit = isPinEdit
        self.containerSize = containerSize
        self.closeAction = closeAction
        self.mapEditController = MapEditController(editController: editController)

        self._viewModel = State(wrappedValue: MapEditorModel(map: map, image: image, photoDegrees: photoDegrees, containerSize: containerSize))
    }

    let editController: EditController
    let image: AKImage
    let photoDegrees: Double
    let map: MapModel
    let viewMode: MapDisplayMode
    let tile: MapEntryModel?
    let isPinEdit: Bool
    let containerSize: CGSize
    let closeAction: (() -> Void)?
    let mapEditController: MapEditController

    @State private var toolBarModel: EditToolBarModel
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
#if !os(tvOS)
            .dragTapGesture(isActive: true, pressAction: pressAction(_:), releaseAction: releaseAction(_:), longPressAction: longPressAction(_:), doubleTapAction: doubleTapAction(_:), dragStartAction: dragStartAction(_:), dragAction: dragAction(_:), dragEndAction: dragEndAction(_:), endAction: endAction(_:), magnifierAction: magnifierAction(_:isFirst:))
#endif
            .onChange(of: editController.sheetEditorModel.itemId) {
                viewModel.changeImage(map: map, hexScale: &toolBarModel.hexScale, pinScale: &toolBarModel.pinScale)
            }
            .onChange(of: editController.sheetEditorModel.entryId, initial: true) {
                mapEditController.changeMap(
                    map: map,
                    currentEntryId: editController.sheetEditorModel.entryId,
                    editorModel: viewModel
                )
            }
            .onChange(of: map.mapPins) {
                viewModel.resetPlayerAndPins(newPins: map.mapPins, map: map, pinScale: toolBarModel.pinScale)
                mapEditController.mergeExternalPins(newMap: map, editorModel: viewModel)
            }
            .onChange(of: map.entries) {
                viewModel.resetEntries(newEntries: map.entries, map: map)
                mapEditController.mergeExternalEntries(newMap: map, editorModel: viewModel)
                toolBarModel.isHexMap = mapEditController.isHexMap(editorModel: viewModel)
            }
            .onChange(of: containerSize) {
                viewModel.updateContainerSize(containerSize)
            }
            .onChange(of: dropPinModel.items) {
                dropPin()
            }
            .onAppear {
                viewModel.firstAppear(map: map)
                toolBarModel.displayMode = viewMode
                mapEditController.prepareWorkingCopy(from: map, editorModel: viewModel)
                toolBarModel.isHexMap = mapEditController.isHexMap(editorModel: viewModel)
                toolBarModel.saveAction = {
                    mapEditController.commitChanges(editorModel: viewModel, pinScale: toolBarModel.pinScale)
                }
                toolBarModel.cancelAction = {
                    mapEditController.discardChanges(editorModel: viewModel)
                }
                toolBarModel.addMonstersAction = { entryId, monsters in
                    mapEditController.addMonsters(map: map, entryId: entryId, location: nil, monsters: monsters, number: 1, editorModel: viewModel)
                }
                toolBarModel.toggleHexAction = {
                    mapEditController.toggleHexMap(editorModel: viewModel)
                    toolBarModel.isHexMap = mapEditController.isHexMap(editorModel: viewModel)
                    toolBarModel.hexScale = viewModel.workingCopy?.hexMapScale ?? toolBarModel.hexScale
                }
                toolBarModel.updateHexScaleAction = { scale in
                    mapEditController.updateHexScale(scale, editorModel: viewModel)
                    toolBarModel.isHexMap = mapEditController.isHexMap(editorModel: viewModel)
                }
            }
            .modifier(EditToolBarViewModifier(editController: editController, model: toolBarModel))
        }
    }
}

private extension MapEditor {
    var overlayMap: some View {
        ZStack(alignment: .topLeading) {
            drawEntryViews(isShowing: true)
            drawEntryViews(isShowing: false)

            if let editEntry = viewModel.editEntries.entries.first {
                drawEntryView(entries: viewModel.editEntries, entry: editEntry)
            }

            drawPins

            if let scalePinId = viewModel.pins.isExpandedId {
                drawPin(id: scalePinId)
            }

            if toolBarModel.displayMode == .master || toolBarModel.displayMode == .reader {
                drawEntryPins()
            }

            if let magnifyPoint = viewModel.editEntries.selectedNeedleCoordinate {
                drawCrosshair(location: magnifyPoint)
                    .zIndex(500)
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

        mapEditController.dropPin(
            at: dropPinModel.point,
            map: map,
            monsters: dropPinModel.items,
            editorModel: viewModel
        )

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
        MapEntryViewer(model: entries, entryId: entry.id, displayMode: toolBarModel.displayMode, displayConfig: map.displayConfig, activateGestures: toolBarModel.displayMode == .master && viewModel.editEntries.entries.isEmpty) {
            viewModel.editEntries.addedNewNeedlePoint = nil
            viewModel.editEntries.eaten = true

            guard let mapModel = editController.editModel(for: map.id) else { return }
            mapModel[entry.id] = entries.entry(entry.id)
            editController.save(updated: mapModel, message: String(localized: "update entry", bundle: .module).localizedString)
        } longPressAction: {
            viewModel.editEntries.addedNewNeedlePoint = nil
            viewModel.editEntries.eaten = true

            guard let mapModel = editController.editModel(for: map.id) else { return }
            mapModel.focused(entries.entry(entry.id))
            editController.save(updated: mapModel, message: String(localized: "focus entry", bundle: .module).localizedString)
        }
        .frame(width: entry.width, height: entry.height)
        .offset(x: entry.xOffset, y: entry.yOffset)
    }
}

// MARK: - Drawing Map Pins

extension MapEditor {
    var drawPins: some View {
        ForEach(viewModel.pins.mapPins.filter({ $0.id != viewModel.pins.isExpandedId && (toolBarModel.displayMode != .player || $0.isShown) })) { pin in
            drawPin(id: pin.id)
        }
    }

    @ViewBuilder
    func drawPin(id: UUID) -> some View {
        if let pin = viewModel.pins.pinPointer(for: id) {
            let scaleFact: CGFloat = viewModel.pins.isExpandedId == id ? 4.0 : 1.0
            let pinSize = pin.size.size * toolBarModel.pinScale * scaleFact
            let location: CGPoint = (pin.location) - (pinSize / CGFloat(2.0))

            MapPinActionView(model: viewModel.pins, pinId: id, layoutDown: true, pinSize: pinSize, isShown: pin.isShown, borderColor: borderColorForPin(position: pin), canDrag: true) {
                mapEditController.togglePinVisibility(pinId: pin.id, editorModel: viewModel)
            } dragEndAction: {
                guard let updatedPin = viewModel.pins.pinPointer(for: pin.id) else { return }
                mapEditController.updatePinMove(pin: updatedPin, editorModel: viewModel)
            }
            .equatable()
            .opacity(toolBarModel.displayMode == .player ? (pin.isShown ? 1 : 0) : 1)
            .offset(x: location.x, y: location.y)
        }
    }

    func borderColorForPin(position: MapPinModel) -> Color {
        if position.location != map.mapPins.first(where: { $0.id == position.id })?.location {
            return .red
        }
        return .gray
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
        if origin.y + viewModel.imageModel.offset.y < 0 {
            origin.y = point.y + 30
        }
        if origin.x + viewModel.imageModel.offset.x < 0 {
            origin.x = point.x
        }
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

    var crosshairSize: CGSize {
        CGSize(width: 160, height: 160)
    }

    var crosshairSizeScaled: CGSize {
        crosshairSize / viewModel.imageModel.scale
    }
}

// MARK: - Gesture Handlers

private extension MapEditor {
#if !os(tvOS)
    func pressAction(_ value: DragGesture.Value) {
        viewModel.pressAction(value)
    }

    func releaseAction(_ value: DragGesture.Value) {
        let hasEditableEntry = tile != nil || !viewModel.editEntries.entries.isEmpty
        mapEditController.releaseAction(value, map: map, editorModel: viewModel, hasEditableEntry: hasEditableEntry)
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
        MapEditor(editController: root.editController, image: AKImage(named: "photo")!, photoDegrees: 0, map: MapModel.preview, viewMode: .master, tile: nil, isPinEdit: false, containerSize: CGSize(width: 300, height: 800))
#else
        MapEditor(editController: root.editController, image: AKImage(systemName: "photo")!, photoDegrees: 0, map: MapModel.preview, viewMode: .master, tile: nil, isPinEdit: false, containerSize: CGSize(width: 300, height: 800))
#endif
    }
    .onAppear {
        root.editController.setCurrentItem(to: ItemRowTreeModel(itemId: root.itemController.itemDataModel.items[0], typeId: .map))
    }
    .environment(DropPinModel())
}
