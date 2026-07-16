// @copyright André Trettin

import CoreRPG
import SwiftUI

@MainActor @Observable
final class MapEntryViewerModel {
    init(mapId: UUID, entries: [MapEntryModel] = [], selectedNeedleIndex: Int? = nil) {
        self.mapId = mapId
        self.entries = entries
        self.selectedNeedleIndex = selectedNeedleIndex
    }

    var mapId: UUID
    private(set) var entries: [MapEntryModel]
    var selectedNeedleIndex: Int?
    var selectedNeedleCoordinate: CGPoint?

    var addedNewNeedlePoint: CGPoint?
    var eaten: Bool = false

    func resetEntries(mapId: UUID, entries: [MapEntryModel]) {
        self.mapId = mapId
        self.entries = entries
    }

    func entry(_ entryId: UUID) -> MapEntryModel {
        entries.first { $0.id == entryId } ?? .empty(entryId)
    }

    func setEntry(entry: MapEntryModel) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
    }

    func isSelected(index: Int) -> Bool {
        selectedNeedleIndex == index
    }

    func update(coordinate: CGPoint, for entryId: UUID, at index: Int) {
        var updatedEntry = entry(entryId)
        guard index >= 0 && index < updatedEntry.coordinates.count else { return }
        updatedEntry.coordinates[index] = coordinate
        setEntry(entry: updatedEntry)
    }
}

struct MapEntryViewer: View {
    let entry: MapEntryModel
    let displayMode: MapDisplayMode
    let displayConfig: DisplayConfigModel
    let activateGestures: Bool
    let mapImage: AKImage?
    let doubleTapAction: () -> Void
    let longPressAction: () -> Void

    var body: some View {
        let path = entryPath
        Group {
            switch displayMode {
            case .master:
                path.fill(.green.opacity(entry.isShown ? 0.1 : 0.5))
                    .stroke(.green.opacity(0.8), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    .applyIf(activateGestures, transform: gestureModifier)
            case .player:
                playerCoverView(for: path)
                    .opacity(entry.isShown ? 0 : 1)
                    .applyIf(activateGestures, transform: gestureModifier)
            case .reader:
                path.stroke(.green.opacity(0.8), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    .applyIf(activateGestures, transform: gestureModifier)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            entry.name.isEmpty
                ? Text("Map Area", bundle: .module)
                : Text(verbatim: entry.name)
        )
        .accessibilityValue(
            Text(entry.isShown ? "Visible to Players" : "Hidden from Players", bundle: .module)
        )
        .accessibilityAction(named: Text("Toggle Player Visibility", bundle: .module)) {
            guard activateGestures else { return }
            doubleTapAction()
        }
        .accessibilityAction(named: Text("Focus Map Area", bundle: .module)) {
            guard activateGestures else { return }
            longPressAction()
        }
    }

    // Path is expensive to build — cached as a computed property so body only
    // references it once, and SwiftUI won't rebuild it unless entry.coordinates changes.
    private var entryPath: Path {
        Path { path in
            guard let first = entry.coordinates.first else { return }
            let origin = CGPoint(x: entry.xOffset, y: entry.yOffset)
            path.move(to: first - origin)
            for point in entry.coordinates[1...] {
                path.addLine(to: point - origin)
            }
            path.addLine(to: first - origin)
            if entry.coordinates.count >= 2 {
                path.addLine(to: entry.coordinates[1] - origin)
            }
        }
    }

    private func gestureModifier<V: View>(_ content: V) -> some View {
        content
#if os(visionOS)
            .hoverEffect(.highlight)
#endif
            .simultaneousGesture(doubleTapGesture.exclusively(before: longPressGesture))
    }

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2).onEnded {
            doubleTapAction()
        }
    }

    private var longPressGesture: some Gesture {
        LongPressGesture().onEnded { _ in
            longPressAction()
        }
    }
    
    @ViewBuilder
    private func playerCoverView(for path: Path) -> some View {
        if displayConfig.tileCoordinates.count == 4, let mapImage {
            // Use tile from map image
            path.fill(
                ImagePaint(
                    image: Image(akImage: mapImage),
                    sourceRect: tileSourceRect,
                    scale: 1.0
                )
            )
        } else {
            // Fallback to solid color
            path.fill(displayConfig.color)
        }
    }
    
    private var tileSourceRect: CGRect {
        guard displayConfig.tileCoordinates.count == 4 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        
        let coords = displayConfig.tileCoordinates
        let minX = coords.map { $0.x }.min() ?? 0
        let maxX = coords.map { $0.x }.max() ?? 0
        let minY = coords.map { $0.y }.min() ?? 0
        let maxY = coords.map { $0.y }.max() ?? 0
        
        #if os(macOS)
        guard let imageSize = mapImage?.size else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        #else
        guard let imageSize = mapImage?.size else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        #endif
        
        // Normalize to 0-1 range for ImagePaint
        return CGRect(
            x: minX / imageSize.width,
            y: minY / imageSize.height,
            width: (maxX - minX) / imageSize.width,
            height: (maxY - minY) / imageSize.height
        )
    }
}

#Preview {
    MapEntryViewer(entry: .previewGreatHall, displayMode: .master, displayConfig: MapModel.preview.displayConfig, activateGestures: false, mapImage: nil, doubleTapAction: {}, longPressAction: {})
}
