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

/// Tests for the CharacterRPG repair pipeline:
///
/// The pipeline runs in two phases, always in this order:
///   1. checkFolders (CharacterRootModel) — scans all root items' entries for valueId references
///      and stamps groupId on the sub-item. This repairs Phase 1 data (old exports where
///      group children were hidden with no parentId/groupId at all).
///   2. repairHiddenAndFolders (ConvertController) — runs after checkFolders. By now any
///      Phase 1 orphan that belongs to a group has groupId set; a truly orphaned hidden item
///      (still no groupId, no parentId) is made visible. Items with a broken/deleted groupId
///      are also made visible and their groupId is cleared.
///
/// Three historical states for group children:
///   Phase 1: parentId=nil, groupId=nil, displayState=1  → checkFolders stamps groupId → repair leaves it hidden
///   Phase 2: parentId=<groupId>, groupId=nil, displayState=1  → decode shim moves parentId→groupId → repair leaves it hidden
///   Phase 3: parentId=nil, groupId=<groupId>, displayState=1  → already correct, repair leaves it hidden
@Suite("Repair pipeline – CharacterRPG")
struct ConvertControllerRepairTests {

    // MARK: - checkFolders: Phase 1 repair (stamps groupId from entry scan)

    @Test("checkFolders stamps groupId on sub-item that has no groupId yet")
    func checkFolders_stampsGroupId_onPhase1SubItem() async throws {
        // Given – a root item whose entry points to a sub-item with no groupId (Phase 1 state)
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let ownerId = await root.itemController.addNew(type: .item)
        let childId = await root.itemController.addNew(type: .item)

        // Build entry with valueId → childId directly (bypass addNewGroup to simulate old data)
        let owner = await root.itemController.itemOrEmpty(for: ownerId)
        let entry = ValueEntryModel(id: UUID(), name: "OldGroupEntry", type: .text, value: "", valueId: childId)
        owner.entries.append(entry)
        await root.itemController.replace(model: owner, isInsert: false)

        // Child in Phase 1 state: hidden, no parentId, no groupId
        let child = await root.itemController.itemOrEmpty(for: childId)
        child.displayState = 1
        child.parentId = nil
        child.groupId = nil
        await root.itemController.replace(model: child, isInsert: false)

        // When – checkFolders scans entries and stamps groupId
        await root.checkFolders(reportModel: ValidateRepairModel())

        // Then – child now has groupId pointing to owner
        let childAfter = await root.itemController.itemOrEmpty(for: childId)
        #expect(childAfter.groupId == ownerId)
        #expect(childAfter.parentId == nil)
        #expect(childAfter.displayState == 1)
    }

    @Test("checkFolders clears parentId when stamping groupId (migrates Phase 2 in-memory state)")
    func checkFolders_clearsParentId_whenStampingGroupId() async throws {
        // Given – a sub-item still carrying parentId (Phase 2 state that wasn't caught by decode shim)
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let ownerId = await root.itemController.addNew(type: .item)
        let childId = await root.itemController.addNew(type: .item)

        let owner = await root.itemController.itemOrEmpty(for: ownerId)
        owner.entries.append(ValueEntryModel(id: UUID(), name: "Entry", type: .text, value: "", valueId: childId))
        await root.itemController.replace(model: owner, isInsert: false)

        let child = await root.itemController.itemOrEmpty(for: childId)
        child.displayState = 1
        child.parentId = ownerId  // Phase 2 state
        child.groupId = nil
        await root.itemController.replace(model: child, isInsert: false)

        // When
        await root.checkFolders(reportModel: ValidateRepairModel())

        // Then – parentId cleared, groupId set
        let childAfter = await root.itemController.itemOrEmpty(for: childId)
        #expect(childAfter.groupId == ownerId)
        #expect(childAfter.parentId == nil)
    }

    // MARK: - repairHiddenAndFolders: Phase 1 true orphan (no entry reference anywhere)

    @Test("repairHiddenAndFolders makes truly orphaned hidden item visible")
    func repairHiddenAndFolders_phase1TrueOrphan_isResetToVisible() async throws {
        // Given – a hidden item with no parentId, no groupId, and no root entry pointing to it
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await ConvertController(
            itemController: root.itemController,
            editController: root.editController
        )

        let itemId = await root.itemController.addNew(type: .item)
        let item = await root.itemController.itemOrEmpty(for: itemId)
        item.displayState = 1
        item.parentId = nil
        item.groupId = nil
        await root.itemController.replace(model: item, isInsert: false)

        // When – repair runs after checkFolders would have already set groupId on any claimed sub-items
        await sut.repairHiddenAndFolders(reportModel: ValidateRepairModel())

        // Then – no entry claimed this item, so it's truly orphaned → made visible
        let after = await root.itemController.itemOrEmpty(for: itemId)
        #expect(after.isGroupHiddenToggle == false)
    }

