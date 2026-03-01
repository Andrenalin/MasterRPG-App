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
        self.toolBarModel = EditToolBarModel(mapModel: map, pinScale: map.pinScale, hexScale: map.hexMapScale, hideCloseButton: false)
        self.viewMode = viewMode
        self.tile = tile
        self.isPinEdit = isPinEdit
        self.containerSize = containerSize
        self.closeAction = closeAction
        
        toolBarModel.displayMode = viewMode
        self._model = State(wrappedValue: ImageViewerModel(offset: .zero, scale: 1))
    }
    
    let editController: EditController
    let image: AKImage
    let photoDegrees: Double
    let map: MapModel
    let toolBarModel: EditToolBarModel
    let viewMode: MapDisplayMode
    let tile: MapEntryModel?
    let isPinEdit: Bool
    let containerSize: CGSize
    let closeAction: (() -> Void)?
    
    @State private var model: ImageViewerModel
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(MapRootModel.self) private var root
    @Environment(DropPinModel.self) private var dropPinModel
    
    @State private var pins: MapPinViewModel = MapPinViewModel(mapPins: [], pointer: .empty)
    @State private var entries: MapEntryViewerModel = MapEntryViewerModel(mapId: UUID(), entries: [])
    @State private var editEntries: MapEntryViewerModel = MapEntryViewerModel(mapId: UUID(), entries: [])
    @State private var focusId: MapEntryModel.ID? = nil
    @State private var appeared = false
    
    enum DraggingType: Hashable {
        case nothing
        case image
    }
    
    @State private var isDragging: DraggingType = .nothing
    @State private var isTapping: DraggingType = .nothing
    
    var body: some View {
        ManagedNavigationStack(name: "MapEditor") { navigator in
            ZStack(alignment: .topLeading) {
                Color.clear
                
                Image(akImage: image)
                    .overlay(alignment: .topLeading) {
                        overlayMap
                    }
                    .scaleEffect(model.scale)
                    .rotationEffect(Angle(degrees: photoDegrees))
                    .offset(x: model.offset.x, y: model.offset.y)
                    .contentMargins(.all, 50)
                    .frame(width: currentSize.width, height: currentSize.height)

            }
            .frame(width: containerSize.width, height: containerSize.height, alignment: .topLeading)
            .background {
                Rectangle().fill(Color.black.gradient)
                    .ignoresSafeArea()
            }
#if !os(tvOS)
            .dragTapGesture(isActive: true, pressAction: pressAction(_:), releaseAction: releaseAction(_:), longPressAction: longPressAction(_:), doubleTapAction: doubleTapAction(_:), dragStartAction: dragStartAction(_:), dragAction: dragAction(_:), dragEndAction: dragEndAction(_:), endAction: endAction(_:), magnifierAction: magnifierAction(_:isFirst:))
#endif
            .onChange(of: editController.editorModel.currentItemId) {
                changeImage()
            }
            .onChange(of: editController.editorModel.currentEntryId, initial: true) {
                changeMap()
            }
            .onChange(of: map.mapPins) {
                resetPlayerAndPins(newPins: map.mapPins)
            }
            .onChange(of: map.entries) {
                resetEntries(newEntries: map.entries)
            }
            .onChange(of: pins.mapPins) {
                resetPinsToMap(pins: pins.mapPins)
            }
            .onChange(of: toolBarModel.hexScale) {
                guard toolBarModel.hexScale != 0 && toolBarModel.hexScale != map.hexMapScale else { return }
                editController.createHexMap(model: map, hexMapScale: toolBarModel.hexScale)
            }
            .onChange(of: containerSize) {
                resetZoom()
            }
            .onChange(of: dropPinModel.items) {
                dropPin()
            }
            .onAppear {
                firstAppear()
            }
            .onDisappear() {
                saveChanges()
            }
            .modifier(EditToolBarViewModifier(editController: editController, model: toolBarModel))
       }
    }
}

private extension MapEditor {
    func saveChanges() {
        guard let model = editController.editModel(for: map.id) else { return }
        model.pinScale <=> toolBarModel.pinScale
        model.mapPins <=> pins.mapPins
        editController.save(updated: model, message: String(localized: "map updated").localizedString)
    }
    
