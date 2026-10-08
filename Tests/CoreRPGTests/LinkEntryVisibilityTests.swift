// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

@MainActor
@Suite("Link list entry visibility")
struct LinkEntryVisibilityTests {
    @Test("A selection list shows entries only when an entry can be selected", arguments: [LinkRootType.selection, .selectionInline])
    func selectionListFollowsEntrySelection(type: LinkRootType) {
        #expect(!ItemSelectionModel(allowEntrySelection: false).showsEntries(in: type))
        #expect(ItemSelectionModel(allowEntrySelection: true).showsEntries(in: type))
        #expect(ItemSelectionModel(onlyEntrySelection: true).showsEntries(in: type))
    }

    @Test("The inspector and the link window always show entries", arguments: [LinkRootType.inspector, .window])
    func browsingListShowsEntries(type: LinkRootType) {
        #expect(ItemSelectionModel(allowEntrySelection: false).showsEntries(in: type))
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
