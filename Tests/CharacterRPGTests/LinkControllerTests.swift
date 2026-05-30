// @copyright André Trettin

import CoreRPG
import Foundation
import DiceRPG
import PdfRPG
import PhotoRPG
import TableRPG
import RPGResourcesDebug
import Testing

@testable import CharacterRPG

struct LinkControllerTests {
    @Test func createGroup() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.linkController

        let itemId = await root.itemController.addNew(type: .item)
        let item = await root.itemController.item(for: itemId)?.copy()
        #expect(nil != item)
        let entryId = UUID()
        item!.entries.append(ValueEntryModel(id: entryId, name: "Some Value", type: .number, isGenerator: false, value: "27", diceId: nil, valueId: nil))
        await root.itemController.replace(model: item!, isInsert: false)

        var result = "**Some Value**: 27 "
        await #expect(sut.linkText(model: root.itemController.itemOrEmpty(for: itemId), entryId: entryId) == result)

        item![entryId].value = "27+2"
        await root.itemController.replace(model: item!, isInsert: false)

        result = "**Some Value**: 27+2 = 29"
        await #expect(sut.linkText(model: root.itemController.itemOrEmpty(for: itemId), entryId: entryId) == result)

        item![entryId].value = "27+2+3"
        await root.itemController.replace(model: item!, isInsert: false)