    var overlayMap: some View {
        ZStack(alignment: .topLeading) {
            drawEntryViews(isShowing: true)
            drawEntryViews(isShowing: false)
            
            if let editEntry = editEntries.entries.first {
                drawEntryView(entries: editEntries, entry: editEntry)
            }
            
            drawPins
            
            if let scalePinId = pins.isExpandedId {
                drawPin(id: scalePinId)
            }
            
            if toolBarModel.displayMode == .master || toolBarModel.displayMode == .reader {
                drawEntryPins()
            }
            
            if let magnifyPoint = editEntries.selectedNeedleCoordinate {
                drawCrosshair(location: magnifyPoint)
                    .zIndex(500)
            }
        }
    }
    
    func firstAppear() {
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            appeared = true
            resetEntries(newEntries: map.entries)
            resetPlayerAndPins(newPins: map.mapPins)
            withAnimation {
                if focusId == nil {
                    resetZoom()
                } else {
                    focusedMap()
                }
            }
        }
    }

    func changeImage() {
        Task {
            toolBarModel.hexScale = map.hexMapScale
            toolBarModel.pinScale = map.pinScale

            try? await Task.sleep(for: .milliseconds(150))
            changeMap()
        }
    }

    func changeMap() {
        let currentEntryId = editController.editorModel.currentEntryId
        if currentEntryId != editEntries.entries.first?.id {
            if map.id == entries.mapId && !editEntries.entries.isEmpty {
                let mapEdit = map.copy()
                for entry in editEntries.entries {
                    entries.setEntry(entry: entry)
                }
                mapEdit.entries = entries.entries
                editController.save(updated: mapEdit, message: String(localized: "Change entry coordinates").localizedString)
            }
            if let currentEntryId {
                let entry = map[currentEntryId]
                withAnimation(.bouncy) {
                    editEntries.resetEntries(mapId: map.id, entries: [entry])
                }
            } else {
                withAnimation(.bouncy) {
                    editEntries.resetEntries(mapId: map.id, entries: [])
                }
            }
        }
        isDragging = .nothing
        isTapping = .nothing
        editEntries.eaten = false
        editEntries.addedNewNeedlePoint = nil
        if appeared {
            resetZoom()
        }
    }
    
    @ViewBuilder
    var backColor: some View {
        colorScheme == .dark ? Color.black.ignoresSafeArea() : Color.white.ignoresSafeArea()
    }
    
    var loupeSize: CGFloat {
        12 / MapEditor.imageSize(image, degrees: photoDegrees).width
    }

    func resetPlayerAndPins(newPins: [MapPinModel]) {
        var modified = newPins
        if let entry = map.entries.first {
            var leftCenter = CGPoint(x: entry.xOffset + entry.size.width / 4, y: entry.yOffset + entry.size.height / 2)
            modified = newPins.map { pin in
                var changedPin = pin
                if changedPin.location == .zero {
                    changedPin.location = leftCenter
                    leftCenter = leftCenter + changedPin.size.size.width * toolBarModel.pinScale + 5
                }
                return changedPin
            }
        }
        
        guard pins.mapPins != modified else { return }
        withAnimation(.bouncy) {
            pins.mapPins = modified
        }
    }
    
    func resetEntries(newEntries: [MapEntryModel]) {
        if let editEntry = editEntries.entries.first, let index = newEntries.firstIndex(where: { $0.id == editEntry.id }), editEntry != newEntries[index] {
            withAnimation(.bouncy) {
                editEntries.resetEntries(mapId: map.id, entries: [newEntries[index]])
            }
        }
        
        guard entries.entries != newEntries else { return }
        
        withAnimation(.bouncy) {
            entries.resetEntries(mapId: map.id, entries: newEntries)
        }
        
        let focus = newEntries.first(where: { $0.focused })?.id
        if focus != focusId {
            focusId = focus
            focusedMap()
        }
    }
    
    func resetPinsToMap(pins: [MapPinModel]) {
        map.mapPins = pins
    }
    
    func dropPin() {
        guard !dropPinModel.items.isEmpty else { return }
        
        let location = (dropPinModel.point - model.offset) / model.scale
        let entry = entry(for: location)
        
        withAnimation(.bouncy) {
            editController.addMonsters(map: map, entryId: entry?.id, location: location, monsters: dropPinModel.items, number: 1)
        }
        dropPinModel.items = []
        dropPinModel.isTarget = false
    }
}

