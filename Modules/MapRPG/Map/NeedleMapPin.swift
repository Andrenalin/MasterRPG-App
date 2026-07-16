// @copyright André Trettin

import CoreRPG
import SwiftUI

struct NeedleMapPin: View {
    let entries: MapEntryViewerModel
    let entryId: UUID
    let index: Int
    let map: MapModel
    let mapEditController: MapEditController
    let coordinatesChanged: ([CGPoint]) -> Void
    let usesGlassEffects: Bool

    init(
        entries: MapEntryViewerModel,
        entryId: UUID,
        index: Int,
        map: MapModel,
        mapEditController: MapEditController,
        coordinatesChanged: @escaping ([CGPoint]) -> Void = { _ in },
        usesGlassEffects: Bool = true
    ) {
        self.entries = entries
        self.entryId = entryId
        self.index = index
        self.map = map
        self.mapEditController = mapEditController
        self.coordinatesChanged = coordinatesChanged
        self.usesGlassEffects = usesGlassEffects
    }

    @Namespace var glassNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragStartCoordinate: CGPoint?

    private var isSelected: Bool {
        entries.isSelected(index: index)
    }

    var coordinate: CGPoint {
        let entry = entries.entry(entryId)
        guard index >= 0 && index < entry.coordinates.count else { return .zero }
        return entry.coordinates[index]
    }

    var body: some View {
        needleView
    }

    var actionButtons: some View {
        ZStack {
            button(type: .remove)
                .zIndex(110)
            button(type: .add)
                .zIndex(110)

            Color.clear
                .frame(width: 22, height: 22)
                .allowsHitTesting(false)
#if !os(visionOS)
                .applyIf(usesGlassEffects) {
                    $0.glassEffectID("menu", in: glassNamespace)
                }
#endif
        }
    }

    private func button(type: NeedleMapPinButtonType) -> some View {
        Button {
            switch type {
            case .remove:
                removePin()
            case .add:
                addPin()
            }
        } label: {
            Label {
                Text(type == .remove ? "Remove Point" : "Add Point", bundle: .module)
            } icon: {
                Image(systemName: type.systemImage)
            }
                .labelStyle(.iconOnly)
                .frame(width: 50, height: 50)
        }
        .borderLessTVBottonStyle()
        .foregroundStyle(.white)
#if !os(visionOS)
        .applyIf(usesGlassEffects && isSelected) {
            $0.glassEffect(.regular.tint(NetworkModules.map.tint.opacity(0.75)).interactive())
        }
        .applyIf(usesGlassEffects) {
            $0.glassEffectID(type.label, in: glassNamespace)
        }
#endif
        .offset(type.offset(expanded: isSelected, layoutDown: true))
        .animation(.spring(duration: type.duration * 3, bounce: 0.2), value: isSelected)
        .opacity(isSelected ? 1 : 0)
        .allowsHitTesting(isSelected)
        .accessibilityHidden(!isSelected)
        .simultaneousGesture(canvasConsumptionGesture)
    }

    var needleView: some View {
        VStack(alignment: .center, spacing: 0) {
            needleHeader
                .frame(width: 44, height: 44)

            Self.needlePath
                .stroke(Color.black, lineWidth: 1, antialiased: true)
                .fill(Color.gray)
                .frame(width: 4, height: 60)
                .zIndex(1)

            Self.needlePinPath
                .stroke(Color.black, lineWidth: 1, antialiased: true)
                .fill(Color.gray)
                .frame(width: 4, height: 60)
        }
        .compositingGroup()
        .shadow(radius: 8)
        .zIndex(isSelected ? 100 : 1)
    }

    var needleHeader: some View {
        headerBar
    }

    var headerBar: some View {
        Circle().fill(.black.opacity(0.4))
            .frame(width: 44, height: 44)
            .scaleEffect(isSelected ? 84.0 / 44.0 : 1.0)
            .animation(.spring(duration: 0.9, bounce: 0.2), value: isSelected)
            .opacity(isSelected ? 1 : 0)
            .overlay(alignment: .center) {
                needHead
                    .overlay {
        #if os(visionOS)
                        actionButtons
        #else
                        if usesGlassEffects {
                            GlassEffectContainer {
                                actionButtons
                            }
                        } else {
                            actionButtons
                        }
        #endif
                    }
            }
            .zIndex(2)
    }

    func addPin() {
        consumeCanvasInteraction()
        withAnimation(.bouncy) {
            mapEditController.addNeedlePoint(at: index, entryId: entryId, entries: entries, map: map)
        }
        notifyCoordinatesChanged()
    }

    func removePin() {
        consumeCanvasInteraction()
        withAnimation(.bouncy) {
            mapEditController.removeNeedlePoint(at: index, entryId: entryId, entries: entries, map: map)
        }
        notifyCoordinatesChanged()
    }

    var needHead: some View {
        Circle().fill(.teal)
            .stroke(Color.blue, lineWidth: 2, antialiased: true)
            .frame(width: 44, height: 44)
            .zIndex(2)
            .gesture(combinedGesture)
            .simultaneousGesture(canvasConsumptionGesture)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Text("Map Area Point \(index + 1)", bundle: .module)
            )
            .accessibilityValue(coordinateAccessibilityValue)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                toggleSelection()
            }
