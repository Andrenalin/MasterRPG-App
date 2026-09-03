// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import CharacterRPG
@testable import DiceRPG
@testable import PdfRPG
@testable import PhotoRPG
@testable import TableRPG

@MainActor
struct LinkControllerTests {
    @Test func createGroup() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.linkController

        let itemId = await root.itemController.addNew(type: .item)
        let item = await root.itemController.item(for: itemId)?.copy()
        #expect(nil != item)
        let entryId = UUID()
        var entry = ValueEntryModel(id: entryId, name: "Some Value", type: .number, isGenerator: false, value: "27", diceId: nil, valueId: nil)
        item!.entries.append(entry)
        root.itemController.replace(model: item!, isInsert: false)

        var result = "**Some Value**: 27 "
        #expect(sut.linkText(model: root.itemController.itemOrEmpty(for: itemId), entry: entry) == result)

        item![entryId].value = "27+2"
        entry = item![entryId]
        root.itemController.replace(model: item!, isInsert: false)

        result = "**Some Value**: 27+2 = 29"
        #expect(sut.linkText(model: root.itemController.itemOrEmpty(for: itemId), entry: entry) == result)

        item![entryId].value = "27+2+3"
        entry = item![entryId]
        root.itemController.replace(model: item!, isInsert: false)

