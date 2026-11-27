// @copyright André Trettin

import Foundation

public extension ItemDataAccessible {
    /// Applies to `self` (the library copy) only what `edited` changed relative to `base` (the
    /// game copy the edit started from): the changed header fields, and the entries that were
    /// added, changed or removed. Everything else keeps the library's value, so a forced save
    /// during a game does not write the game's session state into the library.
    /// See CODE_AUDIT_29 §5.2.
    ///
    /// Covers the properties every item has. Module-specific properties outside `entries` are not
    /// edited by the forced editors (header editor, entry editors, add-entry) and are left alone.
    @MainActor mutating func applyEdit(from base: Self, to edited: Self) {
        if base.name != edited.name { name = edited.name }
        if base.description != edited.description { description = edited.description }
        if base.category != edited.category { category = edited.category }
        if base.tags != edited.tags { tags = edited.tags }
        if base.displayState != edited.displayState { displayState = edited.displayState }
        if base.isGroupHiddenToggle != edited.isGroupHiddenToggle { isGroupHiddenToggle = edited.isGroupHiddenToggle }
        if base.fileUrl != edited.fileUrl { fileUrl = edited.fileUrl }
        if base.parentId != edited.parentId { parentId = edited.parentId }

        let merged = Self.mergedEntries(library: entries, base: base.entries, edited: edited.entries)
        if merged != entries {
            entries = merged
        }
    }

    /// The library entries with the edit (`base` → `edited`) applied: entries removed by the
    /// edit are removed, changed ones replaced in place, new ones inserted at their edited
    /// position (clamped). Library entries the edit never saw stay where they are.
    nonisolated static func mergedEntries(library: [Entry], base: [Entry], edited: [Entry]) -> [Entry] {
        var baseById: [UUID: Entry] = [:]
        for entry in base { baseById[entry.id] = baseById[entry.id] ?? entry }
        let editedIds = Set(edited.map(\.id))

        var result = library.filter { baseById[$0.id] == nil || editedIds.contains($0.id) }
        for (index, entry) in edited.enumerated() where baseById[entry.id] != entry {
            if let existing = result.firstIndex(where: { $0.id == entry.id }) {
                result[existing] = entry
            } else {
                result.insert(entry, at: min(index, result.count))
            }
        }
        return result
    }
}
