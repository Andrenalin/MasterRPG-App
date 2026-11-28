// @copyright André Trettin

import Foundation

public extension ItemDataAccessible {
    /// Applies to `self` (the library copy) only what `edited` changed relative to `base` (the
    /// game copy the edit started from): the changed header fields, and the entries that were
    /// added, changed or removed. Everything else keeps the library's value, so a forced save
    /// during a game does not write the game's session state into the library.
    /// See CODE_AUDIT_29 §5.2.
    ///
    /// Covers the properties every item has, then the module's own through `applyModuleEdit`
    /// (dice, photos, weather or dice options edited in the editor window during a game).
    /// `includingSessionContent` uses `applyModuleUndo` instead, for undo and redo of an edit
    /// that was written where it was made. `fileUrl` is never applied by undo: the file a step
    /// referenced may be gone. See CODE_AUDIT_Edit_Save §5.2, §5.3.
    @MainActor mutating func applyEdit(from base: Self, to edited: Self, includingSessionContent: Bool = false, includingFile: Bool = true) {
        if base.name != edited.name { name = edited.name }
        if base.description != edited.description { description = edited.description }
        if base.category != edited.category { category = edited.category }
        if base.tags != edited.tags { tags = edited.tags }
        if base.displayState != edited.displayState { displayState = edited.displayState }
        if base.isGroupHiddenToggle != edited.isGroupHiddenToggle { isGroupHiddenToggle = edited.isGroupHiddenToggle }
        if includingFile, base.fileUrl != edited.fileUrl { fileUrl = edited.fileUrl }
        if base.parentId != edited.parentId { parentId = edited.parentId }

        if includingSessionContent || !Self.hasSessionOnlyEntries {
            let merged = Self.mergedEntries(library: entries, base: base.entries, edited: edited.entries)
            if merged != entries {
                entries = merged
            }
        }
        if includingSessionContent {
            applyModuleUndo(from: base, to: edited)
        } else {
            applyModuleEdit(from: base, to: edited)
        }
    }

    /// Whether applying the edit `base` → `edited` (without its file) would change anything: an
    /// edit that only replaced the file leaves no undo step. See CODE_AUDIT_Edit_Save §5.3.
    @MainActor static func hasUndoableChange(from base: Self, to edited: Self) -> Bool {
        var probe = base.copy()
        probe.applyEdit(from: base, to: edited, includingSessionContent: true, includingFile: false)
        return !probe.isEqual(other: base)
    }

    /// The library entries with the edit (`base` → `edited`) applied: entries removed by the
    /// edit are removed, changed ones merged field by field (`EntryDataAccessible.applyEdit`),
    /// new ones inserted at their edited position (clamped). Library entries the edit never saw
    /// stay where they are. An entry counts as changed by its content, not by its CRDT clocks:
    /// an editor that assigned every entry again changed none. See CODE_AUDIT_Edit_Save §5.11, §5.12.
    @MainActor static func mergedEntries(library: [Entry], base: [Entry], edited: [Entry]) -> [Entry] {
        var baseById: [UUID: Entry] = [:]
        for entry in base { baseById[entry.id] = baseById[entry.id] ?? entry }
        let editedIds = Set(edited.map(\.id))

        var result = library.filter { baseById[$0.id] == nil || editedIds.contains($0.id) }
        for (index, entry) in edited.enumerated() {
            let baseEntry = baseById[entry.id]
            if let baseEntry, isSameEntry(baseEntry, entry) { continue }
            if let existing = result.firstIndex(where: { $0.id == entry.id }) {
                if let baseEntry {
                    result[existing].applyEdit(from: baseEntry, to: entry)
                } else {
                    result[existing] = entry
                }
            } else {
                result.insert(entry, at: min(index, result.count))
            }
        }
        return reordered(result, base: base, edited: edited)
    }

    /// Content equality of two entries, without the CRDT clocks `==` includes.
    @MainActor private static func isSameEntry(_ lhs: Entry, _ rhs: Entry) -> Bool {
        guard lhs != rhs else { return true }
        guard let comparable = lhs as? any ItemDiffComparable else { return false }
        return isSame(comparable, rhs) && lhs.displayState == rhs.displayState
    }

    @MainActor private static func isSame<Value: ItemDiffComparable>(_ lhs: Value, _ rhs: Entry) -> Bool {
        guard let rhs = rhs as? Value else { return false }
        return lhs.isSame(rhs)
    }

    /// A move changes no entry, so the loop above keeps the library's order. When the edit
    /// reordered the entries it saw, those entries take the edited order in the places they hold;
    /// library entries the edit never saw stay where they are.
    nonisolated private static func reordered(_ result: [Entry], base: [Entry], edited: [Entry]) -> [Entry] {
        var editedPosition: [UUID: Int] = [:]
        for (index, entry) in edited.enumerated() where editedPosition[entry.id] == nil {
            editedPosition[entry.id] = index
        }
        let baseIds = Set(base.map(\.id))
        let editedOrder = edited.map(\.id).filter { baseIds.contains($0) }
        let baseOrder = base.map(\.id).filter { editedPosition[$0] != nil }
        guard editedOrder != baseOrder else { return result }

        var reordered = result
        let slots = reordered.indices.filter { editedPosition[reordered[$0].id] != nil }
        let ordered = slots.map { reordered[$0] }.sorted {
            editedPosition[$0.id, default: 0] < editedPosition[$1.id, default: 0]
        }
        for (slot, entry) in zip(slots, ordered) {
            reordered[slot] = entry
        }
        return reordered
    }
}
