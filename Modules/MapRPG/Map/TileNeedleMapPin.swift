// @copyright André Trettin

import SwiftUI

struct TileNeedleMapPin: View {
    let entries: MapEntryViewerModel
    let entryId: UUID
    let index: Int
    let onUpdate: ([CGPoint]) -> Void

    @GestureState private var isDragging = false

    private var coordinate: CGPoint {
        let entry = entries.entry(entryId)
        guard index >= 0, index < entry.coordinates.count else { return .zero }
        return entry.coordinates[index]
    }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            Circle()
                .fill(.blue)
                .frame(width: 44, height: 44)
                .overlay {
                    Circle()
                        .stroke(.white, lineWidth: 2)
                }

            needlePath
                .stroke(.black, lineWidth: 1, antialiased: true)
                .fill(.blue)
                .frame(width: 4, height: 60)
        }
#if !os(tvOS)
        .gesture(dragGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Tile Point \(index + 1)", bundle: .module))
        .accessibilityValue(coordinateAccessibilityValue)
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

#if !os(tvOS)
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .updating($isDragging) { _, state, _ in
                state = true
            }
            .onChanged { value in
                var position = coordinate
                position.x += value.location.x - value.startLocation.x
                position.y += value.location.y - value.startLocation.y
                entries.update(coordinate: position, for: entryId, at: index)
                entries.selectedNeedleCoordinate = position
            }
            .onEnded { _ in
                onUpdate(entries.entry(entryId).coordinates)
            }
    }

    private func movePointBy(x: CGFloat, y: CGFloat) {
        entries.update(
            coordinate: CGPoint(x: coordinate.x + x, y: coordinate.y + y),
            for: entryId,
            at: index
        )
        onUpdate(entries.entry(entryId).coordinates)
    }

    private var coordinateAccessibilityValue: Text {
        Text(
            "X \(coordinate.x, format: .number.precision(.fractionLength(0))), Y \(coordinate.y, format: .number.precision(.fractionLength(0)))",
            bundle: .module
        )
    }
#endif

    private var needlePath: Path {
        var path = Path()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 4, y: 0))
        path.addLine(to: CGPoint(x: 4, y: 60))
        path.addLine(to: CGPoint(x: 0, y: 60))
        path.closeSubpath()
        return path
    }
}

#Preview {
    TileNeedleMapPin(
        entries: MapEntryViewerModel(mapId: MapModel.previewId, entries: [.previewGreatHall]),
        entryId: MapEntryModel.previewGreatHall.id,
        index: 0,
        onUpdate: { _ in }
    )
}