// MARK: - Drawing MapEntry

extension MapEditor {
    @ViewBuilder
    func drawEntryViews(isShowing: Bool) -> some View {
        ForEach(entries.entries.filter { $0.isShown == isShowing && $0.id != editEntries.entries.first?.id }) {  entry in
            drawEntryView(entries: entries, entry: entry)
        }
    }
    
    func drawEntryView(entries: MapEntryViewerModel, entry: MapEntryModel) -> some View {
        MapEntryViewer(model: entries, entryId: entry.id, displayMode: toolBarModel.displayMode, displayConfig: map.displayConfig, activateGestures: toolBarModel.displayMode == .master && editEntries.entries.isEmpty) {
            editEntries.addedNewNeedlePoint = nil
            editEntries.eaten = true
            map[entry.id] = entries.entry(entry.id)
        } longPressAction: {
            editEntries.addedNewNeedlePoint = nil
            editEntries.eaten = true
            map.focused(entries.entry(entry.id))
        }
        .frame(width: entry.width, height: entry.height)
        .offset(x: entry.xOffset, y: entry.yOffset)
    }
    
    func subPath(for entry: MapEntryModel) -> Path {
        Path { path in
            guard let firstPoint = entry.coordinates.first else {
                return
            }
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
}

// MARK: - Drawing Map Pins

extension MapEditor {
    var drawPins: some View {
        ForEach(pins.mapPins.filter({ $0.id != pins.isExpandedId && (toolBarModel.displayMode != .player || $0.isShown) })) { pin in
            drawPin(id: pin.id)
        }
    }
    
    @ViewBuilder
    func drawPin(id: UUID) -> some View {
        if let pin = pins.pinPointer(for: id) {
            let scaleFact: CGFloat = pins.isExpandedId == id ? 4.0 : 1.0
            let pinSize = pin.size.size * toolBarModel.pinScale * scaleFact
            let location: CGPoint = (pin.location) - (pinSize / CGFloat(2.0))
            
            MapPinActionView(model: pins, pinId: id, layoutDown: true, pinSize: pinSize, isShown: pin.isShown, borderColor: borderColorForPin(position: pin), canDrag: true) {
                    guard var updatedPin = pins.pinPointer(for: pin.id) else { return }
                    updatedPin.isShown.toggle()
                    pins.setPinPointer(updatedPin: updatedPin)
                    map.setPinPointer(updatedPin: updatedPin)
            } dragEndAction: {
                    guard let updatedPin = pins.pinPointer(for: pin.id) else { return }
                    map.setPinPointer(updatedPin: updatedPin)
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

// MARK: - MApEntry Pins

private extension MapEditor {
    @ViewBuilder
    func drawEntryPins() -> some View {
        if let entry = editEntries.entries.first {
            ForEach(entry.coordinates.indexed(), id: \.index) { (index, point) in
                NeedleMapPin(entries: editEntries, entryId: entry.id, index: index) {
                    var updatedEntry = editEntries.entry(entry.id)
                    let next = index + 1 < updatedEntry.coordinates.count ? index + 1 : 0
                    var nextPoint = updatedEntry.coordinates[next]
                    if next == 0 {
                        nextPoint = nextPoint + CGPoint(x: 50, y: 50)
                    } else {
                        nextPoint = nextPoint - (nextPoint - updatedEntry.coordinates[index]) / 2
                    }
                    updatedEntry.coordinates.insert(nextPoint, at: next)
                    map[updatedEntry.id] = updatedEntry
                } removeAction: {
                    var updatedEntry = editEntries.entry(entry.id)
                    if index >= 0 && index < updatedEntry.coordinates.count {
                        updatedEntry.coordinates.remove(at: index)
                        map[updatedEntry.id] = updatedEntry
                    }
                } dragEndAction: {
                    map[entry.id] = editEntries.entry(entry.id)
                }
                .offset(x: point.x - 22, y: point.y - 110)
            }
        }
    }
}

// MARK: - Magnifer glass with Crosshair

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
        if origin.y + model.offset.y < 0 {
            origin.y = point.y + 30
        }
        if origin.x + model.offset.x < 0 {
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
            .offset(imageOffset())
            .scaleEffect(model.scale * 3)
            .frame(width: crosshairSize.width, height: crosshairSize.height)
            .clipShape(Circle())
    }

    var crosshairSize: CGSize {
        CGSize(width: 160, height: 160)
    }

    var crosshairSizeScaled: CGSize {
        crosshairSize / model.scale
    }

    func imageOffset() -> CGSize {
        guard let location = editEntries.selectedNeedleCoordinate else { return .zero }

        let size = MapEditor.imageSize(image, degrees: photoDegrees)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        return CGSize(width: -1 * (location.x - center.x), height: -1 * (location.y - center.y))
    }
}

// MARK: - Zooming

private extension MapEditor {
    static func zoomToFit(with size: CGSize, image: AKImage, degrees: Double) -> (CGFloat, CGPoint) {
        let scale = normScale(screenSize: size, image: image, degrees: degrees)
        let imgSize = imageSize(image, degrees: degrees)
        let x = (size.width - imgSize.width * scale) / 2.0
        let y = (size.height - imgSize.height * scale) / 2.0
        let offset = CGPoint(x: x, y: y)
        return (scale, offset)
    }
    
    static func normScale(screenSize: CGSize, image: AKImage, degrees: Double) -> CGFloat {
        let size = imageSize(image, degrees: degrees)
        let wScale = screenSize.width / size.width
        let hScale = screenSize.height / size.height
        return min(wScale, hScale)
    }
    
    static func imageSize(_ image: AKImage, degrees: Double) -> CGSize {
        (degrees == 0 || degrees == 180) ? image.fixedSize : CGSize(width: image.size.height, height: image.size.width)
    }
    
    var currentSize: CGSize {
        MapEditor.imageSize(image, degrees: photoDegrees) * model.scale
    }
    
    func resetZoom() {
        let (newScale, newOffset): (CGFloat, CGPoint)
        (newScale, newOffset) = MapEditor.zoomToFit(with: containerSize, image: image, degrees: photoDegrees)
        model.normScale = newScale
        zoom(scale: newScale, at: newOffset)
    }
    
    func zooming(on location: CGPoint) {
        let (newScale, newOffset): (CGFloat, CGPoint)
        if model.scale != model.normScale {
            (newScale, newOffset) = MapEditor.zoomToFit(with: containerSize, image: image, degrees: photoDegrees )
        } else {
            (newScale, newOffset) = zoomIn(at: location)
        }
        zoom(scale: newScale, at: newOffset)
    }
    
    func zoom(scale: CGFloat, at offset: CGPoint) {
        withAnimation {
            model.scale = scale
            model.lastScale = model.scale
            model.offset = offset
            model.lastOffset = model.offset
        }
    }
    
    func zoomIn(at point: CGPoint) -> (CGFloat, CGPoint) {
        let newScale = max(0.1, model.scale * 4)
        let offPoint = (point - model.offset) / model.scale
        
        updateScale(newScale, updateLast: false)
        
        let pswidth = (containerSize.width / newScale) / 2
        let psHeight = (containerSize.height / newScale) / 2
        let offset = CGPoint(x: -1 * (offPoint.x - pswidth) * model.scale, y: -1 * (offPoint.y - psHeight) * model.scale)
        return (newScale, offset)
    }
    
    func focusedMap() {
        if let focusId {
            let focusMap = map[focusId]
            let ss = focusMap.size
            let sw = containerSize.width / (ss.width + 50)
            let sh = containerSize.height / (ss.height + 50)
            let newScale = min(sw, sh)
            withAnimation {
                model.scale = max(0.1, newScale)
                model.lastScale = model.scale
                model.offset = CGPoint(x: -1 * (focusMap.xOffset - 25) * model.scale, y: -1 * (focusMap.yOffset - 25) * model.scale)
                model.lastOffset = model.offset
            }
        } else {
            zooming(on: .zero)
        }
    }
}

// MARK: - Gesture Magnifyer

private extension MapEditor {
    func updateScale(_ value: CGFloat, updateLast: Bool) {
        if updateLast {
            model.lastScale = value
        }
        let delta = value / model.lastScale
        let newScale = model.scale * delta
        if newScale < 0.1 {
            return
        }
        
        let imgSize = MapEditor.imageSize(image, degrees: photoDegrees)
        let scaleDiff = (newScale - model.scale) / 2
        let imgOff = imgSize * scaleDiff
        let newOffsetNew = CGPoint(x: -imgOff.width, y: -imgOff.height)
        
        model.lastScale = value
        model.scale = newScale
        updateOffset(with: newOffsetNew, firstOffset: model.offset)
    }
}

// MARK: - Gesture Drag

private extension MapEditor {
    func dragPoint(location: CGPoint) -> DraggingType {
        .image
    }
    
    func updateOffset(with newLocation: CGPoint, firstOffset: CGPoint) {
        let imgSize = MapEditor.imageSize(image, degrees: photoDegrees)
        let offX = max(300, (containerSize.width - imgSize.width * model.scale) / 2)
        let offY = max(300, (containerSize.height - imgSize.height * model.scale) / 2)
        let minX = containerSize.width - (imgSize.width * model.scale) - offX
        let minY = containerSize.height - (imgSize.height * model.scale) - offX
        var newOffset = firstOffset + newLocation
        if newOffset.x < minX {
            newOffset.x = minX
        }
        if newOffset.x > offX {
            newOffset.x = offX
        }
        if newOffset.y < minY {
            newOffset.y = minY
        }
        if newOffset.y > offY {
            newOffset.y = offY
        }
        model.lastOffset = firstOffset
        model.offset = newOffset
    }
}

// MARK: - Tap

private extension MapEditor {
    func onTapped(with location: CGPoint) {
        guard tile != nil || !editEntries.entries.isEmpty else { return }
        let roomPin = (location - model.offset) / model.scale
        guard editEntries.eaten == false && editEntries.addedNewNeedlePoint == nil else { return }

        editEntries.addedNewNeedlePoint = roomPin
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard let point = editEntries.addedNewNeedlePoint, var updatedEntry = editEntries.entries.first else { return }
            editEntries.addedNewNeedlePoint = nil
            updatedEntry.coordinates.append(point)
            map[updatedEntry.id] = updatedEntry // editController.model <- is this working?
        }
    }
}

// MARK: - Gesture Double Tap

private extension MapEditor {
    func onDoubleTapped(with location: CGPoint) {
        if editEntries.eaten  {
            editEntries.eaten = false
            isTapping = .nothing
        } else {
            zooming(on: location)
        }
    }

    func entry(for location: CGPoint) -> MapEntryModel? {
        entries.entries.last(where: { entry -> Bool in
            let path = subPath(for: entry)
            return path.contains(location)
        })
    }
}

// MARK: - Gesture & updates

private extension MapEditor {
#if !os(tvOS)
    func pressAction(_ value: DragGesture.Value) {
        isTapping = dragPoint(location: value.location)
    }
    
    func releaseAction(_ value: DragGesture.Value) {
        guard isTapping != .nothing else { return }
        onTapped(with: value.location)
    }
    
    func longPressAction(_ value: DragGesture.Value) {}
    
    func doubleTapAction(_ value: DragGesture.Value) {
        onDoubleTapped(with: value.location)
    }
    
    func dragStartAction(_ value: DragGesture.Value) {
        isDragging = dragPoint(location: value.startLocation)
        isTapping = .nothing
        model.lastOffset = model.offset
    }
    
    func dragAction(_ value: DragGesture.Value) {
        switch isDragging {
        case .image:
            updateOffset(with: value.location - value.startLocation, firstOffset: model.lastOffset)
        case .nothing:
            break
        }
    }
    
    func dragEndAction(_: DragGesture.Value) {}
    
    func endAction(_: DragGesture.Value) {
        isDragging = .nothing
        isTapping = .nothing
    }
#endif
    
    func magnifierAction(_ value: CGFloat, isFirst: Bool) {
        updateScale(value, updateLast: isFirst)
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
