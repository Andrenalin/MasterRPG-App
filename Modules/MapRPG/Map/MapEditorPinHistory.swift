// @copyright André Trettin

import Foundation
import Observation

/// An immutable editor checkpoint. The map copy contains every persisted
/// editor property while `activeEntryId` preserves which room was being
/// edited when the checkpoint was created.
@MainActor
struct MapEditorSnapshot: Equatable {
    init(map: MapModel, activeEntryId: UUID?) {
        self.map = map.copy()
        self.activeEntryId = activeEntryId
    }

    let map: MapModel
    let activeEntryId: UUID?

    func copy() -> MapEditorSnapshot {
        MapEditorSnapshot(map: map, activeEntryId: activeEntryId)
    }

    static func == (lhs: MapEditorSnapshot, rhs: MapEditorSnapshot) -> Bool {
        lhs.activeEntryId == rhs.activeEntryId && lhs.map == rhs.map
    }
}

/// Working-copy history for the complete non-game map editor. Every user
/// mutation records one stable map checkpoint after its gesture or control
/// interaction commits, so pins, rooms, tiles, grids, and scales share one
/// chronological Undo/Redo stack.
@MainActor @Observable
final class MapEditorHistory {
    init(map: MapModel, activeEntryId: UUID? = nil) {
        current = MapEditorSnapshot(map: map, activeEntryId: activeEntryId)
    }

    /// Each checkpoint is a full map copy, so the oldest ones are dropped beyond this depth.
    /// See CODE_AUDIT_23 §7.3.
    static let maximumUndoDepth = 100

    private(set) var current: MapEditorSnapshot
    private var undoStack: [MapEditorSnapshot] = []
    private var redoStack: [MapEditorSnapshot] = []
    private(set) var undoTitles: [String] = []
    private(set) var redoTitles: [String] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var undoTitle: String { undoTitles.last ?? "" }
    var redoTitle: String { redoTitles.last ?? "" }

    func reset(to snapshot: MapEditorSnapshot) {
        current = snapshot.copy()
        undoStack.removeAll(keepingCapacity: true)
        redoStack.removeAll(keepingCapacity: true)
        undoTitles.removeAll(keepingCapacity: true)
        redoTitles.removeAll(keepingCapacity: true)
    }

    @discardableResult
    func record(_ snapshot: MapEditorSnapshot, title: String) -> Bool {
        guard snapshot != current else { return false }
        undoStack.append(current)
        undoTitles.append(title)
        trimUndoHistory()
        // The snapshot owns a private map copy and is never mutated (see `MapEditorSnapshot`),
        // so it is kept as it is: a second copy duplicated the whole map, hex grid included,
        // on every checkpoint. See CODE_AUDIT_26 §7.55.
        current = snapshot
        redoStack.removeAll(keepingCapacity: true)
        redoTitles.removeAll(keepingCapacity: true)
        return true
    }

    func undo() -> MapEditorSnapshot? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        if let title = undoTitles.popLast() {
            redoTitles.append(title)
        }
        current = previous
        return previous.copy()
    }

    func redo() -> MapEditorSnapshot? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        if let title = redoTitles.popLast() {
            undoTitles.append(title)
        }
        trimUndoHistory()
        current = next
        return next.copy()
    }

    /// The depth shrinks as the map grows: a checkpoint holds every entry, and a large hex
    /// grid has thousands of them. 100 steps up to 200 entries, at least 10.
    private var undoDepth: Int {
        max(10, min(Self.maximumUndoDepth, 20_000 / max(1, current.map.entries.count)))
    }

    private func trimUndoHistory() {
        let overflow = undoStack.count - undoDepth
        guard overflow > 0 else { return }
        undoStack.removeFirst(overflow)
        undoTitles.removeFirst(min(overflow, undoTitles.count))
    }
}