    // MARK: - repairHiddenAndFolders: Phase 3 valid group child is preserved

    @Test("repairHiddenAndFolders does not disturb valid group child (Phase 3)")
    func repairHiddenAndFolders_phase3GroupChild_staysHidden() async throws {
        // Given – a properly created group child (Phase 3)
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await ConvertController(
            itemController: root.itemController,
            editController: root.editController
        )

        let ownerId = await root.itemController.addNew(type: .item)
        let entryId = await root.editController.addNewGroup(itemId: ownerId)
        let owner = await root.itemController.itemOrEmpty(for: ownerId)
        let groupEntry = try #require(owner.entries.first(where: { $0.id == entryId }))
        let childId = try #require(groupEntry.valueId)

        // When
        await sut.repairHiddenAndFolders(reportModel: ValidateRepairModel())

        // Then – group child untouched
        let after = await root.itemController.itemOrEmpty(for: childId)
        #expect(after.displayState == 1)
        #expect(after.groupId == ownerId)
    }

    // MARK: - repairHiddenAndFolders: broken groupId (parent deleted or missing)

    @Test("repairHiddenAndFolders frees item whose groupId points to a deleted parent")
    func repairHiddenAndFolders_brokenGroupId_deletedParent_isResetToVisible() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await ConvertController(
            itemController: root.itemController,
            editController: root.editController
        )

        let ownerId = await root.itemController.addNew(type: .item)
        let childId = await root.itemController.addNew(type: .item)
        let child = await root.itemController.itemOrEmpty(for: childId)
        child.displayState = 1
        child.groupId = ownerId
        await root.itemController.replace(model: child, isInsert: false)

        // Delete the parent
        let owner = await root.itemController.itemOrEmpty(for: ownerId)
        owner.displayState = 2
        await root.itemController.replace(model: owner, isInsert: false)

        // When
        await sut.repairHiddenAndFolders(reportModel: ValidateRepairModel())

