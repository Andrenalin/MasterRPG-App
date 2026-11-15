// @copyright André Trettin

import CoreRPG
import SwiftUI

@MainActor @Observable
final class MapRoomNode: Identifiable {
    init(entry: MapEntryModel) {
        id = entry.id
        self.entry = entry
        let path = Self.makePath(for: entry)
        self.path = path
        bounds = path.boundingRect
    }

    nonisolated let id: UUID
    private(set) var entry: MapEntryModel
    private(set) var path: Path
    /// The path's bounding rectangle, computed when the geometry is made. The culling passes read
    /// it for every room on every pan or zoom frame, so it must not be derived from the path each
    /// time. See CODE_AUDIT_26 §7.52.
    private(set) var bounds: CGRect

    func update(entry: MapEntryModel) {
        guard self.entry != entry else { return }
        let geometryChanged = self.entry.coordinates != entry.coordinates
        self.entry = entry
        if geometryChanged {
            path = Self.makePath(for: entry)
            bounds = path.boundingRect
        }
    }

    private static func makePath(for entry: MapEntryModel) -> Path {
        Path { path in
            guard let firstPoint = entry.coordinates.first else { return }
            path.move(to: firstPoint)
            for point in entry.coordinates.dropFirst() {
                path.addLine(to: point)
            }
            path.closeSubpath()
        }
    }
}

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
    var dragPointId: UUID?
}

@MainActor @Observable
final class MapEntryViewerModel {
    typealias NeedleSelectionHandler = @MainActor (MapNeedlePointModel?) -> Void

    /// - Parameter tracksNeedles: whether the model keeps an observable needle per vertex. Only
    ///   the store of the room being edited uses them; the passive store of a 20,000-cell hex map
    ///   would allocate about 120,000 of them on every reset. See CODE_AUDIT_26 §7.10.
    init(mapId: UUID, entries: [MapEntryModel] = [], tracksNeedles: Bool = true) {
        self.mapId = mapId
        self.tracksNeedles = tracksNeedles
        self.entries = entries
        let nodes = entries.map(MapRoomNode.init(entry:))
        roomNodes = nodes
        entryIndexById = Self.indexById(entries)
        roomNodeById = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        reconcileNeedlePoints(with: entries)
    }

    let tracksNeedles: Bool
    /// Id lookups for `setEntry`, `entry(_:)` and `roomNode(for:)`: they ran a linear search per
    /// call, which made a reset of a big hex map quadratic. See CODE_AUDIT_26 §7.9.
    private var entryIndexById: [UUID: Int] = [:]
    private var roomNodeById: [UUID: MapRoomNode] = [:]

    private static func indexById(_ entries: [MapEntryModel]) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        result.reserveCapacity(entries.count)
        for (index, entry) in entries.enumerated() where result[entry.id] == nil {
            result[entry.id] = index
        }
        return result
    }

    var mapId: UUID
    private(set) var entries: [MapEntryModel]
    private(set) var roomNodes: [MapRoomNode]
    let needleInteraction = MapNeedleInteractionModel()

    private var needlePointsByEntry: [UUID: [MapNeedlePointModel]] = [:]
    @ObservationIgnored private var needleSelectionHandler: NeedleSelectionHandler?

    func configureNeedleSelectionHandler(_ handler: NeedleSelectionHandler?) {
        needleSelectionHandler = handler
    }

    func resetEntries(mapId: UUID, entries: [MapEntryModel]) {
        self.mapId = mapId
        self.entries = entries
        entryIndexById = Self.indexById(entries)
        reconcileRoomNodes(with: entries)
        reconcileNeedlePoints(with: entries)
    }

    func entry(_ entryId: UUID) -> MapEntryModel {
        entryIndexById[entryId].map { entries[$0] } ?? .empty(entryId)
    }

    /// Replaces the entry with the same id. An entry equal to the stored one changes nothing, so
    /// a bulk synchronization only pays for the rooms that differ.
    func setEntry(entry: MapEntryModel) {
        guard let index = entryIndexById[entry.id], entries[index] != entry else { return }
        entries[index] = entry
        roomNodeById[entry.id]?.update(entry: entry)
        reconcileNeedlePoints(for: entry)
    }

    func roomNode(for entryId: UUID) -> MapRoomNode? {
        roomNodeById[entryId]
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
        guard let entryIndex = entryIndexById[entryId],
              case var entry = entries[entryIndex],
              point.coordinateIndex >= 0,
              point.coordinateIndex < entry.coordinates.count else { return }
        point.coordinate = coordinate
        entry.coordinates[point.coordinateIndex] = coordinate
        entries[entryIndex] = entry
        roomNodeById[entryId]?.update(entry: entry)
    }

    func insertNeedle(after point: MapNeedlePointModel, entryId: UUID) {
        guard let entryIndex = entryIndexById[entryId],
              case var entry = entries[entryIndex],
              point.coordinateIndex >= 0,
              point.coordinateIndex < entry.coordinates.count else { return }
        // After the last point the room closes back to the first: the new point sits halfway
        // between them and goes to the end of the list, the other indices stay.
        // See CODE_AUDIT_26 §5.91.
        let insertionIndex = point.coordinateIndex + 1
        let nextCoordinate = entry.coordinates[insertionIndex < entry.coordinates.count ? insertionIndex : 0]
        let newCoordinate = nextCoordinate - (nextCoordinate - point.coordinate) / 2
        entry.coordinates.insert(newCoordinate, at: insertionIndex)
        entries[entryIndex] = entry
        roomNodeById[entryId]?.update(entry: entry)

        var points = needlePointsByEntry[entryId] ?? []
        for candidate in points where candidate.coordinateIndex >= insertionIndex {
            candidate.coordinateIndex += 1
        }
        points.append(MapNeedlePointModel(coordinate: newCoordinate, coordinateIndex: insertionIndex))
        needlePointsByEntry[entryId] = points
    }

    func removeNeedle(_ point: MapNeedlePointModel, entryId: UUID) {
        guard let entryIndex = entryIndexById[entryId],
              case var entry = entries[entryIndex],
              point.coordinateIndex >= 0,
              point.coordinateIndex < entry.coordinates.count else { return }
        let removedIndex = point.coordinateIndex
        entry.coordinates.remove(at: removedIndex)
        entries[entryIndex] = entry
        roomNodeById[entryId]?.update(entry: entry)

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

    private func reconcileRoomNodes(with entries: [MapEntryModel]) {
        // First-wins, not a trapping `uniqueKeysWithValues`: the nodes mirror entries of a peer
        // or imported map, which can repeat an id. See CODE_AUDIT_21 §6.8.
        var existingNodes = Dictionary(roomNodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let reconciled = entries.map { entry in
            if let node = existingNodes.removeValue(forKey: entry.id) {
                node.update(entry: entry)
                return node
            }
            return MapRoomNode(entry: entry)
        }

        let structureChanged = reconciled.count != roomNodes.count
            || zip(reconciled, roomNodes).contains { $0.id != $1.id }
        if structureChanged {
            roomNodes = reconciled
        }
        roomNodeById = Dictionary(roomNodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func reconcileNeedlePoints(with entries: [MapEntryModel]) {
        guard tracksNeedles else { return }
        let validIds = Set(entries.map(\.id))
        needlePointsByEntry = needlePointsByEntry.filter { validIds.contains($0.key) }
        for entry in entries {
            reconcileNeedlePoints(for: entry)
        }
    }

    private func reconcileNeedlePoints(for entry: MapEntryModel) {
        guard tracksNeedles else { return }
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
