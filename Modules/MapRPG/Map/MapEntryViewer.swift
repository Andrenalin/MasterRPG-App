// @copyright André Trettin

import CoreRPG
import SwiftUI

@MainActor @Observable
final class MapNeedlePointModel: Identifiable {
    init(id: UUID = UUID(), coordinate: CGPoint, coordinateIndex: Int) {
        self.id = id
        self.coordinate = coordinate
        self.coordinateIndex = coordinateIndex
    }

    nonisolated let id: UUID
    var coordinate: CGPoint
    fileprivate(set) var coordinateIndex: Int
    fileprivate(set) var isSelected = false
}

@MainActor @Observable
final class MapNeedleInteractionModel {
    var dragCoordinate: CGPoint?
}

@MainActor @Observable
final class MapEntryViewerModel {
    typealias NeedleSelectionHandler = @MainActor (MapNeedlePointModel?) -> Void

    init(mapId: UUID, entries: [MapEntryModel] = [], selectedNeedleIndex: Int? = nil) {
        self.mapId = mapId
        self.entries = entries
        reconcileNeedlePoints(with: entries)
        if let selectedNeedleIndex,
           let entryId = entries.first?.id,
           let point = needlePointsByEntry[entryId]?.first(where: { $0.coordinateIndex == selectedNeedleIndex }) {
            point.isSelected = true
        }
    }

    var mapId: UUID
    private(set) var entries: [MapEntryModel]
    let needleInteraction = MapNeedleInteractionModel()

    // Compatibility for editor/tooling code that still addresses a point by its
    // persisted coordinate index. Rendering and gestures use the stable point ID.
    var selectedNeedleIndex: Int? {
        get { selectedNeedlePoint?.coordinateIndex }
        set {
            guard let entryId = entries.first?.id else {
                clearNeedleSelection()
                return
            }
            let point = newValue.flatMap { index in
                needlePointsByEntry[entryId]?.first { $0.coordinateIndex == index }
            }
            selectNeedle(point)
        }
    }

    var selectedNeedleCoordinate: CGPoint? {
        get { needleInteraction.dragCoordinate }
        set { needleInteraction.dragCoordinate = newValue }
    }

    var addedNewNeedlePoint: CGPoint?
    var eaten: Bool = false

    private var needlePointsByEntry: [UUID: [MapNeedlePointModel]] = [:]
    @ObservationIgnored private var needleSelectionHandler: NeedleSelectionHandler?

    func configureNeedleSelectionHandler(_ handler: NeedleSelectionHandler?) {
        needleSelectionHandler = handler
    }

    func resetEntries(mapId: UUID, entries: [MapEntryModel]) {
        self.mapId = mapId
        self.entries = entries
        reconcileNeedlePoints(with: entries)
    }

    func entry(_ entryId: UUID) -> MapEntryModel {
        entries.first { $0.id == entryId } ?? .empty(entryId)
    }

