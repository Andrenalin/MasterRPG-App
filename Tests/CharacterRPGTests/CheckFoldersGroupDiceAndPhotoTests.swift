// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import CharacterRPG

/// The sheet shows no dice and no photo for an item that is a group (an item an entry points to
/// with `valueId`, see `SheetController`). Validate Data removes what such an item still carries,
/// and must not give it a dice back from its own entries.
@Suite("checkFolders – group dice and photo")
@MainActor
struct CheckFoldersGroupDiceAndPhotoTests {
    private struct Group {
        let ownerId: UUID
        let childId: UUID
    }

    /// An owner with one group entry that points to a hidden group item. `childFirst` decides which
    /// of the two the repair visits first.
    private func makeGroup(
        in root: CharacterRootModel,
        childFirst: Bool = false,
        childDiceId: UUID? = nil,
        childPhotoId: UUID? = nil,
        childPhotos: [UUID] = [],
        childEntries: [ValueEntryModel] = [],
        ownerDiceId: UUID? = nil,
        ownerPhotoId: UUID? = nil
    ) async -> Group {
        let ownerId: UUID
        let childId: UUID
        if childFirst {
            childId = await root.itemController.addNew(type: .item)
            ownerId = await root.itemController.addNew(type: .item)
        } else {
            ownerId = await root.itemController.addNew(type: .item)
            childId = await root.itemController.addNew(type: .item)
        }

        let child = root.itemController.itemOrEmpty(for: childId)
        child.name = "Skills"
        // A group item is an `.entry`; the legacy `.item` category would be migrated (and tagged) by the repair.
        child.category = .entry
        child.displayState = 1
        child.groupId = ownerId
        child.parentId = nil
        child.diceId = childDiceId
        child.photoId = childPhotoId
        child.photos = childPhotos
        child.entries = childEntries
        root.itemController.replace(model: child, isInsert: false)

        let owner = root.itemController.itemOrEmpty(for: ownerId)
        owner.entries.append(ValueEntryModel(id: UUID(), name: "Skills", type: .text, value: "", valueId: childId))
        owner.diceId = ownerDiceId
        owner.photoId = ownerPhotoId
        root.itemController.replace(model: owner, isInsert: false)
        return Group(ownerId: ownerId, childId: childId)
    }

    private func makeRoot() async throws -> CharacterRootModel {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        return root
    }