#if !os(tvOS)
            .accessibilityAction(named: Text("Move Left", bundle: .module)) {
                movePointBy(x: -10, y: 0)
            }
            .accessibilityAction(named: Text("Move Right", bundle: .module)) {
                movePointBy(x: 10, y: 0)
            }
            .accessibilityAction(named: Text("Move Up", bundle: .module)) {
                movePointBy(x: 0, y: -10)
            }
            .accessibilityAction(named: Text("Move Down", bundle: .module)) {
                movePointBy(x: 0, y: 10)
            }
#endif
    }

    func updateCoordinate() {
        mapEditController.updateNeedleCoordinate(entryId: entryId, entries: entries, map: map)
        notifyCoordinatesChanged()
    }

    var combinedGesture: some Gesture {
        let tapGesture = TapGesture().onEnded {
            toggleSelection()
        }
#if os(tvOS)
        return tapGesture
#else
        return dragGesture.simultaneously(with: tapGesture)
#endif
    }

#if !os(tvOS)
    var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                consumeCanvasInteraction()
                let startCoordinate = dragStartCoordinate ?? coordinate
                if dragStartCoordinate == nil {
                    dragStartCoordinate = startCoordinate
                }
                let position = CGPoint(
                    x: startCoordinate.x + value.location.x - value.startLocation.x,
                    y: startCoordinate.y + value.location.y - value.startLocation.y
                )
                entries.update(coordinate: position, for: entryId, at: index)
                entries.selectedNeedleCoordinate = position
            }
            .onEnded { _ in
                dragStartCoordinate = nil
                entries.selectedNeedleCoordinate = nil
                updateCoordinate()
            }
    }

    func movePointBy(x: CGFloat, y: CGFloat) {
        entries.update(
            coordinate: CGPoint(x: coordinate.x + x, y: coordinate.y + y),
            for: entryId,
            at: index
        )
        updateCoordinate()
    }
#endif

    private var coordinateAccessibilityValue: Text {
        Text(
            "X \(coordinate.x, format: .number.precision(.fractionLength(0))), Y \(coordinate.y, format: .number.precision(.fractionLength(0)))",
            bundle: .module
        )
    }

    private func toggleSelection() {
        consumeCanvasInteraction()
        withAnimation(reduceMotion ? nil : .bouncy) {
            entries.selectedNeedleIndex = isSelected ? nil : index
        }
    }

    private func consumeCanvasInteraction() {
        entries.addedNewNeedlePoint = nil
        entries.eaten = true
    }

    private var canvasConsumptionGesture: some Gesture {
        LongPressGesture(minimumDuration: 0)
            .onChanged { _ in
                consumeCanvasInteraction()
            }
    }

    private func notifyCoordinatesChanged() {
        coordinatesChanged(entries.entry(entryId).coordinates)
    }

    private static let needlePath: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: 4, y: 0))
        p.addLine(to: CGPoint(x: 4, y: 60))
        p.addLine(to: CGPoint(x: 0, y: 60))
        p.closeSubpath()
        return p
    }()

    private static let needlePinPath: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 0.5, y: 0))
        p.addLine(to: CGPoint(x: 3.5, y: 0))
        p.addLine(to: CGPoint(x: 2, y: 6))
        p.closeSubpath()
        return p
    }()
}

enum NeedleMapPinButtonType: String {
    case remove, add

    var systemImage: String {
        switch self {
        case .remove: return "trash"
        case .add: return "plus"
        }
    }

    var label: String {
        self.rawValue.capitalized
    }

    var duration: CGFloat {
        switch self {
        case .remove: return 0.3
        case .add: return 0.5
        }
    }

    func offset(expanded: Bool, layoutDown: Bool) -> CGSize {
        guard expanded else { return .zero }
        switch self {
        case .remove: return offset(atIndex: 0, layoutDown: layoutDown)
        case .add: return offset(atIndex: 3, layoutDown: layoutDown)
        }
    }

    private func offset(atIndex index: Int, layoutDown: Bool) -> CGSize {
        let radius: CGFloat = 80
        let startAngleDeg = 45.0
        let step = 90.0 / Double(4 - 1)
        let angleDeg = startAngleDeg + (Double(index) * step)
        let angleRad = angleDeg * .pi / 180
        return CGSize(
            width: cos(angleRad) * radius,
            height: sin(angleRad) * radius * (layoutDown ? -1 : 1)
        )
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(MapRootModel.self) var root
    @Previewable var entries = MapEntryViewerModel(mapId: MapModel.previewId, entries: [MapEntryModel.previewGreatHall])
    let mapEditController = MapEditController(editController: root.editController)

    ZStack(alignment: .topLeading) {
        Rectangle().fill(Color.yellow.gradient)
            .ignoresSafeArea()
        
        ForEach(entries.entries[0].coordinates.indexed(), id: \.index) { (index, point) in
            NeedleMapPin(entries: entries, entryId: entries.entries[0].id, index: index, map: MapModel.preview, mapEditController: mapEditController)
                .offset(x: point.x - 22, y: point.y - 110)
        }
    }
}
