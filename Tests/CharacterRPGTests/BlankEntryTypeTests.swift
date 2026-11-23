// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import CharacterRPG

/// CODE_AUDIT_28 §5.9: blank content turned a text entry into a number entry, which the sheet
/// shows as "= 0 Error".
@MainActor
struct BlankEntryTypeTests {
    @Test("Blank content keeps the type of an entry")
    func blankKeepsType() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        #expect(sut.termineType(content: "", currentType: .text) == .text)
        #expect(sut.termineType(content: "   ", currentType: .text) == .text)
        #expect(sut.termineType(content: "12", currentType: .text) == .number)
        #expect(sut.termineType(content: "", currentType: .number) == .number)
    }

    @Test("Clearing a text note keeps it a text entry")
    func clearingNoteKeepsText() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController
        let itemId = await root.itemController.addNew(type: .item)
        var entry = ValueEntryModel.empty
        entry.name = "Note"
        entry.type = .text
        entry.value = "Some prose"
        sut.add(entry: entry, itemId: itemId, forceSave: true)

        sut.update(itemId: itemId, entryId: entry.id, name: "Note", content: "", forceSave: true)

        let stored = root.itemController.itemOrEmpty(for: itemId)[entry.id]
        #expect(stored.type == .text)
    }

    @Test("A quick entry without content is a text entry")
    func blankQuickEntryIsText() async throws {
        let root = try await MockRoot.importTestData()

        #expect(root.editController.create(name: "Empty", content: "").type == .text)
    }
}
