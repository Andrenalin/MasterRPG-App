// @copyright André Trettin

@testable import CoreRPG
import Foundation
import Testing

@testable import CharacterRPG

/// Character A has an entry B that is a group (`valueId` points to the hidden group item C, which holds
/// entry D). A newer version of A turns B into a plain entry that holds D's content, so C is no longer
/// referenced. After the import C (and every group nested in C) must be gone, not stay as a hidden,
/// unreachable item.
@MainActor
struct ImportRemovedGroupTests {
    private struct Fixture {
        let characterId: UUID
        let entryBId: UUID
        let groupCId: UUID
        let entryDId: UUID
        /// A group nested in C (C → entry F → group E → entry G), when requested.
        let nestedGroupEId: UUID?
        let nestedEntryGId: UUID?
        /// The export of A with its groups, before the change.
        let olderData: Data
        /// The export of A after B became a plain entry, so without any group.
        let newerData: Data
    }

    private let contentOfD = "Axe Mastery 12"

    private func makeRoot() async throws -> CharacterRootModel {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        return root
    }

    private func exportData(of itemId: UUID, in root: CharacterRootModel) async throws -> Data {
        let ids = root.exportController.exporting(itemIds: ItemModuleIds(ids: Set([itemId]), module: .value))
        let stream = OutputStream.toMemory()
        stream.open()
        defer { stream.close() }
        _ = try await root.exportController.export(itemIds: ids, into: stream)
        return try #require(stream.property(forKey: Stream.PropertyKey.dataWrittenToMemoryStreamKey) as? Data)
    }

    private func importData(_ data: Data, into root: CharacterRootModel, forceSave: Bool) async throws {
        let stream = InputStream(data: data)
        stream.open()
        defer { stream.close() }
        try await root.importController.importStream(from: stream, forceSave: forceSave)
    }

    /// Builds A → B → C → D (and optionally C → F → E → G), exports it, then turns B into a plain entry
    /// with D's content, and exports the result as the newer version. The library is empty afterwards.
    private func makeFixture(in root: CharacterRootModel, nestedGroup: Bool) async throws -> Fixture {
        let edit = root.editController
        let characterId = await root.itemController.addNew(type: .item)
        edit.reset(name: "Thorin", itemId: characterId)

        let entryBId = await edit.addNewGroup(itemId: characterId)
        edit.update(itemId: characterId, entryId: entryBId, name: "Combat Skills", content: "")
        let groupCId = try #require(root.itemController.itemOrEmpty(for: characterId).entries.first { $0.id == entryBId }?.valueId)

        let entryD = ValueEntryModel(id: UUID(), name: "Axe Mastery", type: .text, value: contentOfD)
        let entryDId = entryD.id
        edit.add(entry: entryD, itemId: groupCId)

        var nestedGroupEId: UUID?
        var nestedEntryGId: UUID?
        if nestedGroup {
            let entryFId = await edit.addNewGroup(itemId: groupCId)
            edit.update(itemId: groupCId, entryId: entryFId, name: "Weapons", content: "")
            let groupEId = try #require(root.itemController.itemOrEmpty(for: groupCId).entries.first { $0.id == entryFId }?.valueId)
            let entryG = ValueEntryModel(id: UUID(), name: "Sword", type: .text, value: "Sword 8")
            let entryGId = entryG.id
            edit.add(entry: entryG, itemId: groupEId)
            nestedGroupEId = groupEId
            nestedEntryGId = entryGId
        }

        let character = root.itemController.itemOrEmpty(for: characterId)
        #expect(character.entries.first { $0.id == entryBId }?.valueId == groupCId)
        let olderData = try await exportData(of: characterId, in: root)

        // The newer version: B is a plain entry with the content of D, the group is gone.
        let newer = try #require(edit.editModel(for: characterId))
        var entryB = try #require(newer.entries.first { $0.id == entryBId })
        entryB.valueId = nil
        entryB.value = contentOfD
        newer.entries = newer.entries.map { $0.id == entryBId ? entryB : $0 }
        edit.save(updated: newer, message: "B becomes a plain entry")
        let newerData = try await exportData(of: characterId, in: root)
        #expect(newerData != olderData)

        try await MockRoot.resetTestData(for: root)
        return Fixture(
            characterId: characterId,
            entryBId: entryBId,
            groupCId: groupCId,
            entryDId: entryDId,
            nestedGroupEId: nestedGroupEId,
            nestedEntryGId: nestedEntryGId,
            olderData: olderData,
            newerData: newerData
        )
    }

    /// A group item that is still in the library, whether visible or hidden. A soft-deleted item does not count.
    private func isInLibrary(_ itemId: UUID, in root: CharacterRootModel) -> Bool {
        guard root.itemController.itemDataModel.items.contains(itemId) else { return false }
        return root.itemController.itemSync(for: itemId)?.isHidden != true
    }

    @Test("A newer import without the group removes the group item C", arguments: [false, true])
    func importRemovesGroup(forceSave: Bool) async throws {
        let root = try await makeRoot()
        let fixture = try await makeFixture(in: root, nestedGroup: false)

        try await importData(fixture.olderData, into: root, forceSave: forceSave)
        #expect(isInLibrary(fixture.characterId, in: root))
        #expect(isInLibrary(fixture.groupCId, in: root))
        let before = root.itemController.itemOrEmpty(for: fixture.characterId)
        #expect(before.entries.first { $0.id == fixture.entryBId }?.valueId == fixture.groupCId)

        try await importData(fixture.newerData, into: root, forceSave: forceSave)

        let after = root.itemController.itemOrEmpty(for: fixture.characterId)
        let entryB = try #require(after.entries.first { $0.id == fixture.entryBId })
        #expect(entryB.valueId == nil)
        #expect(entryB.content == contentOfD)
        #expect(isInLibrary(fixture.groupCId, in: root) == false)
    }

    @Test("A newer import without the group also removes the groups nested in C", arguments: [false, true])
    func importRemovesNestedGroups(forceSave: Bool) async throws {
        let root = try await makeRoot()
        let fixture = try await makeFixture(in: root, nestedGroup: true)
        let nestedGroupId = try #require(fixture.nestedGroupEId)

        try await importData(fixture.olderData, into: root, forceSave: forceSave)
        #expect(isInLibrary(fixture.groupCId, in: root))
        #expect(isInLibrary(nestedGroupId, in: root))

        try await importData(fixture.newerData, into: root, forceSave: forceSave)

        let entryB = try #require(root.itemController.itemOrEmpty(for: fixture.characterId).entries.first { $0.id == fixture.entryBId })
        #expect(entryB.valueId == nil)
        #expect(isInLibrary(fixture.groupCId, in: root) == false)
        #expect(isInLibrary(nestedGroupId, in: root) == false)
    }
}
