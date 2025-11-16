// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct MapViewer: View {
    init(image: AKImage, photoDegrees: Double, map: MapModel, toolBarModel: GameToolBarModel, playerPinId: UUID?, mapMode: MapMode, containerSize: CGSize, focusedId: MapEntryModel.ID? = nil, sendMapUpdates: @escaping () -> Void, focused: @escaping () -> Void) {
        self.image = image
        self.photoDegrees = photoDegrees
        self.map = map
        self.toolBarModel = toolBarModel
        self.playerPinId = playerPinId
        self.mapMode = mapMode
        self.containerSize = containerSize
        self.focusedId = focusedId
        self.sendMapUpdates = sendMapUpdates
        self.focused = focused
        
        _focusId = State(wrappedValue: focusedId)
        _entries = State(wrappedValue: MapEntryViewerModel(entries: map.entries))
        _appeared = State(wrappedValue: false)

        self._model = State(wrappedValue: ImageViewerModel(offset: .zero, scale: 1))

        resetPlayerAndPins(newPins: map.mapPins)
    }
    
    enum MapMode {
        case gameMaster
        case player
        case viewer
    }
    
    let image: AKImage
    let photoDegrees: Double
    let map: MapModel
    let toolBarModel: GameToolBarModel
    let playerPinId: UUID?
    let mapMode: MapMode
    let containerSize: CGSize
    let focusedId: MapEntryModel.ID?
    let sendMapUpdates: () -> Void
    let focused: () -> Void
    
    @State private var model: ImageViewerModel
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(MapRootModel.self) private var root
    @Environment(DropPinModel.self) private var dropPinModel
    
    @State private var pins: MapPinViewModel = MapPinViewModel(mapPins: [], pointer: .empty)
    @State private var entries: MapEntryViewerModel
    @State private var scalePinId: UUID?
    @State private var focusId: MapEntryModel.ID?
    @State private var appeared: Bool

    var body: some View {
        //let _ = Self._printChanges()

        ZStack(alignment: .topLeading) {
            backColor
            
            Image(akImage: image)
                .overlay(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        if toolBarModel.displayMode == .player {
                            drawEntryViews(isShowing: true)
                            
                            drawPins
                            
                            drawEntryViews(isShowing: false)
                        } else {
                            drawEntryViews(isShowing: true)
                            drawEntryViews(isShowing: false)
                            
                            drawPins
                        }
                        
                        if let scalePinId {
                            drawPin(id: scalePinId)
                        }
                        if map.pointer.isShown {
                            drawPin(id: pins.pointer.id)
                        }
                    }
                }
                .scaleEffect(model.scale)
                .rotationEffect(Angle(degrees: photoDegrees))
                .offset(x: model.offset.x, y: model.offset.y)
                .contentMargins(.all, 50)
                .frame(width: currentSize.width, height: currentSize.height)
        }
        .frame(width: containerSize.width, height: containerSize.height, alignment: .topLeading)
#if !os(tvOS)
        .dragTapGesture(isActive: mapMode != .viewer, pressAction: pressAction(_:), releaseAction: releaseAction(_:), longPressAction: longPressAction(_:), doubleTapAction: doubleTapAction(_:), dragStartAction: dragStartAction(_:), dragAction: dragAction(_:), dragEndAction: dragEndAction(_:), endAction: endAction(_:), magnifierAction: magnifierAction(_:isFirst:))
#endif
        .background(backColor)
        .overlay {
            backColor.opacity(appeared ? 0 : 1)
        }
        .onChange(of: map.pointer) {
            resetPointer()
        }
        .onChange(of: map.mapPins) {
            resetPlayerAndPins(newPins: map.mapPins)
        }
        .onChange(of: map.entries) {
            resetEntries(newEntries: map.entries)
        }
        .onChange(of: toolBarModel.hexScale) {
            guard toolBarModel.hexScale != 0 && toolBarModel.hexScale != map.hexMapScale else { return }
            root.editController(type: .main).createHexMap(model: map, hexMapScale: toolBarModel.hexScale)
        }
        .onChange(of: toolBarModel.pinScale) {
            map.pinScale = toolBarModel.pinScale
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
        .onDisappear {
            appeared = false
        }
    }
}

