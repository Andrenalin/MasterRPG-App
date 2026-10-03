// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_Folder §5: list, merge and game-memory rules that need no module root.
@Suite("Folder audit model fixes")
@MainActor
struct FolderAuditModelTests {
    @Test("Multi-select maps the rows of folder children to their item ids (§5.7)")
    func selectionItemIdsAreItemIds() {
        let rootItemId = UUID()
        let childItemId = UUID()
        let rootRow = FolderListItemModel(
            id: rootItemId,
            source: ItemRowModel(itemId: rootItemId, typeId: .photo),
            destination: nil,
            level: 0,
            isShown: false
        )
        let childRowId = UUID()
        let childRow = FolderListItemModel(
            id: childRowId,
            source: ItemRowModel(itemId: childItemId, entryId: childRowId, typeId: .photo),
            destination: nil,
            level: 1,
            isShown: false
        )
        let model = FolderListModel(navigationModel: ModuleNavigationModel())
        model.list = [rootRow, childRow]
        model.update(selectionMode: true)
        model.update(selection: [rootRow.id, childRow.id])

        #expect(Set(model.selectionItemIds) == [rootItemId, childItemId])
    }

    @Test("A member listed twice gets one row id per occurrence (§5.17)")
    func repeatedMembersGetDistinctRowIds() {
        let memberId = UUID()
        let otherId = UUID()
        // Entries whose id is the member id, as in Adventure, Character, Map, Table, Dice, Pdf, Rule.
        let collection = FakeItemModel(
            name: "Collection",
            category: .collection,
            entries: [
                FakeEntryModel(id: memberId, childId: memberId, name: "", content: ""),
                FakeEntryModel(id: otherId, childId: otherId, name: "", content: ""),
                FakeEntryModel(id: memberId, childId: memberId, name: "", content: "")
            ]
        )

        let rowIds = collection.memberRowIds()

        #expect(rowIds.count == 3)
        #expect(Set(rowIds).count == 3)
        #expect(rowIds[0] == memberId.childPath(of: collection.id))
        #expect(!rowIds.contains(memberId))
    }

    @Test("Entries with their own ids keep them as row ids (§5.17)")
    func separateEntryIdsAreRowIds() {
        let entryId = UUID()
        let collection = FakeItemModel(
            name: "Album",
            category: .album,
            entries: [FakeEntryModel(id: entryId, childId: UUID(), name: "", content: "")]
        )

        #expect(collection.memberRowIds() == [entryId])
    }

    private struct Entry: Equatable {
        let id: UUID
        let childId: UUID
        let name: String
    }

    @Test("The folder union lists a member once, whatever its entry ids (§5.18)")
    func folderUnionDeduplicatesByMember() {
        let photoId = UUID()
        let local = [Entry(id: UUID(), childId: photoId, name: "Photo")]
        let remote = [Entry(id: UUID(), childId: photoId, name: "Photo")]

        let merged = FolderEntryMerge.merged(local: local, remote: remote, id: \.id, name: \.name, childId: \.childId)
        let mergedReversed = FolderEntryMerge.merged(local: remote, remote: local, id: \.id, name: \.name, childId: \.childId)

        #expect(merged.map(\.childId) == [photoId])
        #expect(merged == mergedReversed, "the kept entry does not depend on which side is local")
    }

    @Test("A staged saved game does not shadow the library until the game starts (§5.25)")
    func stagedSavedGameDoesNotShadowLibrary() {
        let itemId = UUID()
        let model = ItemDataModel(categoryTags: [])
        model.itemData[itemId] = FakeItemModel(id: itemId, name: "Library")
        model.gameItemData[itemId] = FakeItemModel(id: itemId, name: "Saved")
        model.isSavedGameStaged = true

        #expect((model.item(for: itemId) as? FakeItemModel)?.name == "Library")

        model.isGameMode = true
        #expect((model.item(for: itemId) as? FakeItemModel)?.name == "Saved")

        model.resetGame()
        #expect(model.isSavedGameStaged == false)
    }

    @Test("A running game's copies are preferred as before (§5.25)")
    func gameCopiesArePreferredWithoutStagedSave() {
        let itemId = UUID()
        let model = ItemDataModel(categoryTags: [])
        model.itemData[itemId] = FakeItemModel(id: itemId, name: "Library")
        model.gameItemData[itemId] = FakeItemModel(id: itemId, name: "Game")

        #expect((model.item(for: itemId) as? FakeItemModel)?.name == "Game")
        #expect((model.item(for: itemId, noGame: true) as? FakeItemModel)?.name == "Library")
    }
}