        result = "**Some Value**: 27+2+3 = 32"
        #expect(sut.linkText(model: root.itemController.itemOrEmpty(for: itemId), entry: entry) == result)
    }
    
    @Test func toggleWithShareTogglerAndEditAction() async throws {
        let root = try await MockRoot.importTestData()
        
        let sut = root.linkController
        let firstItem = root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        let text = sut.generateLink(itemId: firstItem.id)
        var result = sut.toggleTextLink(linkNumber: 0, itemId: firstItem.id, entryId: nil, command: nil, in: text, shareResult: shareResult(), toggler: toggler(), editAction: editAction())
        var expectedText = "\(text)➡️[Show](RPG://VALUES/600/E8AB89DA-4BB7-4C6E-BD6F-88A5AC5A8358/show) Timo’s Character -- 11 Entries [Remove](RPG://VALUES/300/E8AB89DA-4BB7-4C6E-BD6F-88A5AC5A8358/remove)⬅️"
        #expect(result == expectedText)
        
        result = sut.toggleTextLink(linkNumber: LinkType.share.linkNumberAddition, itemId: firstItem.id, entryId: nil, command: LinkType.share.rawValue, in: result, shareResult: shareResult(), toggler: toggler(), editAction: editAction())
        expectedText = "\(text)➡️[Show](RPG://VALUES/600/E8AB89DA-4BB7-4C6E-BD6F-88A5AC5A8358/show) Timo’s Character -- 11 Entries [Remove](RPG://VALUES/300/E8AB89DA-4BB7-4C6E-BD6F-88A5AC5A8358/remove)⬅️"
        #expect(result == expectedText)

        result = sut.toggleTextLink(linkNumber: LinkType.remove.linkNumberAddition, itemId: firstItem.id, entryId: nil, command: LinkType.remove.rawValue, in: result, shareResult: shareResult(), toggler: toggler(), editAction: editAction())
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
        let editController = root.editController
        let folderId = await root.itemController.addNew(type: .folder)
        let charlieId = await root.itemController.addNew(type: .item)
        editController.reset(name: "Charlie", itemId: charlieId)
        let alphaId = await root.itemController.addNew(type: .item)
        editController.reset(name: "Alpha", itemId: alphaId)
        let bravoId = await root.itemController.addNew(type: .item)
        editController.reset(name: "Bravo", itemId: bravoId)
        let itemIds = [charlieId, alphaId, bravoId]

        for itemId in itemIds {
            editController.addItem(itemId: itemId, parentId: folderId)
        }

        var groupsByItem: [UUID: [UUID]] = [:]
        for itemId in itemIds {
            var groupItemIds: [UUID] = []
            for _ in 0..<3 {
                let entryId = await editController.addNewGroup(itemId: itemId)
                let item = root.itemController.itemOrEmpty(for: itemId)
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
        let folder = root.itemController.itemOrEmpty(for: s.folderId)
        #expect(folder.parentId == nil)
        #expect(folder.groupId == nil)
        #expect(folder.entries.map(\.childId) == s.alphabeticalIds)

        for itemId in s.itemIds {
            let item = root.itemController.itemOrEmpty(for: itemId)
            #expect(item.parentId == s.folderId)
            #expect(item.groupId == nil)
            let groupItemIds = try #require(s.groupsByItem[itemId])
            for groupItemId in groupItemIds {
                let group = root.itemController.itemOrEmpty(for: groupItemId)
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
        let sut = root.linkController
        let s = try await buildGroupStructure(root: root)

        // Folder: sorted alphabetically regardless of insertion order
        let folder = root.itemController.itemOrEmpty(for: s.folderId)
        try #require(folder.entries.count == 3)
        for (index, itemId) in s.alphabeticalIds.enumerated() {
            #expect(folder.entries[index].childId == itemId)
        }

        // Items: parentId points to the folder; 3 entries, all with valueId set
        for itemId in s.itemIds {
            let item = root.itemController.itemOrEmpty(for: itemId)
            #expect(item.parentId == s.folderId)
            #expect(item.entries.count == 3)
            #expect(item.entries.allSatisfy { $0.valueId != nil })
        }

        // Groups: parentId == nil, groupId == parent item id
        for itemId in s.itemIds {
            let groupItemIds = try #require(s.groupsByItem[itemId])
            for groupItemId in groupItemIds {
                let group = root.itemController.itemOrEmpty(for: groupItemId)
                #expect(group.parentId == nil)
                #expect(group.groupId == itemId)
            }
        }

        sut.validateParentId()
        try await verifyStructureIntact(s, root: root)
    }

    /// A group whose groupId was cleared and parentId points to a stale id:
    /// validateParentId only logs the conflict — it does not overwrite or repair the data.
    @Test func validateParentIdDoesNotRepairGroupMissingGroupId() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.linkController
        let s = try await buildGroupStructure(root: root)

        // Simulate broken state on the first group of the first item:
        // groupId cleared, parentId pointing to the folder (wrong – not the item)
        let targetItemId = s.itemIds[0]
        let targetGroupId = try #require(s.groupsByItem[targetItemId]?.first)
        let brokenGroup = root.itemController.itemOrEmpty(for: targetGroupId)
        brokenGroup.groupId = nil
        brokenGroup.parentId = s.folderId
        root.itemController.replace(model: brokenGroup, isInsert: false)

        let groupBefore = root.itemController.itemOrEmpty(for: targetGroupId)
        #expect(groupBefore.groupId == nil)
        #expect(groupBefore.parentId == s.folderId)

        sut.validateParentId()

        // validateParentId logs the parentId conflict but makes no change
        let groupAfter = root.itemController.itemOrEmpty(for: targetGroupId)
        #expect(groupAfter.groupId == nil)
        #expect(groupAfter.parentId == s.folderId)
    }

    /// A group that has both groupId and parentId set:
    /// validateParentId skips it entirely (guard on groupId fires), leaving both fields unchanged.
    @Test func validateParentIdSkipsGroupWithBothGroupIdAndParentId() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.linkController
        let s = try await buildGroupStructure(root: root)

        // Give the first group a spurious parentId while groupId remains set
        let targetItemId = s.itemIds[0]
        let targetGroupId = try #require(s.groupsByItem[targetItemId]?.first)
        let group = root.itemController.itemOrEmpty(for: targetGroupId)
        group.parentId = s.folderId
        root.itemController.replace(model: group, isInsert: false)

        let groupBefore = root.itemController.itemOrEmpty(for: targetGroupId)
        #expect(groupBefore.groupId == targetItemId)
        #expect(groupBefore.parentId == s.folderId)

        sut.validateParentId()

        // guard child.groupId == nil fires → group is skipped → both fields unchanged
        let groupAfter = root.itemController.itemOrEmpty(for: targetGroupId)
        #expect(groupAfter.groupId == targetItemId)
        #expect(groupAfter.parentId == s.folderId)
    }

    /// A group with neither groupId nor parentId set and displayState == 0 (visible):
    /// validateParentId must set parentId to the owning item and reset displayState to 1 (hidden).
    @Test func validateParentIdHidesAndRepairsGroupWithNoRelationships() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.linkController
        let s = try await buildGroupStructure(root: root)

        // Simulate fully detached, visible group: both relationships cleared, displayState forced to 0
        let targetItemId = s.itemIds[0]
        let targetGroupId = try #require(s.groupsByItem[targetItemId]?.first)
        let brokenGroup = root.itemController.itemOrEmpty(for: targetGroupId)
        brokenGroup.groupId = nil
        brokenGroup.parentId = nil
        brokenGroup.displayState = 0
        root.itemController.replace(model: brokenGroup, isInsert: false)

        let groupBefore = root.itemController.itemOrEmpty(for: targetGroupId)
        #expect(groupBefore.groupId == nil)
        #expect(groupBefore.parentId == nil)
        #expect(groupBefore.displayState == 0)

        sut.validateParentId()

        // validateParentId sets parentId to the owning item and hides the group
        let groupAfter = root.itemController.itemOrEmpty(for: targetGroupId)
        #expect(groupAfter.parentId == targetItemId)
        #expect(groupAfter.groupId == nil)
        #expect(groupAfter.displayState == 1)
    }

    @Test func toggleTextLinkCommandsExpandEntryValuesAndRemoveLinks() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let entry = ValueEntryModel(id: UUID(), name: "Strength", type: .number, value: "18")
        let character = ValueModel(
            id: UUID(),
            name: "Command Character",
            description: "Ready for action",
            entries: [entry]
        )
        root.itemController.replace(model: character, isInsert: true)

        let itemText = root.linkController.generateLinks(itemId: character.id, entryId: nil, into: "See ")
        let entryText = root.linkController.generateLinks(itemId: character.id, entryId: entry.id, into: "Value ")

        let expandedItem = root.linkController.toggleTextLink(
            linkNumber: 0,
            itemId: character.id,
            entryId: nil,
            command: nil,
            in: itemText,
            shareResult: nil,
            toggler: nil,
            editAction: { row in row.itemId == character.id }
        )
        let expandedEntry = root.linkController.toggleTextLink(
            linkNumber: 0,
            itemId: character.id,
            entryId: entry.id,
            command: nil,
            in: entryText,
            shareResult: nil,
            toggler: nil,
            editAction: nil
        )
        let removedItem = root.linkController.toggleTextLink(
            linkNumber: LinkType.remove.linkNumberAddition,
            itemId: character.id,
            entryId: nil,
            command: LinkType.remove.rawValue,
            in: itemText,
            shareResult: nil,
            toggler: nil,
            editAction: nil
        )
        let showCommand = root.linkController.toggleTextLink(
            linkNumber: 0,
            itemId: character.id,
            entryId: nil,
            command: LinkType.show.rawValue,
            in: itemText,
            shareResult: nil,
            toggler: nil,
            editAction: nil
        )
        let shareCommand = root.linkController.toggleTextLink(
            linkNumber: 0,
            itemId: character.id,
            entryId: nil,
            command: LinkType.share.rawValue,
            in: itemText,
            shareResult: nil,
            toggler: nil,
            editAction: nil
        )

        #expect(expandedItem.localizedStandardContains("Ready for action"))
        #expect(expandedItem.localizedStandardContains("Remove"))
        #expect(expandedEntry.localizedStandardContains("18"))
        #expect(removedItem.localizedStandardContains("Command Character"))
        #expect(showCommand == itemText)
        #expect(shareCommand == itemText)
    }

    @Test func validateLinksRemovesMissingPhotosDiceAndValueReferences() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let validPhotoId = await root.photoRoot.itemController.addNew(type: .item)
        let missingPhotoId = UUID()
        let missingInlinePhotoId = UUID()
        let missingDiceId = UUID()
        let missingValueId = UUID()
        let entry = ValueEntryModel(
            id: UUID(),
            name: "Linked Stat",
            type: .number,
            value: "12",
            diceId: missingDiceId,
            valueId: missingValueId
        )
        let character = ValueModel(
            id: UUID(),
            name: "Broken Links",
            photoId: missingPhotoId,
            photos: [validPhotoId, missingInlinePhotoId],
            entries: [entry]
        )
        root.itemController.replace(model: character, isInsert: true)

        root.linkController.validateLinks(on: character.id)

        let repaired = try #require(root.itemController.itemSync(for: character.id))
        let repairedEntry = repaired[entry.id]

        #expect(repaired.photoId == nil)
        #expect(repaired.photos == [validPhotoId])
        #expect(repairedEntry.diceId == nil)
        #expect(repairedEntry.valueId == nil)
    }

    @Test func repairDuplicateLinksRewritesValueLinksToDuplicateModels() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let originalEntry = ValueEntryModel(id: UUID(), name: "Power", type: .number, value: "7")
        let original = ValueModel(id: UUID(), name: "Original", entries: [originalEntry])
        root.itemController.replace(model: original, isInsert: true)

        let duplicateEntry = ValueEntryModel(id: UUID(), name: "Power", type: .number, value: "7")
        let duplicate = ValueModel(id: UUID(), name: "Duplicate", entries: [duplicateEntry])
        let mapper = [original.id: duplicate.id]
        let linkedText = root.linkController.generateLinks(itemId: original.id, entryId: originalEntry.id, into: "Use ")

        let repaired = root.linkController.repairValueLinks(models: [duplicate], mapper: mapper, text: linkedText)

        #expect(repaired.localizedStandardContains(duplicate.id.uuidString))
        #expect(repaired.localizedStandardContains(duplicateEntry.id.uuidString))
        #expect(!repaired.localizedStandardContains(original.id.uuidString))
        #expect(!repaired.localizedStandardContains(originalEntry.id.uuidString))

        let holderEntry = ValueEntryModel(id: UUID(), name: linkedText, type: .text, value: linkedText)
        let holder = ValueModel(id: UUID(), name: "Holder", entries: [holderEntry])
        root.linkController.repairDuplicateLinks(models: [holder, duplicate], mapper: mapper)

        #expect(holder.entries[0].name.localizedStandardContains(duplicate.id.uuidString))
        #expect(holder.entries[0].value.localizedStandardContains(duplicateEntry.id.uuidString))
    }

    @Test func collectLinksReturnsInlinePhotoListAndValidateFindsExistingItems() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let photoA = UUID()
        let photoB = UUID()
        let character = ValueModel(id: UUID(), name: "Photo List", photos: [photoA, photoB])
        root.itemController.replace(model: character, isInsert: true)

        #expect(Set(root.linkController.collectLinks(of: .photo, from: character.id)) == Set([photoA, photoB]))
        #expect(root.linkController.collectLinks(of: .photo, from: UUID()).isEmpty)
        #expect(root.linkController.validate(id: character.id) == character.id)
        #expect(root.linkController.validate(id: UUID()) == nil)
    }

    // MARK: - updateValueCalculation

    private static func makeRoot() -> CharacterRootModel {
        let diceRoot = DiceRootModel.testRoot()
        let pdfRoot = PdfRootModel.testRoot()
        let photoRoot = PhotoRootModel.testRoot()
        let tableRoot = TableRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot)
        return CharacterRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
    }

    /// Reproduces the reported "inline dice not updating" bug: an entry (B) whose
    /// value formula links to another entry (A) on the same character. `updateValueCalculation`
    /// is what `EntryListDiceRow` uses to know when to recompute B's dice display after A
    /// changes. Registered *before* either entry has ever been touched this game session
    /// (i.e. before either exists in `gameItemData`) — matching the real flow: the dice row
    /// appears and arms tracking against the current (permanent) instance, then later the
    /// player edits A for the first time this session.
    @Test func updateValueCalculationFiresWhenLinkedDependencyFirstEntersGameMemory() async throws {
        let root = Self.makeRoot()
        let sut = root.linkController
        let edit = root.editController

        let itemId = await root.itemController.addNew(type: .character)
        let aEntry = ValueEntryModel(id: UUID(), name: "Strength", type: .number, value: "45")
        edit.add(entry: aEntry, itemId: itemId)

        let linkText = root.itemController.itemOrEmpty(for: itemId).url(linkNumber: 0, entryId: aEntry.id)
        let bEntry = ValueEntryModel(id: UUID(), name: "Attack", type: .number, value: linkText)
        edit.add(entry: bEntry, itemId: itemId)

        root.itemController.itemDataModel.isGameMode = true
        defer { root.itemController.itemDataModel.isGameMode = false }

        // Sanity check matching the bug's precondition: neither entry has been
        // touched yet this game session, so there's nothing in gameItemData yet.
        #expect(root.itemController.itemDataModel.gameItemData[itemId] == nil)

        var fireCount = 0
        sut.updateValueCalculation(itemId: itemId, entryId: bEntry.id) {
            fireCount += 1
        }

        // First edit to A this game session — this is what makes `replaceInGameMemory`
        // insert a brand-new instance into `gameItemData` rather than mutating one
        // already there.
        edit.updateValue(itemId: itemId, entryId: aEntry.id, number: 35)

        // The withObservationTracking `onChange` dispatches `action()` via
        // `Task { @MainActor in ... }`, so give it a turn to run.
        try await Task.sleep(for: .milliseconds(100))

        #expect(fireCount == 1)
    }

    /// Full end-to-end reproduction of the reported bug: entry B has an attached dice
    /// whose die-count scales with B's own calculated value (`DiceModel.addDiceEvery`/
    /// `resetDice()`), and B's formula links to entry A. Mirrors `EntryListDiceRow`'s
    /// actual wiring (`updateValueCalculation` re-arming → `validateForValue` →
    /// `DiceModel.compareValue.didSet` → `resetDice()`) rather than calling the dice
    /// update helper directly, so a break anywhere in that chain shows up here.
    @Test func inlineDiceCountUpdatesWhenLinkedValueChanges() async throws {
        let root = Self.makeRoot()
        let edit = root.editController
        let sut = root.linkController

        // One die, +1 die every 20 points of the compared value.
        let diceTemplate = DiceModel(id: UUID(), name: "Attack Dice", dice: [DieModel(id: UUID(), die: .twenty)], addDiceEvery: 20)
        root.diceRoot.itemController.replace(model: diceTemplate, isInsert: true)

        let itemId = await root.itemController.addNew(type: .character)
        let aEntry = ValueEntryModel(id: UUID(), name: "Strength", type: .number, value: "45")
        edit.add(entry: aEntry, itemId: itemId)

        let linkText = root.itemController.itemOrEmpty(for: itemId).url(linkNumber: 0, entryId: aEntry.id)
        let bEntry = ValueEntryModel(id: UUID(), name: "Attack", type: .number, value: linkText, diceId: diceTemplate.id)
        edit.add(entry: bEntry, itemId: itemId)

        root.itemController.itemDataModel.isGameMode = true
        defer { root.itemController.itemDataModel.isGameMode = false }

        guard let gameDiceId = root.gameController.gameDiceId(itemId: itemId, entryId: bEntry.id) else {
            Issue.record("expected a game dice id for entry B")
            return
        }

        func pushDiceValue() {
            let entry = root.itemController.itemOrEmpty(for: itemId)[bEntry.id]
            guard let text = sut.calculate(entry: entry), let value = Int(text) else { return }
            root.diceRoot.diceGameControllable.validateForValue(diceId: gameDiceId, compareValue: value)
        }

        // Mirrors `.onChange(of: updateOtherValue, initial: true)`: push the current
        // value once, then arm tracking for the next change.
        pushDiceValue()
        sut.updateValueCalculation(itemId: itemId, entryId: bEntry.id) {
            pushDiceValue()
        }

        #expect(root.diceRoot.gameController.gameItem(for: gameDiceId).dice.count == 3)

        edit.updateValue(itemId: itemId, entryId: aEntry.id, number: 35)
        try await Task.sleep(for: .milliseconds(100))

        #expect(root.diceRoot.gameController.gameItem(for: gameDiceId).dice.count == 2)
    }

    /// Guards `updateValueCalculation`'s self-re-arming chain (mirroring
    /// `EntryListDiceRow`'s `updateOtherValue` toggle-and-reregister pattern) across
    /// *multiple* successive changes to the same dependency, not just the first —
    /// isolated from any network/resync involvement. See CODE_AUDIT note: an earlier,
    /// now-reverted attempt at hardening this function (having the tracked closure
    /// also read `itemController.itemDataModel.gameItemData[detail.itemId]`, to react
    /// to a dependency's first game-memory promotion) silently broke exactly this —
    /// the second re-arm's registration never fired again. Found via this test.
    @Test func inlineDiceCountUpdatesAcrossMultipleSuccessiveChanges() async throws {
        let root = Self.makeRoot()
        let edit = root.editController
        let sut = root.linkController

        let diceTemplate = DiceModel(id: UUID(), name: "Attack Dice", dice: [DieModel(id: UUID(), die: .twenty)], addDiceEvery: 20)
        root.diceRoot.itemController.replace(model: diceTemplate, isInsert: true)

        let itemId = await root.itemController.addNew(type: .character)
        let aEntry = ValueEntryModel(id: UUID(), name: "Strength", type: .number, value: "45")
        edit.add(entry: aEntry, itemId: itemId)

        let linkText = root.itemController.itemOrEmpty(for: itemId).url(linkNumber: 0, entryId: aEntry.id)
        let bEntry = ValueEntryModel(id: UUID(), name: "Attack", type: .number, value: linkText, diceId: diceTemplate.id)
        edit.add(entry: bEntry, itemId: itemId)

        root.itemController.itemDataModel.isGameMode = true
        defer { root.itemController.itemDataModel.isGameMode = false }

        guard let gameDiceId = root.gameController.gameDiceId(itemId: itemId, entryId: bEntry.id) else {
            Issue.record("expected a game dice id for entry B")
            return
        }

        func pushDiceValue() {
            let entry = root.itemController.itemOrEmpty(for: itemId)[bEntry.id]
            guard let text = sut.calculate(entry: entry), let value = Int(text) else { return }
            root.diceRoot.diceGameControllable.validateForValue(diceId: gameDiceId, compareValue: value)
        }
        // Mirrors `.onChange(of: updateOtherValue, initial: true)`: each firing
        // re-registers itself for the *next* change, not just the first.
        func armTracking() {
            sut.updateValueCalculation(itemId: itemId, entryId: bEntry.id) {
                pushDiceValue()
                armTracking()
            }
        }
        pushDiceValue()
        armTracking()

        edit.updateValue(itemId: itemId, entryId: aEntry.id, number: 35)
        try await Task.sleep(for: .milliseconds(100))
        #expect(root.diceRoot.gameController.gameItem(for: gameDiceId).compareValue == 35)

        edit.updateValue(itemId: itemId, entryId: aEntry.id, number: 15)
        try await Task.sleep(for: .milliseconds(100))
        #expect(root.diceRoot.gameController.gameItem(for: gameDiceId).compareValue == 15)
    }

    /// Reproduces the reported bug end to end: a full-package resync
    /// (`GameController.updatePlayer(data:)`, sent on reconnect or on any
    /// advertised-version mismatch — i.e. potentially after *every* edit in an
    /// active session) used to replace `gameModel.itemData[characterId]` with a
    /// fresh `.copy()` instance instead of mutating the existing one in place. That
    /// silently orphaned `LinkController.updateValueCalculation`'s
    /// `withObservationTracking` registrations (armed against entries on the *old*
    /// instance), so a linked value's *next* change — after a resync landed in
    /// between — never reached the inline dice display again, even though the
    /// calculated value kept updating correctly. `GameController.updatePlayer(data:)`
    /// now mutates the existing instance in place via `replace(with:)` instead.
    @Test func inlineDiceCountSurvivesFullResyncMidSession() async throws {
        let root = Self.makeRoot()
        let edit = root.editController
        let sut = root.linkController

        let diceTemplate = DiceModel(id: UUID(), name: "Attack Dice", dice: [DieModel(id: UUID(), die: .twenty)], addDiceEvery: 20)
        root.diceRoot.itemController.replace(model: diceTemplate, isInsert: true)

        let itemId = await root.itemController.addNew(type: .character)
        let aEntry = ValueEntryModel(id: UUID(), name: "Strength", type: .number, value: "45")
        edit.add(entry: aEntry, itemId: itemId)

        let linkText = root.itemController.itemOrEmpty(for: itemId).url(linkNumber: 0, entryId: aEntry.id)
        let bEntry = ValueEntryModel(id: UUID(), name: "Attack", type: .number, value: linkText, diceId: diceTemplate.id)
        edit.add(entry: bEntry, itemId: itemId)

        root.itemController.itemDataModel.isGameMode = true
        defer { root.itemController.itemDataModel.isGameMode = false }

        guard let gameDiceId = root.gameController.gameDiceId(itemId: itemId, entryId: bEntry.id) else {
            Issue.record("expected a game dice id for entry B")
            return
        }

        func pushDiceValue() {
            let entry = root.itemController.itemOrEmpty(for: itemId)[bEntry.id]
            guard let text = sut.calculate(entry: entry), let value = Int(text) else { return }
            root.diceRoot.diceGameControllable.validateForValue(diceId: gameDiceId, compareValue: value)
        }
        // Mirrors `EntryListDiceRow`'s actual `updateOtherValue` re-arm chain — each
        // firing re-registers itself for the *next* change, not just the first.
        func armTracking() {
            sut.updateValueCalculation(itemId: itemId, entryId: bEntry.id) {
                pushDiceValue()
                armTracking()
            }
        }

        pushDiceValue()
        armTracking()
        #expect(root.diceRoot.gameController.gameItem(for: gameDiceId).dice.count == 3)

        // First edit — this is what promotes `itemId` into `gameModel.itemData`
        // in the first place (via `EditController.updateValue` → `replaceInGameMemory`).
        edit.updateValue(itemId: itemId, entryId: aEntry.id, number: 35)
        try await Task.sleep(for: .milliseconds(100))
        #expect(root.diceRoot.gameController.gameItem(for: gameDiceId).dice.count == 2)

        // A full-package resync lands mid-session — e.g. the player's own edit
        // round-tripping back with a version the master already had, or a
        // reconnect. Build it from the item's current (already-edited) state,
        // exactly like the network layer would.
        let resyncData = try await root.gameController.createGameData(for: itemId)
        try await root.gameController.updatePlayer(data: resyncData)
        try await Task.sleep(for: .milliseconds(100))

        // The resync must not have discarded the calculated dice state that was
        // already correct.
        #expect(root.diceRoot.gameController.gameItem(for: gameDiceId).dice.count == 2)

        // Second edit, *after* the resync — this is the one that went silent
        // before the fix: tracking armed against the pre-resync instance never
        // fires again once that instance is orphaned.
        edit.updateValue(itemId: itemId, entryId: aEntry.id, number: 15)
        try await Task.sleep(for: .milliseconds(100))
        #expect(root.diceRoot.gameController.gameItem(for: gameDiceId).dice.count == 1)
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