extension MapViewer {
    func firstAppear() {
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation {
                if focusId == nil {
                    resetZoom()
                } else {
                    focusedMap()
                }
            }
            appeared = true
        }
    }

    @ViewBuilder
    var backColor: some View {
        colorScheme == .dark ? Color.black.ignoresSafeArea() : Color.white.ignoresSafeArea()
    }

    func resetEntries(newEntries: [MapEntryModel]) {
        guard entries.entries != newEntries else { return }

        withAnimation(.bouncy) {
            entries.entries = newEntries
        }

        let focus = newEntries.first(where: { $0.focused })?.id
        if focus != focusId {
            focusId = focus
            focusedMap()
        }
    }
    
    func resetPlayerAndPins(newPins: [MapPinModel]) {
        var modified = newPins
        if let entry = map.entries.first {
            var leftCenter = CGPoint(x: entry.xOffset + entry.size.width / 4, y: entry.yOffset + entry.size.height / 2)
            modified = newPins.map { pin in
                var changedPin = pin
                if changedPin.location == .zero {
                    changedPin.location = leftCenter
                    leftCenter = leftCenter + changedPin.size.size.width * map.pinScale + 5
                }
                return changedPin
            }
        }
        resetPointer()
        guard pins.mapPins != modified else { return }
        if appeared {
            withAnimation(.bouncy) {
                pins.mapPins = modified
            }
        } else {
            pins.mapPins = modified
        }
    }
    
    func resetPointer() {
        if pins.pointer != map.pointer {
            if appeared {
                withAnimation(.bouncy) {
                    pins.pointer = map.pointer
                }
            } else {
                pins.pointer = map.pointer
            }
        }
    }
    
    func dropPin() {
        guard !dropPinModel.items.isEmpty else { return }
        
        let location = (dropPinModel.point - model.offset) / model.scale
        let entry = entry(for: location)
        
        withAnimation(.bouncy) {
            root.editController(type: .main).addMonsters(map: map, entryId: entry?.id, location: location, monsters: dropPinModel.items, number: 1)
        }
        dropPinModel.items = []
        dropPinModel.isTarget = false
    }
}

// MARK: - Drawing MapEntry

extension MapViewer {
    @ViewBuilder
    func drawEntryViews(isShowing: Bool) -> some View {
        ForEach(entries.entries.filter { $0.isShown == isShowing }, id: \.id) { entry in
            MapEntryViewer(model: entries, entryId: entry.id, displayMode: toolBarModel.displayMode, displayConfig: map.displayConfig, activateGestures: toolBarModel.displayMode == .master) {
                map[entry.id] = entries.entry(entry.id)
                if toolBarModel.isStreaming {
                    sendMapUpdates()
                }
            } longPressAction: {
                map.focused(entries.entry(entry.id))
                focused()
            }
            .frame(width: entry.width, height: entry.height)
            .offset(x: entry.xOffset, y: entry.yOffset)
        }
    }
}

// MARK: - Drawing Map Pins

extension MapViewer {
    var drawPins: some View {
        ForEach(pins.mapPins.filter({ $0.id != scalePinId && (toolBarModel.displayMode != .player || $0.isShown) })) { pin in
            drawPin(id: pin.id)
        }
    }
    
    @ViewBuilder
    func drawPin(id: UUID) -> some View {
        let pin = pins.pinPointer(for: id) ?? .empty(id)
        let scaleFact: CGFloat = scalePinId == id ? 4.0 : 1.0
        let pinSize = pin.size.size * map.pinScale * scaleFact
        let location: CGPoint = (pin.location) - (pinSize / CGFloat(2.0))
        
        MapPinView(model: pins, pinId: id, pinSize: pinSize, isShown: pin.isShown, borderColor: borderColorForPin(position: pin), canDrag: mapMode == .gameMaster || pin.id == playerPinId || pin.id == map.pointer.id) {
            scalePinId = scalePinId == pin.id ? nil : pin.id
        } doubleTapAction: {
            if mapMode == .gameMaster {
                guard var updatedPin = pins.pinPointer(for: pin.id) else { return }
                updatedPin.isShown.toggle()
                pins.setPinPointer(updatedPin: updatedPin)
                map.setPinPointer(updatedPin: updatedPin)
                if toolBarModel.isStreaming {
                    sendMapUpdates()
                }
            }
        } dragEndAction: {
            guard let updatedPin = pins.pinPointer(for: pin.id) else { return }
            if map.pointer.id == updatedPin.id {
                updatePointer(location: updatedPin.location, withOutRelocation: true)
            } else {
                if mapMode == .gameMaster || updatedPin.id == playerPinId {
                    updateMap(pin: updatedPin)
                    if toolBarModel.displayMode == .player || toolBarModel.isStreaming {
                        sendMapUpdates()
                    }
                }
            }
        }
        .opacity(toolBarModel.displayMode == .player ? (pin.isShown ? 1 : 0) : 1)
        .offset(x: location.x, y: location.y)
    }
    
    func borderColorForPin(position: MapPinModel) -> Color {
        if position.location != map.mapPins.first(where: { $0.id == position.id })?.location {
            return .red
        }
        return .gray
    }
        
    func updateMap(pin: MapPinModel) {
        map[MapPinId.id, pin.id] = pin
        if let playerIndex = root.gameController.mapGameModel.playerPins.firstIndex(where: { $0.id == pin.id }) {
            root.gameController.mapGameModel.playerPins[playerIndex] = pin
        }
    }
}

