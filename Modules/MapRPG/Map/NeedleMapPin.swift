// @copyright André Trettin

import CoreRPG
import SwiftUI

struct MapNeedleLayer: View {
    let entries: MapEntryViewerModel
    let entryId: UUID
    var coordinatesChanged: ([CGPoint]) -> Void = { _ in }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(entries.renderedNeedlePoints(for: entryId)) { point in
                NeedleMapPin(
                    entries: entries,
                    entryId: entryId,
                    point: point,
                    coordinatesChanged: coordinatesChanged
                )
                .offset(x: point.coordinate.x - 22, y: point.coordinate.y - 110)
            }
        }
    }
}

struct MapNeedleMenuLayer: View {
    let entries: MapEntryViewerModel
    let entryId: UUID
    var coordinatesChanged: ([CGPoint]) -> Void = { _ in }
    var usesGlassEffects = true

    var body: some View {
        if let point = entries.selectedNeedlePoint(for: entryId) {
            NeedleMapPinMenu(
                entries: entries,
                entryId: entryId,
                point: point,
                coordinatesChanged: coordinatesChanged,
                usesGlassEffects: usesGlassEffects
            )
            .offset(x: point.coordinate.x - 22, y: point.coordinate.y - 110)
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        }
    }
}

struct NeedleMapPin: View {
    let entries: MapEntryViewerModel
    let entryId: UUID
    let point: MapNeedlePointModel
    let coordinatesChanged: ([CGPoint]) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var dragTranslation: CGSize = .zero

    init(
        entries: MapEntryViewerModel,
        entryId: UUID,
        point: MapNeedlePointModel,
        coordinatesChanged: @escaping ([CGPoint]) -> Void = { _ in }
    ) {
        self.entries = entries
        self.entryId = entryId
        self.point = point
        self.coordinatesChanged = coordinatesChanged
    }

    // Compatibility for previews/tests that still address the persisted array
    // index. Production rendering passes the stable point model directly.
    init(
        entries: MapEntryViewerModel,
        entryId: UUID,
        index: Int,
        map _: MapModel,
        mapEditController _: MapEditController,
        coordinatesChanged: @escaping ([CGPoint]) -> Void = { _ in },
        usesGlassEffects _: Bool = true
    ) {
        let point = entries.renderedNeedlePoints(for: entryId)
            .first(where: { $0.coordinateIndex == index })
            ?? MapNeedlePointModel(coordinate: .zero, coordinateIndex: index)
        self.init(
            entries: entries,
            entryId: entryId,
            point: point,
            coordinatesChanged: coordinatesChanged
        )
    }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            needleHeader
                .frame(width: 44, height: 44)

            Self.needlePath
                .stroke(Color.black, lineWidth: 1, antialiased: true)
                .fill(Color.gray)
                .frame(width: 4, height: 60)
                .allowsHitTesting(false)

            Self.needlePinPath
                .stroke(Color.black, lineWidth: 1, antialiased: true)
                .fill(Color.gray)
                .frame(width: 4, height: 60)
                .allowsHitTesting(false)
        }
        .shadow(radius: 4)
        .offset(dragTranslation)
    }

    private var needleHeader: some View {
        Circle()
            .fill(.black.opacity(0.4))
            .frame(width: 44, height: 44)
            .scaleEffect(point.isSelected ? 84.0 / 44.0 : 1.0)
            .animation(reduceMotion ? nil : .snappy, value: point.isSelected)
            .opacity(point.isSelected ? 1 : 0)
            .overlay {
                needleHead
            }
    }

    private var needleHead: some View {
        Circle()
            .fill(.teal)
            .stroke(Color.blue, lineWidth: 2, antialiased: true)
            .frame(width: 44, height: 44)
            .contentShape(.circle)
            .highPriorityGesture(combinedGesture)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Text("Map Area Point \(point.coordinateIndex + 1)", bundle: .module)
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

    private var combinedGesture: some Gesture {
        let tapGesture = TapGesture().onEnded {
            toggleSelection()
        }
#if os(tvOS)
        return tapGesture
#else
        return dragGesture.exclusively(before: tapGesture)
#endif
    }

#if !os(tvOS)
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onChanged { value in
                entries.needleInteraction.dragCoordinate = CGPoint(
                    x: point.coordinate.x + value.translation.width,
                    y: point.coordinate.y + value.translation.height
                )
            }
            .onEnded { value in
                let coordinate = CGPoint(
                    x: point.coordinate.x + value.translation.width,
                    y: point.coordinate.y + value.translation.height
                )
                entries.moveNeedle(point, to: coordinate, entryId: entryId)
                entries.needleInteraction.dragCoordinate = nil
                notifyCoordinatesChanged()
            }
    }

    func movePointBy(x: CGFloat, y: CGFloat) {
        entries.moveNeedle(
            point,
            to: CGPoint(x: point.coordinate.x + x, y: point.coordinate.y + y),
            entryId: entryId
        )
        notifyCoordinatesChanged()
    }