        result = "**Some Value**: 27+2+3 = 32"
        await #expect(sut.linkText(model: root.itemController.itemOrEmpty(for: itemId), entryId: entryId) == result)
    }
    
    @Test func toggleWithShareTogglerAndEditAction() async throws {
        let root = try await MockRoot.importTestData()
        
        let sut = await root.linkController
        let firstItem = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        let text = await sut.generateLink(itemId: firstItem.id)
        var result = await sut.toggleTextLink(linkNumber: 0, itemId: firstItem.id, entryId: nil, command: nil, in: text, shareResult: shareResult(), toggler: toggler(), editAction: editAction())
        var expectedText = "\(text)➡️[Share](RPG://VALUES/500/E8AB89DA-4BB7-4C6E-BD6F-88A5AC5A8358/share)[Show](RPG://VALUES/600/E8AB89DA-4BB7-4C6E-BD6F-88A5AC5A8358/show) Timo’s Character -- 11 Entries [Remove](RPG://VALUES/300/E8AB89DA-4BB7-4C6E-BD6F-88A5AC5A8358/remove)⬅️"
        #expect(result == expectedText)
        
        result = await sut.toggleTextLink(linkNumber: LinkType.share.linkNumberAddition, itemId: firstItem.id, entryId: nil, command: LinkType.share.rawValue, in: result, shareResult: shareResult(), toggler: toggler(), editAction: editAction())
        expectedText = "\(text)➡️[Share](RPG://VALUES/500/E8AB89DA-4BB7-4C6E-BD6F-88A5AC5A8358/share)[Show](RPG://VALUES/600/E8AB89DA-4BB7-4C6E-BD6F-88A5AC5A8358/show) Timo’s Character -- 11 Entries [Remove](RPG://VALUES/300/E8AB89DA-4BB7-4C6E-BD6F-88A5AC5A8358/remove)⬅️"
        #expect(result == expectedText)

        result = await sut.toggleTextLink(linkNumber: LinkType.remove.linkNumberAddition, itemId: firstItem.id, entryId: nil, command: LinkType.remove.rawValue, in: result, shareResult: shareResult(), toggler: toggler(), editAction: editAction())
        #expect(result == "Adalbert Unheil")
    }
    
    // MARK: - validateParentId

    /// Folder: 3 items, each with 3 groups.
    /// Before validateParentId: items have parentId set; groups have groupId but nil parentId; every item entry has valueId.
    /// After validateParentId: groups have parentId set to their parent item's id.
    @Test func validateParentIdSetsParentIdOnGroupChildren() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.linkController
        let editController = await root.editController

        // Build: folder → [Charlie, Alpha, Bravo] added in non-alphabetical order
        let folderId = await root.itemController.addNew(type: .folder)
        let charlieId = await root.itemController.addNew(type: .item)
        await editController.reset(name: "Charlie", itemId: charlieId)
        let alphaId = await root.itemController.addNew(type: .item)
        await editController.reset(name: "Alpha", itemId: alphaId)
        let bravoId = await root.itemController.addNew(type: .item)
        await editController.reset(name: "Bravo", itemId: bravoId)
        // itemIds stays in creation order; folder entries will be sorted
        let itemIds = [charlieId, alphaId, bravoId]

        for itemId in itemIds {
            await editController.addItem(itemId: itemId, parentId: folderId)
        }

        // addNewGroup returns the entry id; entry.valueId is the group item id
        var groupsByItem: [UUID: [UUID]] = [:]
        for itemId in itemIds {
            var groupItemIds: [UUID] = []
            for _ in 0..<3 {
                let entryId = await editController.addNewGroup(itemId: itemId)
                let item = await root.itemController.itemOrEmpty(for: itemId)
                let entry = try #require(item.entries.first(where: { $0.id == entryId }))
                let groupItemId = try #require(entry.valueId)
                groupItemIds.append(groupItemId)
            }
            groupsByItem[itemId] = groupItemIds
        }

        // Folder has exactly 3 entries, sorted alphabetically regardless of insertion order
        let folder = await root.itemController.itemOrEmpty(for: folderId)
        try #require(folder.entries.count == 3)
        let alphabeticalIds = [alphaId, bravoId, charlieId]
        for (index, itemId) in alphabeticalIds.enumerated() {
            #expect(folder.entries[index].childId == itemId)
        }

        // Items: parentId points to the folder
        for itemId in itemIds {
            let item = await root.itemController.itemOrEmpty(for: itemId)
            #expect(item.parentId == folderId)
        }

        // Items: 3 entries, every entry has valueId set (the group child)
        // Groups: parentId == nil before validateParentId, groupId == parent item id
        for itemId in itemIds {
            let item = await root.itemController.itemOrEmpty(for: itemId)
            #expect(item.entries.count == 3)
            #expect(item.entries.allSatisfy { $0.valueId != nil })

            let groupItemIds = try #require(groupsByItem[itemId])
            for groupItemId in groupItemIds {
                let group = await root.itemController.itemOrEmpty(for: groupItemId)
                #expect(group.parentId == nil)
                #expect(group.groupId == itemId)
            }
        }

        // validateParentId must set parentId on every group child that had nil parentId
        await sut.validateParentId()

        for itemId in itemIds {
            let groupItemIds = try #require(groupsByItem[itemId])
            for groupItemId in groupItemIds {
                let group = await root.itemController.itemOrEmpty(for: groupItemId)
                // Items live in the folder → groups inherit the folder as parentId
                #expect(group.parentId == folderId)
                #expect(group.groupId == itemId)
            }
        }
    }

    /// When the item that owns the group is itself inside a folder, the group must
    /// inherit the folder as its parentId — not the item's own id.
    @Test func validateParentIdSetsParentIdToFolderWhenItemIsInFolder() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.linkController
        let editController = await root.editController

        let folderId = await root.itemController.addNew(type: .folder)
        let itemId = await root.itemController.addNew(type: .item)
        await editController.addItem(itemId: itemId, parentId: folderId)

        let entryId = await editController.addNewGroup(itemId: itemId)
        let item = await root.itemController.itemOrEmpty(for: itemId)
        let entry = try #require(item.entries.first(where: { $0.id == entryId }))
        let groupItemId = try #require(entry.valueId)

        // Pre-conditions: item is in folder; group has groupId set but no parentId yet
        #expect(item.parentId == folderId)
        let groupBefore = await root.itemController.itemOrEmpty(for: groupItemId)
        #expect(groupBefore.groupId == itemId)
        #expect(groupBefore.parentId == nil)

        await sut.validateParentId()

        // Group must get parentId = folderId, not itemId, because the item lives in the folder
        let groupAfter = await root.itemController.itemOrEmpty(for: groupItemId)
        #expect(groupAfter.parentId == folderId)
        #expect(groupAfter.groupId == itemId)
    }

    /// When a group child already has a parentId pointing to a different item,
    /// validateParentId must leave the data unchanged (it only logs the conflict).
    @Test func validateParentIdDoesNotOverwriteExistingParentId() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.linkController
        let editController = await root.editController

        let itemId = await root.itemController.addNew(type: .item)
        let otherId = await root.itemController.addNew(type: .item)

        let entryId = await editController.addNewGroup(itemId: itemId)
        let item = await root.itemController.itemOrEmpty(for: itemId)
        let entry = try #require(item.entries.first(where: { $0.id == entryId }))
        let groupItemId = try #require(entry.valueId)

        // Manually point the group's parentId to a different item
        let group = await root.itemController.itemOrEmpty(for: groupItemId)
        group.parentId = otherId
        await root.itemController.replace(model: group, isInsert: false)

        await sut.validateParentId()

        // parentId must remain unchanged (conflict is only logged, not corrected)
        let groupAfter = await root.itemController.itemOrEmpty(for: groupItemId)
        #expect(groupAfter.parentId == otherId)
    }

    @MainActor
    private func shareResult() -> ShareValueResult {
        ShareValueResult.preview()
    }
    
    private func toggler() -> ((UUID, NetworkModules) async -> Void) {
        { _, _ in }
    }
    
    private func editAction() -> ((ItemRowModel) -> Bool) {
        { _ in true }
    }
}
