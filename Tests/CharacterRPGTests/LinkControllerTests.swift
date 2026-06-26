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
        var entry = ValueEntryModel(id: entryId, name: "Some Value", type: .number, isGenerator: false, value: "27", diceId: nil, valueId: nil)
        item!.entries.append(entry)
        await root.itemController.replace(model: item!, isInsert: false)

        var result = "**Some Value**: 27 "
        await #expect(sut.linkText(model: root.itemController.itemOrEmpty(for: itemId), entry: entry) == result)

        item![entryId].value = "27+2"
        entry = item![entryId]
        await root.itemController.replace(model: item!, isInsert: false)

        result = "**Some Value**: 27+2 = 29"
        await #expect(sut.linkText(model: root.itemController.itemOrEmpty(for: itemId), entry: entry) == result)

        item![entryId].value = "27+2+3"
        entry = item![entryId]
        await root.itemController.replace(model: item!, isInsert: false)

        result = "**Some Value**: 27+2+3 = 32"
        await #expect(sut.linkText(model: root.itemController.itemOrEmpty(for: itemId), entry: entry) == result)
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
    
    // MARK: - validateParentId / GroupId

    // MARK: Helpers

    private struct GroupTestStructure {
        let folderId: UUID
        /// Items in creation order: [Charlie, Alpha, Bravo]
        let itemIds: [UUID]
        /// Items in alphabetical folder order: [Alpha, Bravo, Charlie]
        let alphabeticalIds: [UUID]
        /// Maps each item id to its 3 group item ids
        let groupsByItem: [UUID: [UUID]]
    }

    /// Builds: folder → [Charlie, Alpha, Bravo] (added non-alphabetically), each item → 3 group children.
    private func buildGroupStructure(root: CharacterRootModel) async throws -> GroupTestStructure {
        let editController = await root.editController
        let folderId = await root.itemController.addNew(type: .folder)
        let charlieId = await root.itemController.addNew(type: .item)
        await editController.reset(name: "Charlie", itemId: charlieId)
        let alphaId = await root.itemController.addNew(type: .item)
        await editController.reset(name: "Alpha", itemId: alphaId)
        let bravoId = await root.itemController.addNew(type: .item)
        await editController.reset(name: "Bravo", itemId: bravoId)
        let itemIds = [charlieId, alphaId, bravoId]

        for itemId in itemIds {
            await editController.addItem(itemId: itemId, parentId: folderId)
        }

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

        return GroupTestStructure(
            folderId: folderId,
            itemIds: itemIds,
            alphabeticalIds: [alphaId, bravoId, charlieId],
            groupsByItem: groupsByItem
        )
    }

    /// Asserts the fully correct expected state: folder ordered alphabetically, items have
    /// folderId as parentId, groups have nil parentId, their item as groupId, and displayState == 1.
    private func verifyStructureIntact(_ s: GroupTestStructure, root: CharacterRootModel) async throws {
        let folder = await root.itemController.itemOrEmpty(for: s.folderId)
        #expect(folder.parentId == nil)
        #expect(folder.groupId == nil)
        #expect(folder.entries.map(\.childId) == s.alphabeticalIds)

        for itemId in s.itemIds {
            let item = await root.itemController.itemOrEmpty(for: itemId)
            #expect(item.parentId == s.folderId)
            #expect(item.groupId == nil)
            let groupItemIds = try #require(s.groupsByItem[itemId])
            for groupItemId in groupItemIds {
                let group = await root.itemController.itemOrEmpty(for: groupItemId)
                #expect(group.parentId == nil)
                #expect(group.groupId == itemId)
                #expect(group.displayState == 1)
            }
        }
    }

    // MARK: Tests

    /// Folder: 3 items, each with 3 groups.
    /// Items have parentId set; groups have groupId but nil parentId; every item entry has valueId.
    /// Groups have parentId always set to nil and groupId is set to the belonging items.
    /// validateParentId is a no-op when the structure is already correct.
    @Test func validateParentIdSetsParentIdOnGroupChildren() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.linkController
        let s = try await buildGroupStructure(root: root)

        // Folder: sorted alphabetically regardless of insertion order
        let folder = await root.itemController.itemOrEmpty(for: s.folderId)
        try #require(folder.entries.count == 3)
        for (index, itemId) in s.alphabeticalIds.enumerated() {
            #expect(folder.entries[index].childId == itemId)
        }

        // Items: parentId points to the folder; 3 entries, all with valueId set
        for itemId in s.itemIds {
            let item = await root.itemController.itemOrEmpty(for: itemId)
            #expect(item.parentId == s.folderId)
            #expect(item.entries.count == 3)
            #expect(item.entries.allSatisfy { $0.valueId != nil })
        }

        // Groups: parentId == nil, groupId == parent item id
        for itemId in s.itemIds {
            let groupItemIds = try #require(s.groupsByItem[itemId])
            for groupItemId in groupItemIds {
                let group = await root.itemController.itemOrEmpty(for: groupItemId)
                #expect(group.parentId == nil)
                #expect(group.groupId == itemId)
            }
        }

        await sut.validateParentId()
        try await verifyStructureIntact(s, root: root)
    }

    /// A group whose groupId was cleared and parentId points to a stale id:
    /// validateParentId only logs the conflict — it does not overwrite or repair the data.
    @Test func validateParentIdDoesNotRepairGroupMissingGroupId() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.linkController
        let s = try await buildGroupStructure(root: root)

        // Simulate broken state on the first group of the first item:
        // groupId cleared, parentId pointing to the folder (wrong – not the item)
        let targetItemId = s.itemIds[0]
        let targetGroupId = try #require(s.groupsByItem[targetItemId]?.first)
        let brokenGroup = await root.itemController.itemOrEmpty(for: targetGroupId)
        brokenGroup.groupId = nil
        brokenGroup.parentId = s.folderId
        await root.itemController.replace(model: brokenGroup, isInsert: false)

        let groupBefore = await root.itemController.itemOrEmpty(for: targetGroupId)
        #expect(groupBefore.groupId == nil)
        #expect(groupBefore.parentId == s.folderId)

        await sut.validateParentId()

        // validateParentId logs the parentId conflict but makes no change
        let groupAfter = await root.itemController.itemOrEmpty(for: targetGroupId)
        #expect(groupAfter.groupId == nil)
        #expect(groupAfter.parentId == s.folderId)
    }

    /// A group that has both groupId and parentId set:
    /// validateParentId skips it entirely (guard on groupId fires), leaving both fields unchanged.
    @Test func validateParentIdSkipsGroupWithBothGroupIdAndParentId() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.linkController
        let s = try await buildGroupStructure(root: root)

        // Give the first group a spurious parentId while groupId remains set
        let targetItemId = s.itemIds[0]
        let targetGroupId = try #require(s.groupsByItem[targetItemId]?.first)
        let group = await root.itemController.itemOrEmpty(for: targetGroupId)
        group.parentId = s.folderId
        await root.itemController.replace(model: group, isInsert: false)

        let groupBefore = await root.itemController.itemOrEmpty(for: targetGroupId)
        #expect(groupBefore.groupId == targetItemId)
        #expect(groupBefore.parentId == s.folderId)

        await sut.validateParentId()

        // guard child.groupId == nil fires → group is skipped → both fields unchanged
        let groupAfter = await root.itemController.itemOrEmpty(for: targetGroupId)
        #expect(groupAfter.groupId == targetItemId)
        #expect(groupAfter.parentId == s.folderId)
    }

    /// A group with neither groupId nor parentId set and displayState == 0 (visible):
    /// validateParentId must set parentId to the owning item and reset displayState to 1 (hidden).
    @Test func validateParentIdHidesAndRepairsGroupWithNoRelationships() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.linkController
        let s = try await buildGroupStructure(root: root)

        // Simulate fully detached, visible group: both relationships cleared, displayState forced to 0
        let targetItemId = s.itemIds[0]
        let targetGroupId = try #require(s.groupsByItem[targetItemId]?.first)
        let brokenGroup = await root.itemController.itemOrEmpty(for: targetGroupId)
        brokenGroup.groupId = nil
        brokenGroup.parentId = nil
        brokenGroup.displayState = 0
        await root.itemController.replace(model: brokenGroup, isInsert: false)

        let groupBefore = await root.itemController.itemOrEmpty(for: targetGroupId)
        #expect(groupBefore.groupId == nil)
        #expect(groupBefore.parentId == nil)
        #expect(groupBefore.displayState == 0)

        await sut.validateParentId()

        // validateParentId sets parentId to the owning item and hides the group
        let groupAfter = await root.itemController.itemOrEmpty(for: targetGroupId)
        #expect(groupAfter.parentId == targetItemId)
        #expect(groupAfter.groupId == nil)
        #expect(groupAfter.displayState == 1)
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
