// @copyright André Trettin

import Foundation
import Testing

@testable import TableRPG

/// CODE_AUDIT_AppIntents3 §4.7: what "Roll on Table" says and returns.
@MainActor
@Suite("Table roll text")
struct TableRollTextTests {
    private func occurrence(_ name: String, depth: Int, entries: [TableGenerationEntry]) -> TableGenerationOccurrence {
        let occurrence = TableGenerationOccurrence(
            tableId: UUID(), tableName: name, tableType: .list, diceId: nil,
            entries: entries, depth: depth, tablePath: []
        )
        occurrence.selectedEntryIds = Set(entries.map(\.id))
        return occurrence
    }

    private func entry(_ name: String, _ content: String) -> TableGenerationEntry {
        TableGenerationEntry(id: UUID(), name: name, content: content, tableLinks: [])
    }

    @Test("Nested tables follow the entry that rolled them, named by their table")
    func nestedLines() {
        let root = occurrence("Encounter", depth: 0, entries: [
            entry("Goblin", "[Goblin](RPG://CHARACTERS/0/\(UUID().uuidString)) with a club")
        ])
        root.children = [occurrence("Weapon", depth: 1, entries: [entry("Club", "Club")])]
        #expect(TableRollText.lines(for: root) == ["Goblin — Goblin with a club", "Weapon: Club"])
    }

    @Test("Unselected entries are left out")
    func onlySelected() {
        let picked = entry("Gold", "")
        let root = occurrence("Loot", depth: 0, entries: [picked, entry("Gem", "")])
        root.selectedEntryIds = [picked.id]
        #expect(TableRollText.lines(for: root) == ["Gold"])
    }

    @Test("Siri reads at most the spoken limit")
    func spokenLimit() {
        let long = String(repeating: "a", count: TableRollText.spokenLimit + 50)
        #expect(TableRollText.spoken(["one", "two"]) == "one. two")
        #expect(TableRollText.spoken([long]).count == TableRollText.spokenLimit + 1)
    }
}
