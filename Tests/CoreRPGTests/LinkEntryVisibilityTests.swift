// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

@MainActor
@Suite("Link list entry visibility")
struct LinkEntryVisibilityTests {
    @Test("A selection list shows entries only when an entry can be selected", arguments: [LinkRootType.selection, .selectionInline])
    func selectionListFollowsEntrySelection(type: LinkRootType) {
        #expect(!ItemSelectionModel(allowEntrySelection: false).showsEntries(in: type, module: .table))
        #expect(ItemSelectionModel(allowEntrySelection: true).showsEntries(in: type, module: .table))
        #expect(ItemSelectionModel(onlyEntrySelection: true).showsEntries(in: type, module: .table))
    }

    @Test("An inspector hides the entries of characters unless an entry can be selected")
    func inspectorHidesCharacterEntries() {
        // Other modules link a character as a whole; the Character module selects its entries.
        #expect(!ItemSelectionModel(allowEntrySelection: false).showsEntries(in: .inspector, module: .value))
        #expect(ItemSelectionModel(allowEntrySelection: true).showsEntries(in: .inspector, module: .value))
        #expect(ItemSelectionModel(onlyEntrySelection: true).showsEntries(in: .inspector, module: .value))
    }

    @Test("An inspector keeps the entries of every other module", arguments: [NetworkModules.table, .pdf, .dice, .photo, .map])
    func inspectorShowsOtherEntries(module: NetworkModules) {
        #expect(ItemSelectionModel(allowEntrySelection: false).showsEntries(in: .inspector, module: module))
    }

    @Test("The link window always shows entries", arguments: [NetworkModules.table, .value])
    func linkWindowShowsEntries(module: NetworkModules) {
        #expect(ItemSelectionModel(allowEntrySelection: false).showsEntries(in: .window, module: module))
    }

    @Test("A row with an entry of its own item is an entry row")
    func entryOfOwnItemIsEntryRow() {
        // Given
        let entryId = UUID()
        let model = FakeItemModel(name: "Item", entries: [FakeEntryModel(id: entryId, childId: UUID(), name: "Entry", content: "")])

        // When
        let row = makeRow(model: model, entryId: entryId)

        // Then
        #expect(row.isEntryRow)
    }

    @Test("A folder member row carries its parent's entry id and stays an item row")
    func folderMemberIsItemRow() {
        // Given
        let model = FakeItemModel(name: "Member", entries: [FakeEntryModel(id: UUID(), childId: UUID(), name: "Entry", content: "")])

        // When
        let member = makeRow(model: model, entryId: UUID())
        let topLevel = makeRow(model: model, entryId: nil)

        // Then
        #expect(!member.isEntryRow)
        #expect(!topLevel.isEntryRow)
    }

    private func makeRow(model: FakeItemModel, entryId: UUID?) -> FolderListItemModel {
        let row = FolderListItemModel(
            id: entryId ?? model.id,
            source: ItemRowModel(itemId: model.id, entryId: entryId, typeId: .none),
            level: 0,
            isShown: false
        )
        row.model = model
        return row
    }
}