        // Then – child freed and groupId cleared
        let after = await root.itemController.itemOrEmpty(for: childId)
        #expect(after.isGroupHiddenToggle == false)
        #expect(after.groupId == nil)
    }

    @Test("repairHiddenAndFolders frees item whose groupId points to a non-existent parent")
    func repairHiddenAndFolders_brokenGroupId_missingParent_isResetToVisible() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await ConvertController(
            itemController: root.itemController,
            editController: root.editController
        )

        let childId = await root.itemController.addNew(type: .item)
        let phantomId = UUID()
        let child = await root.itemController.itemOrEmpty(for: childId)
        child.displayState = 1
        child.groupId = phantomId
        await root.itemController.replace(model: child, isInsert: false)

        // When
        await sut.repairHiddenAndFolders(reportModel: ValidateRepairModel())

        // Then
        let after = await root.itemController.itemOrEmpty(for: childId)
        #expect(after.isGroupHiddenToggle == false)
        #expect(after.groupId == nil)
    }

    // MARK: - Full pipeline: checkFolders → repairHiddenAndFolders

    @Test("Full pipeline: Phase 1 sub-item gets groupId from checkFolders, then repair leaves it hidden")
    func fullPipeline_phase1SubItem_getsGroupIdThenStaysHidden() async throws {
        // Given – Phase 1 sub-item (hidden, no parentId, no groupId) referenced in a root entry
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let ownerId = await root.itemController.addNew(type: .item)
        let childId = await root.itemController.addNew(type: .item)

        let owner = await root.itemController.itemOrEmpty(for: ownerId)
        owner.entries.append(ValueEntryModel(id: UUID(), name: "Entry", type: .text, value: "", valueId: childId))
        await root.itemController.replace(model: owner, isInsert: false)

        let child = await root.itemController.itemOrEmpty(for: childId)
        child.displayState = 1
        child.parentId = nil
        child.groupId = nil
        await root.itemController.replace(model: child, isInsert: false)

        // When – full pipeline (same order as after import)
        await root.checkFolders(reportModel: ValidateRepairModel())

        // Then – checkFolders stamped groupId, child stays hidden (not treated as orphan)
        let afterCheck = await root.itemController.itemOrEmpty(for: childId)
        #expect(afterCheck.groupId == ownerId)
        #expect(afterCheck.displayState == 1)
    }

    @Test("Full pipeline: true orphan (no entry reference) becomes visible after both passes")
    func fullPipeline_trueOrphan_becomesVisible() async throws {
        // Given – a hidden item with no parentId, no groupId, and no root entry pointing to it
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let itemId = await root.itemController.addNew(type: .item)
        let item = await root.itemController.itemOrEmpty(for: itemId)
        item.displayState = 1
        item.parentId = nil
        item.groupId = nil
        await root.itemController.replace(model: item, isInsert: false)

        // When – full pipeline
        await root.checkFolders(reportModel: ValidateRepairModel())

        // Then – no entry claimed it; checkFolders calls repairHiddenAndFolders internally
        let after = await root.itemController.itemOrEmpty(for: itemId)
        #expect(after.isGroupHiddenToggle == false)
    }

    // MARK: - Folder cleaning

    @Test("Folder cleaning removes entry whose child's parentId no longer matches")
    func folderCleaning_removesEntryWithMismatchedParentId() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await ConvertController(
            itemController: root.itemController,
            editController: root.editController
        )

        let folderId = await root.itemController.addNew(type: .folder)
        let child1Id = await root.itemController.addNew(type: .item)
        let child2Id = await root.itemController.addNew(type: .item)
        await root.editController.addItem(itemId: child1Id, parentId: folderId)
        await root.editController.addItem(itemId: child2Id, parentId: folderId)

        // Corrupt child2: clear parentId without removing from folder entries
        let child2 = await root.itemController.itemOrEmpty(for: child2Id)
        child2.parentId = nil
        await root.itemController.replace(model: child2, isInsert: false)

        // When
        await sut.repairHiddenAndFolders(reportModel: ValidateRepairModel())

        // Then
        let folder = await root.itemController.itemOrEmpty(for: folderId)
        #expect(folder.entries.count == 1)
        #expect(folder.entries[0].childId == child1Id)
    }

    // MARK: - Value module intentionally skips generic orphaned-parentId repair

    @Test("Value module: orphaned folder child with parentId is not auto-repaired by generic loop")
    func valueModule_orphanedFolderChild_notRepairedByGenericLoop() async throws {
        // Documents the intentional behaviour: .value skips the generic parentId-orphan loop
        // to avoid interfering with real folder children (which legitimately use parentId).
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await ConvertController(
            itemController: root.itemController,
            editController: root.editController
        )

        let folderId = await root.itemController.addNew(type: .folder)
        let childId = await root.itemController.addNew(type: .item)
        let child = await root.itemController.itemOrEmpty(for: childId)
        child.parentId = folderId   // set parentId but NOT added to folder entries
        await root.itemController.replace(model: child, isInsert: false)

        // When
        await sut.repairHiddenAndFolders(reportModel: ValidateRepairModel())

        // Then – parentId preserved (generic orphan repair skipped for .value module)
        let after = await root.itemController.itemOrEmpty(for: childId)
        #expect(after.parentId == folderId)
    }

    // MARK: - Category normalization

    @Test("Category normalization converts non-entry category to .entry with original as tag")
    func categoryNormalization_convertsCategoryToEntry() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await ConvertController(
            itemController: root.itemController,
            editController: root.editController
        )

        let itemId = await root.itemController.addNew(type: .item)
        await root.editController.reset(category: .character, itemId: itemId)
        await root.editController.reset(tags: ["ExistingTag"], itemId: itemId)

        // When
        await sut.repairHiddenAndFolders(reportModel: ValidateRepairModel())

        // Then
        let after = await root.itemController.itemOrEmpty(for: itemId)
        #expect(after.category == .entry)
        #expect(after.tags.contains("Character"))
        #expect(after.tags.contains("ExistingTag"))
    }

    @Test("Category normalization skips special categories (folder, collection)")
    func categoryNormalization_skipsSpecialCategories() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await ConvertController(
            itemController: root.itemController,
            editController: root.editController
        )

        let folderId = await root.itemController.addNew(type: .folder)

        // When
        await sut.repairHiddenAndFolders(reportModel: ValidateRepairModel())

        // Then
        let after = await root.itemController.itemOrEmpty(for: folderId)
        #expect(after.category == .folder)
    }

    // MARK: - Valid structures are preserved

    @Test("Valid folder child is not disturbed by repair")
    func validFolderChild_repairIsNoop() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await ConvertController(
            itemController: root.itemController,
            editController: root.editController
        )

        let folderId = await root.itemController.addNew(type: .folder)
        let childId = await root.itemController.addNew(type: .item)
        await root.editController.addItem(itemId: childId, parentId: folderId)

        // When
        await sut.repairHiddenAndFolders(reportModel: ValidateRepairModel())

        // Then
        let childAfter = await root.itemController.itemOrEmpty(for: childId)
        let folderAfter = await root.itemController.itemOrEmpty(for: folderId)
        #expect(childAfter.parentId == folderId)
        #expect(folderAfter.entries.contains(where: { $0.childId == childId }))
    }
}
#endif