    private func encoded(_ itemId: UUID, in root: CharacterRootModel) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(root.itemController.itemOrEmpty(for: itemId))
    }

    // MARK: - Removing

    @Test("A group item loses its dice, photo and photo list", arguments: [false, true])
    func groupItemLosesDiceAndPhotos(childFirst: Bool) async throws {
        let root = try await makeRoot()
        let photoId = UUID()
        let group = await makeGroup(in: root, childFirst: childFirst, childDiceId: UUID(), childPhotoId: photoId, childPhotos: [photoId, UUID()])

        await root.checkFolders(reportModel: ValidateRepairModel())

        let child = root.itemController.itemOrEmpty(for: group.childId)
        #expect(child.diceId == nil)
        #expect(child.photoId == nil)
        #expect(child.photos.isEmpty)
    }

    @Test("A group item with only a dice loses just the dice")
    func groupItemWithOnlyDice() async throws {
        let root = try await makeRoot()
        let group = await makeGroup(in: root, childDiceId: UUID())

        await root.checkFolders(reportModel: ValidateRepairModel())

        let child = root.itemController.itemOrEmpty(for: group.childId)
        #expect(child.diceId == nil)
        #expect(child.photoId == nil)
    }

    @Test("A group item with only a photo loses just the photo")
    func groupItemWithOnlyPhoto() async throws {
        let root = try await makeRoot()
        let photoId = UUID()
        let group = await makeGroup(in: root, childPhotoId: photoId, childPhotos: [photoId])

        await root.checkFolders(reportModel: ValidateRepairModel())

        let child = root.itemController.itemOrEmpty(for: group.childId)
        #expect(child.photoId == nil)
        #expect(child.photos.isEmpty)
        #expect(child.diceId == nil)
    }

    @Test("The group item keeps its name, entries and group reference")
    func groupItemKeepsEverythingElse() async throws {
        let root = try await makeRoot()
        let childEntry = ValueEntryModel(id: UUID(), name: "Climb", type: .text, value: "5")
        let group = await makeGroup(in: root, childDiceId: UUID(), childPhotoId: UUID(), childEntries: [childEntry])

        await root.checkFolders(reportModel: ValidateRepairModel())

        let child = root.itemController.itemOrEmpty(for: group.childId)
        #expect(child.name == "Skills")
        #expect(child.groupId == group.ownerId)
        #expect(child.entries.map(\.id) == [childEntry.id])
        #expect(child.entries.first?.value == "5")
    }

    // MARK: - Not giving a dice back

    @Test("A group item is not given a dice from its own entries", arguments: [false, true])
    func groupItemIsNotBackfilledFromItsEntries(childFirst: Bool) async throws {
        let root = try await makeRoot()
        let entryDiceId = UUID()
        let childEntry = ValueEntryModel(id: UUID(), name: "Climb", type: .text, value: "5", diceId: entryDiceId)
        let group = await makeGroup(in: root, childFirst: childFirst, childDiceId: UUID(), childEntries: [childEntry])

        await root.checkFolders(reportModel: ValidateRepairModel())
        await root.checkFolders(reportModel: ValidateRepairModel())

        let child = root.itemController.itemOrEmpty(for: group.childId)
        #expect(child.diceId == nil)
        #expect(child.entries.first?.diceId == entryDiceId, "the entry's own dice stays")
    }

    @Test("A group item that never had a dice is not given one from its entries")
    func groupItemWithoutDiceStaysWithout() async throws {
        let root = try await makeRoot()
        let childEntry = ValueEntryModel(id: UUID(), name: "Climb", type: .text, value: "5", diceId: UUID())
        let group = await makeGroup(in: root, childEntries: [childEntry])

        await root.checkFolders(reportModel: ValidateRepairModel())

        #expect(root.itemController.itemOrEmpty(for: group.childId).diceId == nil)
    }

    // MARK: - Leaving other items alone

    @Test("The owner of a group keeps its own dice and photo")
    func ownerKeepsDiceAndPhoto() async throws {
        let root = try await makeRoot()
        let ownerDiceId = UUID()
        let ownerPhotoId = UUID()
        let group = await makeGroup(in: root, childDiceId: UUID(), childPhotoId: UUID(), ownerDiceId: ownerDiceId, ownerPhotoId: ownerPhotoId)

        await root.checkFolders(reportModel: ValidateRepairModel())

        let owner = root.itemController.itemOrEmpty(for: group.ownerId)
        #expect(owner.diceId == ownerDiceId)
        #expect(owner.photoId == ownerPhotoId)
    }

    @Test("An item that is no group keeps its dice and photo")
    func plainItemKeepsDiceAndPhoto() async throws {
        let root = try await makeRoot()
        let itemId = await root.itemController.addNew(type: .item)
        let diceId = UUID()
        let photoId = UUID()
        let item = root.itemController.itemOrEmpty(for: itemId)
        item.diceId = diceId
        item.photoId = photoId
        item.photos = [photoId]
        root.itemController.replace(model: item, isInsert: false)

        await root.checkFolders(reportModel: ValidateRepairModel())

        let after = root.itemController.itemOrEmpty(for: itemId)
        #expect(after.diceId == diceId)
        #expect(after.photoId == photoId)
        #expect(after.photos == [photoId])
    }

    @Test("An item that is no group is not given the dice of its first entry")
    func plainItemIsNotBackfilledFromEntries() async throws {
        let root = try await makeRoot()
        let itemId = await root.itemController.addNew(type: .item)
        let entryDiceId = UUID()
        let item = root.itemController.itemOrEmpty(for: itemId)
        item.entries = [ValueEntryModel(id: UUID(), name: "Climb", type: .text, value: "5", diceId: entryDiceId)]
        root.itemController.replace(model: item, isInsert: false)

        await root.checkFolders(reportModel: ValidateRepairModel())

        // The entry's dice belongs to the entry; validation no longer copies it to the item.
        // See CODE_AUDIT_26 §5.107.
        #expect(root.itemController.itemOrEmpty(for: itemId).diceId == nil)
    }

    @Test("A group nested in a group loses its dice and photo too")
    func nestedGroupItemLosesDiceAndPhoto() async throws {
        let root = try await makeRoot()
        let outer = await makeGroup(in: root, childDiceId: UUID(), childPhotoId: UUID())
        let innerId = await root.itemController.addNew(type: .item)
        let inner = root.itemController.itemOrEmpty(for: innerId)
        inner.displayState = 1
        inner.groupId = outer.childId
        inner.diceId = UUID()
        inner.photoId = UUID()
        root.itemController.replace(model: inner, isInsert: false)
        let middle = root.itemController.itemOrEmpty(for: outer.childId)
        middle.entries.append(ValueEntryModel(id: UUID(), name: "Nested", type: .text, value: "", valueId: innerId))
        root.itemController.replace(model: middle, isInsert: false)

        await root.checkFolders(reportModel: ValidateRepairModel())

        let nested = root.itemController.itemOrEmpty(for: innerId)
        #expect(nested.diceId == nil)
        #expect(nested.photoId == nil)
        #expect(root.itemController.itemOrEmpty(for: outer.childId).diceId == nil)
    }

    @Test("The group of a hidden owner is not touched")
    func groupOfHiddenOwnerIsNotTouched() async throws {
        let root = try await makeRoot()
        let diceId = UUID()
        let photoId = UUID()
        let group = await makeGroup(in: root, childDiceId: diceId, childPhotoId: photoId)
        let owner = root.itemController.itemOrEmpty(for: group.ownerId)
        owner.displayState = DisplayStateMask.totalHidden.rawValue
        root.itemController.replace(model: owner, isInsert: false)

        await root.checkFolders(reportModel: ValidateRepairModel())

        let child = root.itemController.itemOrEmpty(for: group.childId)
        #expect(child.diceId == diceId)
        #expect(child.photoId == photoId)
    }

    // MARK: - Repeated runs

    @Test("A repeated run leaves a repaired group item unchanged")
    func repeatedRunIsStable() async throws {
        let root = try await makeRoot()
        let childEntry = ValueEntryModel(id: UUID(), name: "Climb", type: .text, value: "5", diceId: UUID())
        let group = await makeGroup(in: root, childDiceId: UUID(), childPhotoId: UUID(), childEntries: [childEntry])

        await root.checkFolders(reportModel: ValidateRepairModel())
        let afterFirst = try encoded(group.childId, in: root)
        await root.checkFolders(reportModel: ValidateRepairModel())
        await root.checkFolders(reportModel: ValidateRepairModel())

        #expect(try encoded(group.childId, in: root) == afterFirst, "the group item's clocks must not move on a repeated run")
    }

    // MARK: - EditController.removeDice(itemId:)

    @Test("removeDice(itemId:) clears the item's dice and keeps its entries' dice")
    func removeDiceClearsItemDice() async throws {
        let root = try await makeRoot()
        let entryDiceId = UUID()
        let group = await makeGroup(in: root, childDiceId: UUID(), childEntries: [ValueEntryModel(id: UUID(), name: "Climb", type: .text, value: "5", diceId: entryDiceId)])

        root.editController.removeDice(itemId: group.childId)

        let child = root.itemController.itemOrEmpty(for: group.childId)
        #expect(child.diceId == nil)
        #expect(child.entries.first?.diceId == entryDiceId)
    }

    @Test("removeDice(itemId:) without a dice saves nothing")
    func removeDiceWithoutDiceIsNoOp() async throws {
        let root = try await makeRoot()
        let group = await makeGroup(in: root)
        let before = try encoded(group.childId, in: root)

        root.editController.removeDice(itemId: group.childId)

        #expect(try encoded(group.childId, in: root) == before)
    }
}
