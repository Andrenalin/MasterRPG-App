// @copyright André Trettin

import CoreRPG
import SwiftUI

@MainActor @Observable
final class MapRoomNode: Identifiable {
    init(entry: MapEntryModel) {
        id = entry.id
        self.entry = entry
        path = Self.makePath(for: entry)
    }

    nonisolated let id: UUID
    private(set) var entry: MapEntryModel
    private(set) var path: Path

    var bounds: CGRect { path.boundingRect }

    func update(entry: MapEntryModel) {
        guard self.entry != entry else { return }
        let geometryChanged = self.entry.coordinates != entry.coordinates
        self.entry = entry
        if geometryChanged {
            path = Self.makePath(for: entry)
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

    init(mapId: UUID, entries: [MapEntryModel] = []) {
        self.mapId = mapId
        self.entries = entries
        roomNodes = entries.map(MapRoomNode.init(entry:))
        reconcileNeedlePoints(with: entries)
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
        reconcileRoomNodes(with: entries)
        reconcileNeedlePoints(with: entries)
    }

    func entry(_ entryId: UUID) -> MapEntryModel {
        entries.first { $0.id == entryId } ?? .empty(entryId)
    }

    func setEntry(entry: MapEntryModel) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
        roomNodes.first(where: { $0.id == entry.id })?.update(entry: entry)
        reconcileNeedlePoints(for: entry)
    }

    func roomNode(for entryId: UUID) -> MapRoomNode? {
        roomNodes.first { $0.id == entryId }
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
              let entryIndex = entries.firstIndex(where: { $0.id == entryId }),
              point.coordinateIndex >= 0,
              point.coordinateIndex < entry.coordinates.count else { return }
        point.coordinate = coordinate
        entry.coordinates[point.coordinateIndex] = coordinate
        entries[entryIndex] = entry
        roomNodes.first(where: { $0.id == entryId })?.update(entry: entry)
    }

    func insertNeedle(after point: MapNeedlePointModel, entryId: UUID) {
        guard var entry = entries.first(where: { $0.id == entryId }),
              let entryIndex = entries.firstIndex(where: { $0.id == entryId }),
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
        entries[entryIndex] = entry
        roomNodes.first(where: { $0.id == entryId })?.update(entry: entry)

        var points = needlePointsByEntry[entryId] ?? []
        for candidate in points where candidate.coordinateIndex >= insertionIndex {
            candidate.coordinateIndex += 1
        }
        points.append(MapNeedlePointModel(coordinate: newCoordinate, coordinateIndex: insertionIndex))
        needlePointsByEntry[entryId] = points
    }

    func removeNeedle(_ point: MapNeedlePointModel, entryId: UUID) {
        guard var entry = entries.first(where: { $0.id == entryId }),
              let entryIndex = entries.firstIndex(where: { $0.id == entryId }),
              point.coordinateIndex >= 0,
              point.coordinateIndex < entry.coordinates.count else { return }
        let removedIndex = point.coordinateIndex
        entry.coordinates.remove(at: removedIndex)
        entries[entryIndex] = entry
        roomNodes.first(where: { $0.id == entryId })?.update(entry: entry)

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
