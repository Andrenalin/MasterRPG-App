// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG
@testable import CharacterRPG

/// A formula entry links to an entry inside a group (`group c / entry d`). The linked entry then
/// moves out of its group to the character's root and into another group; the formula keeps
/// calculating the whole time.
@MainActor
struct LinkCalculationMovedEntryTests {
    private struct Fixture {
        let root: CharacterRootModel
        /// Character A.
        let characterId: UUID
        /// Group entry b on A, its group item c and the entry d inside c (value 12).
        let groupEntryBId: UUID
        let groupCId: UUID
        let entryDId: UUID
        /// Number entry e on A: `3 + link(c/d)`.
        let entryEId: UUID
        /// Second group entry f on A, its group item g and the entry h inside g (value 5).
        let groupEntryFId: UUID
        let groupGId: UUID
        let entryHId: UUID
    }

    private func makeFixture() async throws -> Fixture {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let edit = root.editController

        let characterId = await root.itemController.addNew(type: .item)
        edit.reset(name: "Hero", itemId: characterId)

        // Entry b with group c, which holds entry d.
        let groupEntryBId = await edit.addNewGroup(itemId: characterId)
        let groupCId = try #require(root.itemController.itemOrEmpty(for: characterId)[groupEntryBId].valueId)
        let entryD = ValueEntryModel(id: UUID(), name: "Strength", type: .number, value: "12")
        edit.add(entry: entryD, itemId: groupCId)

        // Entry e on A: a formula that links to c / d.
        let entryE = ValueEntryModel(id: UUID(), name: "Bonus", type: .number, value: "3")
        edit.add(entry: entryE, itemId: characterId)
        edit.add(link: "Strength", module: .value, itemId: groupCId, entryId: entryD.id, destinationItemId: characterId, destinationEntryId: entryE.id)

        // A second group entry f with group g, which holds entry h.
        let groupEntryFId = await edit.addNewGroup(itemId: characterId)
        let groupGId = try #require(root.itemController.itemOrEmpty(for: characterId)[groupEntryFId].valueId)
        let entryH = ValueEntryModel(id: UUID(), name: "Mana", type: .number, value: "5")
        edit.add(entry: entryH, itemId: groupGId)

        return Fixture(
            root: root, characterId: characterId,
            groupEntryBId: groupEntryBId, groupCId: groupCId, entryDId: entryD.id,
            entryEId: entryE.id,
            groupEntryFId: groupEntryFId, groupGId: groupGId, entryHId: entryH.id
        )
    }

    private func calculatedE(_ fixture: Fixture) -> String? {
        let entryE = fixture.root.itemController.itemOrEmpty(for: fixture.characterId)[fixture.entryEId]
        return fixture.root.linkController.calculate(entry: entryE)
    }

    /// The item the formula's link to d names.
    private func linkedItemId(_ fixture: Fixture) -> UUID? {
        let value = fixture.root.itemController.itemOrEmpty(for: fixture.characterId)[fixture.entryEId].value
        return LinkReplaceController.links(for: value).first { $0.entryId == fixture.entryDId }?.itemId
    }

    private func entryIds(of itemId: UUID, in fixture: Fixture) -> [UUID] {
        fixture.root.itemController.itemOrEmpty(for: itemId).entries.map(\.id)
    }

    @Test func formulaCalculatesWhileLinkedEntryMovesOutOfAndIntoGroups() async throws {
        let fixture = try await makeFixture()
        let edit = fixture.root.editController

        // The links point at c / d, and e is the number the link produces.
        let entryE = fixture.root.itemController.itemOrEmpty(for: fixture.characterId)[fixture.entryEId]
        #expect(entryE.value.contains(fixture.entryDId.uuidString), Comment(rawValue: entryE.value))
        #expect(entryIds(of: fixture.groupCId, in: fixture).contains(fixture.entryDId))
        #expect(calculatedE(fixture) == "15", "3 + 12 while d is in group c")
        #expect(linkedItemId(fixture) == fixture.groupCId)

        // Move d out of c to the root of the character.
        edit.moveOutOfGroup(
            itemId: fixture.groupCId, sourceEntryId: fixture.entryDId,
            parent: FolderRepresentable(id: fixture.characterId, name: "Hero")
        )
        #expect(!entryIds(of: fixture.groupCId, in: fixture).contains(fixture.entryDId))
        #expect(entryIds(of: fixture.characterId, in: fixture).contains(fixture.entryDId), "d is a root entry of A now")
        #expect(calculatedE(fixture) == "15", "e still calculates after d moved to the root")
        #expect(linkedItemId(fixture) == fixture.characterId, "the link names A, which holds d now")

        // Move d into group g.
        edit.move(
            itemId: fixture.characterId, sourceEntryId: fixture.entryDId,
            into: FolderRepresentable(id: fixture.groupGId, name: "Magic")
        )
        #expect(!entryIds(of: fixture.characterId, in: fixture).contains(fixture.entryDId))
        #expect(entryIds(of: fixture.groupGId, in: fixture).contains(fixture.entryDId), "d is in group g now")
        #expect(calculatedE(fixture) == "15", "e still calculates after d moved into group g")
        #expect(linkedItemId(fixture) == fixture.groupGId, "the link names group g, which holds d now")
    }

    /// The inspector keeps one cached row per entry id. A row for an entry that moved kept naming
    /// the item the entry left, resolved an empty entry there and showed nothing, and a new
    /// search reused that row.
    @Test func inspectorShowsAMovedEntryUnderItsNewItem() async throws {
        let fixture = try await makeFixture()
        let edit = fixture.root.editController
        let controller = fixture.root.folderLinkController
        let character = try #require(fixture.root.itemController.itemSync(for: fixture.characterId))

        controller.resetDetail(model: character)
        await controller.performDetailSearch()
        func detailList() -> [FolderListItemModel] { controller.listModel.detailListModel?.list ?? [] }
        func rowD() -> FolderListItemModel? { detailList().first { $0.source.entryId == fixture.entryDId } }

        // Open both groups, so d shows in c.
        for groupEntryId in [fixture.groupEntryBId, fixture.groupEntryFId] {
            let groupRow = try #require(detailList().first { $0.source.entryId == groupEntryId })
            controller.toggleFolder(item: groupRow)
        }
        var row = try #require(rowD())
        #expect(row.source.itemId == fixture.groupCId)
        #expect(row.isEntryRow)

        // d moves out of c to the root of A.
        edit.moveOutOfGroup(
            itemId: fixture.groupCId, sourceEntryId: fixture.entryDId,
            parent: FolderRepresentable(id: fixture.characterId, name: "Hero")
        )
        await controller.performDetailSearch()
        row = try #require(rowD(), "d is listed after it moved to the root")
        #expect(row.source.itemId == fixture.characterId, "the row names A, which holds d now")
        #expect(row.isEntryRow, "the row resolves d, so it shows its text")
        #expect(row.model?.id == fixture.characterId)

        // d moves into group g.
        edit.move(
            itemId: fixture.characterId, sourceEntryId: fixture.entryDId,
            into: FolderRepresentable(id: fixture.groupGId, name: "Magic")
        )
        await controller.performDetailSearch()
        row = try #require(rowD(), "d is listed after it moved into g")
        #expect(row.source.itemId == fixture.groupGId, "the row names g, which holds d now")
        #expect(row.isEntryRow)
        #expect(row.model?.id == fixture.groupGId)
    }
}
