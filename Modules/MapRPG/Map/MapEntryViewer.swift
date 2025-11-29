// @copyright André Trettin

import CoreRPG
import SwiftUI

@Observable
final class MapEntryViewerModel {
    init(entries: [MapEntryModel] = [], selectedNeedleIndex: Int? = nil) {
        self.entries = entries
        self.selectedNeedleIndex = selectedNeedleIndex
    }
    
    var entries: [MapEntryModel]
    var selectedNeedleIndex: Int?
    var selectedNeedleCoordinate: CGPoint?

    var addedNewNeedlePoint: CGPoint?
    var eaten: Bool = false

    func entry(_ entryId: UUID) -> MapEntryModel {
        entries.first { $0.id == entryId }  ?? .empty(entryId)
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
    let model: MapEntryViewerModel
    let entryId: UUID
    let displayMode: MapDisplayMode
    let displayConfig: DisplayConfigModel
    let activateGestures: Bool
    let doubleTapAction: () -> Void
    let longPressAction: () -> Void
    
    var body: some View {
        Group {
            let subPathCache = subPath(for: entry)
            switch displayMode {
            case .master:
                subPathCache.fill(.green.opacity(entry.isShown ? 0.1 : 0.5))
                    .stroke(.green.opacity(0.8), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
            case .player:
                if !entry.isShown {
                    subPathCache.fill(displayConfig.color)
                }
                if !entry.isShown, displayConfig.hasBorder {
                    subPathCache.stroke(displayConfig.borderColor, style: StrokeStyle(lineWidth: displayConfig.borderThickness, lineCap: .round, lineJoin: .round))
                }
            case .reader:
                subPathCache.stroke(.green.opacity(0.8), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
            }
        }
        .applyIf(activateGestures) { content in
            content
#if os(visionOS)
                .hoverEffect(.highlight)
#endif
                .simultaneousGesture(gestures)
        }
    }
    
    private var gestures: some Gesture {
        doubleTapGesture.exclusively(before: longPressGesture)
    }
    
    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2).onEnded {
            withAnimation(.bouncy) {
                var updatedEntry = entry
                updatedEntry.isShown.toggle()
                model.setEntry(entry: updatedEntry)
            }
            doubleTapAction()
        }
    }
    
    private var longPressGesture: some Gesture {
        LongPressGesture().onEnded { isLongPressed in
            if isLongPressed {
                longPressAction()
            }
        }
    }
    
    private var entry: MapEntryModel {
        model.entry(entryId)
    }
    
    private func subPath(for entry: MapEntryModel) -> Path {
        Path { path in
            guard let firstPoint = entry.coordinates.first else {
                return
            }
            path.move(to: firstPoint - CGPoint(x: entry.xOffset, y: entry.yOffset))
            for point in entry.coordinates[1...] {
                path.addLine(to: point - CGPoint(x: entry.xOffset, y: entry.yOffset))
            }
            path.addLine(to: firstPoint - CGPoint(x: entry.xOffset, y: entry.yOffset))
            if entry.coordinates.count >= 2 {
                let secondPoint = entry.coordinates[1]
                path.addLine(to: secondPoint - CGPoint(x: entry.xOffset, y: entry.yOffset))
            }
        }
    }
}
