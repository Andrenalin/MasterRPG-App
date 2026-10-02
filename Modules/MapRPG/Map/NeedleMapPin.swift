// @copyright André Trettin

import CoreRPG
import SwiftUI

struct MapNeedleLayer: View {
    let entries: MapEntryViewerModel
    let entryId: UUID
    let session: MapEditorSession?
    var viewportScale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(entries.renderedNeedlePoints(for: entryId)) { point in
                NeedleMapPin(
                    entries: entries,
                    entryId: entryId,
                    point: point,
                    session: session,
                    viewportScale: viewportScale
                )
                .offset(x: point.coordinate.x - 22, y: point.coordinate.y - 110)
            }
        }
    }
}

struct NeedleMapPin: View {
    let entries: MapEntryViewerModel
    let entryId: UUID
    let point: MapNeedlePointModel
    let session: MapEditorSession?
    let viewportScale: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var previewCoordinate: CGPoint?

    init(
        entries: MapEntryViewerModel,
        entryId: UUID,
        point: MapNeedlePointModel,
        session: MapEditorSession? = nil,
        viewportScale: CGFloat = 1
    ) {
        self.entries = entries
        self.entryId = entryId
        self.point = point
        self.session = session
        self.viewportScale = viewportScale
    }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
#if !os(tvOS)
            NeedleMapPinHeaderView(
                point: point,
                gesture: combinedGesture,
                coordinateAccessibilityValue: coordinateAccessibilityValue,
                toggleSelection: toggleSelection,
                movePointBy: movePointBy
            )
                .frame(width: 44, height: 44)
#else
            NeedleMapPinHeaderView(
                point: point,
                gesture: combinedGesture,
                coordinateAccessibilityValue: coordinateAccessibilityValue,
                toggleSelection: toggleSelection
            )
                .frame(width: 44, height: 44)
#endif

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
        .offset(previewOffset)
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
        DragGesture(
            minimumDistance: 3,
            coordinateSpace: .named(MapViewportCoordinateSpace.name)
        )
            .updating($previewCoordinate) { value, state, _ in
                state = coordinate(for: value)
            }
            .onChanged { value in
                if entries.needleInteraction.dragPointId != point.id {
                    session?.beginNeedleDrag(point)
                }
                entries.needleInteraction.dragPointId = point.id
                entries.needleInteraction.dragCoordinate = coordinate(for: value)
            }
            .onEnded { value in
                let coordinate = coordinate(for: value)
                entries.moveNeedle(point, to: coordinate, entryId: entryId)
                entries.needleInteraction.dragCoordinate = nil
                entries.needleInteraction.dragPointId = nil
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

    private var previewOffset: CGSize {
        guard let previewCoordinate else { return .zero }
        return CGSize(
            width: previewCoordinate.x - point.coordinate.x,
            height: previewCoordinate.y - point.coordinate.y
        )
    }

#if !os(tvOS)
    /// Converts both gesture locations through the committed viewport. Using
    /// the logical delta between those points keeps the needle preview, loupe
    /// sample, and final coordinate on the same path at every zoom level.
    private func coordinate(for value: DragGesture.Value) -> CGPoint {
        guard let session else {
            let translation = logicalTranslation(value.translation)
            return CGPoint(
                x: point.coordinate.x + translation.width,
                y: point.coordinate.y + translation.height
            )
        }

        return MapNeedleDragGeometry.coordinate(
            originalCoordinate: point.coordinate,
            startViewportPoint: value.startLocation,
            currentViewportPoint: value.location,
            viewportGeometry: session.viewport.geometry,
            transform: session.viewport.transform
        )
    }
#endif

    private func logicalTranslation(_ translation: CGSize) -> CGSize {
        let scale = viewportScale.isFinite && viewportScale > 0 ? viewportScale : 1
        return CGSize(width: translation.width / scale, height: translation.height / scale)
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
        session?.route(.needleCoordinatesChanged(entryId))
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

// MARK: - Extracted subviews (CODE_AUDIT §8.3)
//
// Each gives SwiftUI its own diffing boundary, instead of the previous computed
// `some View` properties on `NeedleMapPin` itself that all re-evaluated whenever any part
// of `NeedleMapPin`'s body did. The gesture is threaded through generically since
// `combinedGesture`'s `some Gesture` still has to be built where `previewCoordinate`
// (a `@GestureState`) lives.
private struct NeedleMapPinHeaderView<G: Gesture>: View {
    let point: MapNeedlePointModel
    let gesture: G
    let coordinateAccessibilityValue: Text
    let toggleSelection: () -> Void
#if !os(tvOS)
    let movePointBy: (_ x: CGFloat, _ y: CGFloat) -> Void
#endif

    var body: some View {
        ZStack {
            MapSelectionHalo(contentDiameter: 44, isVisible: point.isSelected)
#if !os(tvOS)
            NeedleMapPinHeadView(
                point: point,
                gesture: gesture,
                coordinateAccessibilityValue: coordinateAccessibilityValue,
                toggleSelection: toggleSelection,
                movePointBy: movePointBy
            )
#else
            NeedleMapPinHeadView(
                point: point,
                gesture: gesture,
                coordinateAccessibilityValue: coordinateAccessibilityValue,
                toggleSelection: toggleSelection
            )
#endif
        }
        .frame(width: 44, height: 44)
    }
}

private struct NeedleMapPinHeadView<G: Gesture>: View {
    let point: MapNeedlePointModel
    let gesture: G
    let coordinateAccessibilityValue: Text
    let toggleSelection: () -> Void
#if !os(tvOS)
    let movePointBy: (_ x: CGFloat, _ y: CGFloat) -> Void
#endif

    var body: some View {
        Circle()
            .fill(.teal)
            .stroke(Color.blue, lineWidth: 2, antialiased: true)
            .frame(width: 44, height: 44)
            .contentShape(.circle)
            .highPriorityGesture(gesture)
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
                movePointBy(-10, 0)
            }
            .accessibilityAction(named: Text("Move Right", bundle: .module)) {
                movePointBy(10, 0)
            }
            .accessibilityAction(named: Text("Move Up", bundle: .module)) {
                movePointBy(0, -10)
            }
            .accessibilityAction(named: Text("Move Down", bundle: .module)) {
                movePointBy(0, 10)
            }
#endif
    }
}

/// Shared selection halo for needles and map pins. It draws outside the
/// interactive content without enlarging or intercepting its hit region.
struct MapSelectionHalo: View {
    let contentDiameter: CGFloat
    let isVisible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var diameter: CGFloat {
        max(0, contentDiameter) + 40
    }

    private var collapsedScale: CGFloat {
        guard diameter > 0 else { return 1 }
        return max(0, contentDiameter) / diameter
    }

    var body: some View {
        Circle()
            .fill(.black.opacity(0.4))
            .frame(width: diameter, height: diameter)
            .scaleEffect(isVisible ? 1 : collapsedScale)
            .opacity(isVisible ? 1 : 0)
            .animation(reduceMotion ? nil : .snappy, value: isVisible)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

enum NeedleMapPinButtonType: String, CaseIterable, Hashable {
    case remove, add

    var systemImage: String {
        switch self {
        case .remove: "trash"
        case .add: "plus"
        }
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

        MapNeedleLayer(entries: entries, entryId: entries.entries[0].id, session: nil)
    }
}