#endif

    func updateCoordinate() {
        notifyCoordinatesChanged()
    }

    private var coordinateAccessibilityValue: Text {
        Text(
            "X \(point.coordinate.x, format: .number.precision(.fractionLength(0))), Y \(point.coordinate.y, format: .number.precision(.fractionLength(0)))",
            bundle: .module
        )
    }

    private func toggleSelection() {
        withAnimation(reduceMotion ? nil : .snappy) {
            entries.toggleNeedleSelection(point)
        }
    }

    private func notifyCoordinatesChanged() {
        coordinatesChanged(entries.entry(entryId).coordinates)
    }

    private static let needlePath: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 4, y: 0))
        path.addLine(to: CGPoint(x: 4, y: 60))
        path.addLine(to: CGPoint(x: 0, y: 60))
        path.closeSubpath()
        return path
    }()

    private static let needlePinPath: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 0.5, y: 0))
        path.addLine(to: CGPoint(x: 3.5, y: 0))
        path.addLine(to: CGPoint(x: 2, y: 6))
        path.closeSubpath()
        return path
    }()
}

private struct NeedleMapPinMenu: View {
    let entries: MapEntryViewerModel
    let entryId: UUID
    let point: MapNeedlePointModel
    let coordinatesChanged: ([CGPoint]) -> Void
    let usesGlassEffects: Bool

    @Namespace private var glassNamespace

    var body: some View {
        Group {
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
        .frame(width: 44, height: 44)
    }

    private var actionButtons: some View {
        ZStack {
            menuButton(type: .remove)
            menuButton(type: .add)
        }
    }

    private func menuButton(type: NeedleMapPinButtonType) -> some View {
        Button {
            perform(type)
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
        .applyIf(usesGlassEffects) {
            $0.glassEffect(.regular.tint(NetworkModules.map.tint.opacity(0.75)).interactive())
                .glassEffectID(type.label, in: glassNamespace)
        }
#endif
        .offset(type.offset(expanded: true, layoutDown: true))
    }

    private func perform(_ type: NeedleMapPinButtonType) {
        switch type {
        case .remove:
            entries.removeNeedle(point, entryId: entryId)
        case .add:
            entries.insertNeedle(after: point, entryId: entryId)
        }
        coordinatesChanged(entries.entry(entryId).coordinates)
    }
}

enum NeedleMapPinButtonType: String {
    case remove, add

    var systemImage: String {
        switch self {
        case .remove: "trash"
        case .add: "plus"
        }
    }

    var label: String { rawValue.capitalized }

    func offset(expanded: Bool, layoutDown: Bool) -> CGSize {
        guard expanded else { return .zero }
        return switch self {
        case .remove: offset(atIndex: 0, layoutDown: layoutDown)
        case .add: offset(atIndex: 3, layoutDown: layoutDown)
        }
    }

    private func offset(atIndex index: Int, layoutDown: Bool) -> CGSize {
        let radius: CGFloat = 80
        let startAngleDeg = 45.0
        let step = 90.0 / Double(4 - 1)
        let angleDeg = startAngleDeg + Double(index) * step
        let angleRad = angleDeg * .pi / 180
        return CGSize(
            width: cos(angleRad) * radius,
            height: sin(angleRad) * radius * (layoutDown ? -1 : 1)
        )
    }
}

#Preview(traits: .mockData) {
    @Previewable var entries = MapEntryViewerModel(
        mapId: MapModel.previewId,
        entries: [MapEntryModel.previewGreatHall]
    )

    ZStack(alignment: .topLeading) {
        Rectangle().fill(Color.yellow.gradient)
            .ignoresSafeArea()

        MapNeedleLayer(entries: entries, entryId: entries.entries[0].id)
        MapNeedleMenuLayer(entries: entries, entryId: entries.entries[0].id)
    }
}
