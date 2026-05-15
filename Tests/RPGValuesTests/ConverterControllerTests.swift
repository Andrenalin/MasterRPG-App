// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import DiceRPG
import PdfRPG
import PhotoRPG
import TableRPG
import RPGResourcesDebug
import Testing

@testable import CharacterRPG

/// Tests for the scenario where a sub-item lives inside a folder AND belongs to a group owner.
/// The sub-item has both parentId (folder) and groupId (owner) set simultaneously.
/// checkFolders / repairHiddenAndFolders must preserve both and not corrupt either.
struct ConverterControllerTests {

    // MARK: - Baseline: folder + group memberships coexist

    /// An item inside a folder with an entry pointing to a sub-item.
    /// The sub-item has parentId (folder) and groupId (owner) both set.
    /// Running checkFolders must not touch either relationship.
    @Test func folderItemWithGroupSubItem_baselineIsPreserved() async throws {
        // Given
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let folderId = await root.itemController.addNew(type: .folder)
        let ownerId  = await root.itemController.addNew(type: .item)
        let childId  = await root.itemController.addNew(type: .item)

        // Place owner inside folder
        await root.editController.addItem(itemId: ownerId, parentId: folderId)

        // Build sub-item: belongs to owner (groupId) AND is inside folder (parentId)
        let child = await root.itemController.itemOrEmpty(for: childId)
        child.displayState = 1
        child.groupId  = ownerId
        child.parentId = folderId
        await root.itemController.replace(model: child, isInsert: false)

        // Add entry on owner that references child via valueId
        let owner = await root.itemController.itemOrEmpty(for: ownerId)
        owner.entries.append(ValueEntryModel(id: UUID(), name: "SubEntry", type: .text, value: "", valueId: childId))
        await root.itemController.replace(model: owner, isInsert: false)

        // When
        await root.checkFolders(reportModel: ValidateRepairModel())

        // Then – both relationships intact
        let childAfter = await root.itemController.itemOrEmpty(for: childId)
        #expect(childAfter.groupId  == ownerId)
        #expect(childAfter.parentId == folderId)
        #expect(childAfter.displayState == 1)

        // Folder still contains the owner
        let folderAfter = await root.itemController.itemOrEmpty(for: folderId)
        #expect(folderAfter.entries.contains(where: { $0.childId == ownerId }))
    }

    // MARK: - Missing groupId: checkFolders restores it, parentId (folder) is kept

    /// Same layout but the sub-item lost its groupId (e.g. Phase 1 export or data corruption).
    /// checkFolders must stamp groupId back from the entry reference, and must NOT clear
    /// the real folder parentId.
    @Test func folderItemWithGroupSubItem_missingGroupId_isRepairedKeepingParentId() async throws {
        // Given
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let folderId = await root.itemController.addNew(type: .folder)
        let ownerId  = await root.itemController.addNew(type: .item)
        let childId  = await root.itemController.addNew(type: .item)

        await root.editController.addItem(itemId: ownerId, parentId: folderId)

        // Sub-item has parentId (folder) but groupId is nil (corrupted / old export)
        let child = await root.itemController.itemOrEmpty(for: childId)
        child.displayState = 1
        child.groupId  = nil      // missing
        child.parentId = folderId
        await root.itemController.replace(model: child, isInsert: false)

        let owner = await root.itemController.itemOrEmpty(for: ownerId)
        owner.entries.append(ValueEntryModel(id: UUID(), name: "SubEntry", type: .text, value: "", valueId: childId))
        await root.itemController.replace(model: owner, isInsert: false)

        // When
        await root.checkFolders(reportModel: ValidateRepairModel())

        // Then – groupId restored, folder parentId preserved
        let childAfter = await root.itemController.itemOrEmpty(for: childId)
        #expect(childAfter.groupId  == ownerId)
        #expect(childAfter.parentId == folderId)   // real folder parentId must survive
        #expect(childAfter.displayState == 1)
    }