    func setEntry(entry: MapEntryModel) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
        reconcileNeedlePoints(for: entry)
    }

    func isSelected(index: Int) -> Bool {
        selectedNeedlePoint?.coordinateIndex == index
    }

    func update(coordinate: CGPoint, for entryId: UUID, at index: Int) {
        var updatedEntry = entry(entryId)
        guard index >= 0 && index < updatedEntry.coordinates.count else { return }
        updatedEntry.coordinates[index] = coordinate
        setEntry(entry: updatedEntry)
    }

    func renderedNeedlePoints(for entryId: UUID) -> [MapNeedlePointModel] {
        (needlePointsByEntry[entryId] ?? []).sorted { lhs, rhs in
            if lhs.coordinate.y != rhs.coordinate.y {
                return lhs.coordinate.y < rhs.coordinate.y
            }
            if lhs.coordinate.x != rhs.coordinate.x {
                return lhs.coordinate.x < rhs.coordinate.x
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    func selectedNeedlePoint(for entryId: UUID) -> MapNeedlePointModel? {
        needlePointsByEntry[entryId]?.first(where: \.isSelected)
    }

    func selectNeedle(_ point: MapNeedlePointModel?) {
        let selectedId = point?.id
        for candidate in needlePointsByEntry.values.joined() where candidate.isSelected != (candidate.id == selectedId) {
            candidate.isSelected = candidate.id == selectedId
        }
    }

    func toggleNeedleSelection(_ point: MapNeedlePointModel) {
        selectNeedle(point.isSelected ? nil : point)
        needleSelectionHandler?(point.isSelected ? point : nil)
    }

    func moveNeedle(_ point: MapNeedlePointModel, to coordinate: CGPoint, entryId: UUID) {
        guard var entry = entries.first(where: { $0.id == entryId }),
              point.coordinateIndex >= 0,
              point.coordinateIndex < entry.coordinates.count else { return }
        point.coordinate = coordinate
        entry.coordinates[point.coordinateIndex] = coordinate
        entries[entries.firstIndex(where: { $0.id == entryId }) ?? entries.startIndex] = entry
    }

    func insertNeedle(after point: MapNeedlePointModel, entryId: UUID) {
        guard var entry = entries.first(where: { $0.id == entryId }),
              point.coordinateIndex >= 0,
              point.coordinateIndex < entry.coordinates.count else { return }
        let insertionIndex = point.coordinateIndex + 1 < entry.coordinates.count
            ? point.coordinateIndex + 1
            : 0
        var newCoordinate = entry.coordinates[insertionIndex]
        if insertionIndex == 0 {
            newCoordinate = newCoordinate + CGPoint(x: 50, y: 50)
        } else {
            newCoordinate = newCoordinate - (newCoordinate - point.coordinate) / 2
        }
        entry.coordinates.insert(newCoordinate, at: insertionIndex)
        entries[entries.firstIndex(where: { $0.id == entryId }) ?? entries.startIndex] = entry

        var points = needlePointsByEntry[entryId] ?? []
        for candidate in points where candidate.coordinateIndex >= insertionIndex {
            candidate.coordinateIndex += 1
        }
        points.append(MapNeedlePointModel(coordinate: newCoordinate, coordinateIndex: insertionIndex))
        needlePointsByEntry[entryId] = points
    }

    func removeNeedle(_ point: MapNeedlePointModel, entryId: UUID) {
        guard var entry = entries.first(where: { $0.id == entryId }),
              point.coordinateIndex >= 0,
              point.coordinateIndex < entry.coordinates.count else { return }
        let removedIndex = point.coordinateIndex
        entry.coordinates.remove(at: removedIndex)
        entries[entries.firstIndex(where: { $0.id == entryId }) ?? entries.startIndex] = entry

        if point.isSelected {
            selectNeedle(nil)
            needleSelectionHandler?(nil)
        }
        var points = needlePointsByEntry[entryId] ?? []
        points.removeAll { $0.id == point.id }
        for candidate in points where candidate.coordinateIndex > removedIndex {
            candidate.coordinateIndex -= 1
        }
        needlePointsByEntry[entryId] = points
    }

    private var selectedNeedlePoint: MapNeedlePointModel? {
        needlePointsByEntry.values.joined().first(where: \.isSelected)
    }

    private func clearNeedleSelection() {
        selectNeedle(nil)
    }

    private func reconcileNeedlePoints(with entries: [MapEntryModel]) {
        let validIds = Set(entries.map(\.id))
        needlePointsByEntry = needlePointsByEntry.filter { validIds.contains($0.key) }
        for entry in entries {
            reconcileNeedlePoints(for: entry)
        }
    }

    private func reconcileNeedlePoints(for entry: MapEntryModel) {
        let oldPoints = needlePointsByEntry[entry.id] ?? []
        var unused = oldPoints
        var reconciled: [MapNeedlePointModel] = []
        reconciled.reserveCapacity(entry.coordinates.count)

        for (index, coordinate) in entry.coordinates.enumerated() {
            let exactIndex = unused.firstIndex { $0.coordinate == coordinate }
            let fallbackIndex = unused.firstIndex { $0.coordinateIndex == index }
            if let matchIndex = exactIndex ?? fallbackIndex {
                let point = unused.remove(at: matchIndex)
                point.coordinate = coordinate
                point.coordinateIndex = index
                reconciled.append(point)
            } else {
                reconciled.append(MapNeedlePointModel(coordinate: coordinate, coordinateIndex: index))
            }
        }

        needlePointsByEntry[entry.id] = reconciled
    }
}

struct MapEntryViewer: View {
    let entry: MapEntryModel
    let displayMode: MapDisplayMode
    let displayConfig: DisplayConfigModel
    let activateGestures: Bool
    let mapImage: AKImage?
    let mapImageSize: CGSize?
    let doubleTapAction: () -> Void
    let longPressAction: () -> Void

    init(
        entry: MapEntryModel,
        displayMode: MapDisplayMode,
        displayConfig: DisplayConfigModel,
        activateGestures: Bool,
        mapImage: AKImage?,
        mapImageSize: CGSize? = nil,
        doubleTapAction: @escaping () -> Void,
        longPressAction: @escaping () -> Void
    ) {
        self.entry = entry
        self.displayMode = displayMode
        self.displayConfig = displayConfig
        self.activateGestures = activateGestures
        self.mapImage = mapImage
        self.mapImageSize = mapImageSize
        self.doubleTapAction = doubleTapAction
        self.longPressAction = longPressAction
    }

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
        .allowsHitTesting(activateGestures)
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
            .highPriorityGesture(doubleTapGesture.exclusively(before: longPressGesture))
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
        
        guard let imageSize = mapImageSize ?? mapImage?.fixedSize,
              imageSize.width > 0,
              imageSize.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        
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