// MARK: - Pointer

private extension MapViewer {
    func updatePointer(location: CGPoint, withOutRelocation: Bool = false) {
        if map.pointer.isShown || toolBarModel.isPointing {
            if withOutRelocation {
                map.pointer.location = location
            } else {
                map.pointer.location = (location - model.offset) / model.scale
                pins.setPinPointer(updatedPin: map.pointer)
            }
            if mapMode == .gameMaster {
                map.pointer.isShown <=> toolBarModel.isPointing
                pins.setPinPointer(updatedPin: map.pointer)
            }
            sendMapUpdates()
        }
    }
}

// MARK: - Zooming

private extension MapViewer {
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
        MapViewer.imageSize(image, degrees: photoDegrees) * model.scale
    }
    
    func resetZoom() {
        let (newScale, newOffset): (CGFloat, CGPoint)
        (newScale, newOffset) = MapViewer.zoomToFit(with: containerSize, image: image, degrees: photoDegrees)
        model.normScale = newScale
        zoom(scale: newScale, at: newOffset)
    }
        
    func zooming(on location: CGPoint) {
        let (newScale, newOffset): (CGFloat, CGPoint)
        if model.scale != model.normScale {
            (newScale, newOffset) = MapViewer.zoomToFit(with: containerSize, image: image, degrees: photoDegrees)
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

private extension MapViewer {
    func updateScale(_ value: CGFloat, updateLast: Bool) {
        if updateLast {
            model.lastScale = value
        }
        let delta = value / model.lastScale
        let newScale = model.scale * delta
        if newScale < 0.1 {
            return
        }
        
        let imgSize = MapViewer.imageSize(image, degrees: photoDegrees)
        let scaleDiff = (newScale - model.scale) / 2
        let imgOff = imgSize * scaleDiff
        let newOffsetNew = CGPoint(x: -imgOff.width, y: -imgOff.height)
        
        model.lastScale = value
        model.scale = newScale
        updateOffset(with: newOffsetNew, firstOffset: model.offset)
    }
}

// MARK: - Gesture Drag

private extension MapViewer {
    func updateOffset(with newLocation: CGPoint, firstOffset: CGPoint) {
        let imgSize = MapViewer.imageSize(image, degrees: photoDegrees)
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

// MARK: - Gesture Double Tap

private extension MapViewer {
    func onDoubleTapped(with location: CGPoint) {
        //zooming(on: location)
    }
    
    func entry(for location: CGPoint) -> MapEntryModel? {
        map.entries.last(where: { entry -> Bool in
            let path = subPath(for: entry)
            return path.contains(location)
        })
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

// MARK: - Gesture & updates

private extension MapViewer {
#if !os(tvOS)
    func pressAction(_ value: DragGesture.Value) {}
    
    func releaseAction(_ value: DragGesture.Value) {
        updatePointer(location: value.location)
    }
    
    func longPressAction(_ value: DragGesture.Value) {}
    
    func doubleTapAction(_ value: DragGesture.Value) {
        onDoubleTapped(with: value.location)
    }
    
    func dragStartAction(_ value: DragGesture.Value) {
        model.lastOffset = model.offset
    }
    
    func dragAction(_ value: DragGesture.Value) {
        updateOffset(with: value.location - value.startLocation, firstOffset: model.lastOffset)
    }
    
    func dragEndAction(_: DragGesture.Value) {}
    
    func endAction(_: DragGesture.Value) {}
#endif
    
    func magnifierAction(_ value: CGFloat, isFirst: Bool) {
        updateScale(value, updateLast: isFirst)
    }
}

@Observable
final class ImageViewerModel {
    init(offset: CGPoint = .zero, scale: CGFloat = 1) {
        self.offset = offset
        self.lastOffset = offset
        self.scale = scale
        self.lastScale = scale
        normScale = scale
    }
    
    var offset: CGPoint
    var lastOffset: CGPoint
    var scale: CGFloat
    var lastScale: CGFloat
    
    var normScale: CGFloat
}

#Preview {
    Group {
#if os(macOS)
        MapViewer(image: AKImage(named: "photo")!, photoDegrees: 0, map: MapModel.preview, toolBarModel: GameToolBarModel(), playerPinId: nil, mapMode: .gameMaster, containerSize: CGSize(width: 300, height: 800), focusedId: nil) {
        } focused: {}
#else
        MapViewer(image: AKImage(systemName: "photo")!, photoDegrees: 0, map: MapModel.preview, toolBarModel: GameToolBarModel(), playerPinId: nil, mapMode: .gameMaster, containerSize: CGSize(width: 300, height: 800), focusedId: nil) {
        } focused: {}
#endif
    }
    .environment(MapRootModel.preview)
    .environment(DropPinModel())
}