    // MARK: - Phase 2 state: parentId used as group reference (no real folder)

    /// Sub-item's parentId was set to the group owner (Phase 2 / old code behaviour),
    /// not to a real folder. checkFolders must move that into groupId and clear parentId.
    /// Result must match the Phase 3 / baseline state.
    @Test func folderItemWithGroupSubItem_parentIdUsedAsGroupId_isMigratedToGroupId() async throws {
        // Given
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let ownerId = await root.itemController.addNew(type: .item)
        let childId = await root.itemController.addNew(type: .item)

        // Phase 2 state: parentId == ownerId, groupId == nil
        let child = await root.itemController.itemOrEmpty(for: childId)
        child.displayState = 1
        child.groupId  = nil
        child.parentId = ownerId   // wrongly used as group reference
        await root.itemController.replace(model: child, isInsert: false)

        let owner = await root.itemController.itemOrEmpty(for: ownerId)
        owner.entries.append(ValueEntryModel(id: UUID(), name: "SubEntry", type: .text, value: "", valueId: childId))
        await root.itemController.replace(model: owner, isInsert: false)

        // When
        await root.checkFolders(reportModel: ValidateRepairModel())

        // Then – parentId cleared (it was the group reference, not a real folder),
        //         groupId set to ownerId → identical to Phase 3 baseline
        let childAfter = await root.itemController.itemOrEmpty(for: childId)
        #expect(childAfter.groupId  == ownerId)
        #expect(childAfter.parentId == nil)
        #expect(childAfter.displayState == 1)
    }

    // MARK: - True orphan: no parentId, no groupId → made visible

    /// Sub-item with parentId=nil and groupId=nil is a true orphan.
    /// Even if displayState==1, the full pipeline must make it visible.
    @Test func subItem_noParentIdNoGroupId_isOrphan_becomesVisible() async throws {
        // Given
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let itemId = await root.itemController.addNew(type: .item)
        let item = await root.itemController.itemOrEmpty(for: itemId)
        item.displayState = 1
        item.parentId = nil
        item.groupId  = nil
        await root.itemController.replace(model: item, isInsert: false)

        // When – full pipeline (checkFolders → repairHiddenAndFolders)
        await root.checkFolders(reportModel: ValidateRepairModel())

        // Then – no entry claimed this item, so it is truly orphaned → made visible
        let after = await root.itemController.itemOrEmpty(for: itemId)
        #expect(after.isGroupHiddenToggle == false)
        #expect(after.groupId  == nil)
        #expect(after.parentId == nil)
    }

    // MARK: - Group member not hidden: checkFolders stamps displayState=1

    /// A sub-item that belongs to a group (groupId set) but whose displayState was reset to
    /// visible (e.g. by an older repair pass). checkFolders must re-hide it.
    @Test func subItem_groupMember_notHidden_isReHiddenByCheckFolders() async throws {
        // Given
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let ownerId = await root.itemController.addNew(type: .item)
        let childId = await root.itemController.addNew(type: .item)

        // Sub-item has correct groupId but displayState was reset to 0 (visible)
        let child = await root.itemController.itemOrEmpty(for: childId)
        child.displayState = 0     // should be 1
        child.groupId  = ownerId
        child.parentId = nil
        await root.itemController.replace(model: child, isInsert: false)

        let owner = await root.itemController.itemOrEmpty(for: ownerId)
        owner.entries.append(ValueEntryModel(id: UUID(), name: "SubEntry", type: .text, value: "", valueId: childId))
        await root.itemController.replace(model: owner, isInsert: false)

        // When
        await root.checkFolders(reportModel: ValidateRepairModel())

        // Then – checkFolders stamps displayState=1 on claimed sub-items
        let childAfter = await root.itemController.itemOrEmpty(for: childId)
        #expect(childAfter.displayState == 1)
        #expect(childAfter.groupId == ownerId)
    }
}
#endif
