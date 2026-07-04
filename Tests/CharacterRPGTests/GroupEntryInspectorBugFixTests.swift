// @copyright André Trettin

#if canImport(Testing)
import Foundation
import DiceRPG
import RPGResourcesDebug
import Testing

@testable import CoreRPG
@testable import CharacterRPG

/// Regression tests for three bugs in the character group-entry inspector:
///
/// **Bug 1** — `resetFilter()` only rebuilt `listModel.list` (main). When the inspector used
/// `detailListModel`, toggling a group entry appeared as a no-op because the detail list
/// was never updated. Fix: `resetFilter()` now also rebuilds `detailListModel.list`.
///
/// **Bug 2** — Sub-entries were created with `itemId = characterId`. Views resolved
/// `model?[subEntry.id]` against the character model, which doesn't own sub-entries →
/// empty text. Fix: sub-entries now use `itemId = subValueId` so the lookup hits the
/// sub-value model that actually holds them.
///
/// **Bug 3** — `focusedCharacterInspector` only searched `entry.name`, `entry.content`,
/// and `subValue.name`. Sub-entry names/content (e.g. "Axe Mastery") were invisible to
/// search. Fix: the loop now also checks each sub-entry's name and content.
@MainActor
struct GroupEntryInspectorBugFixTests {

    // MARK: - Helpers

    private func makeRoot() async throws -> CharacterRootModel {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        return root
    }

    /// Creates a character with one group entry and one named sub-entry inside it.
    /// Returns (charId, groupEntryId, subValueId, subEntryId).
    private func makeCharacterWithSubEntry(
        root: CharacterRootModel,
        charName: String       = "Thorin",
        groupEntryName: String = "Combat Skills",
        subEntryName: String   = "Axe Mastery",
        subEntryContent: String = "Deals extra cleave damage"
    ) async throws -> (charId: UUID, groupEntryId: UUID, subValueId: UUID, subEntryId: UUID) {
        let charId       = await root.itemController.addNew(type: .item)
        root.editController.reset(name: charName, itemId: charId)

        let groupEntryId = await root.editController.addNewGroup(itemId: charId)
        root.editController.update(itemId: charId, entryId: groupEntryId,
                                   name: groupEntryName, content: "")

        let char       = root.itemController.itemOrEmpty(for: charId)
        let groupEntry = try #require(char.entries.first(where: { $0.id == groupEntryId }))
        let subValueId = try #require(groupEntry.valueId)

        let subEntryId = await root.editController.addNewGroup(itemId: subValueId)
        root.editController.update(itemId: subValueId, entryId: subEntryId,
                                   name: subEntryName, content: subEntryContent)

        return (charId, groupEntryId, subValueId, subEntryId)
    }

    // MARK: - Bug 1: resetFilter updates detailListModel

    @Test("Toggling group entry in detail mode updates detailListModel.list — not just main list")
    func toggleGroupEntryUpdatesDetailList() async throws {
        let root = try await makeRoot()
        let (charId, groupEntryId, _, subEntryId) =
            try await makeCharacterWithSubEntry(root: root)

        guard let charModel = root.itemController.itemSync(for: charId) else {
            #expect(Bool(false), "Character must be findable via itemSync")
            return
        }

        // Mimic what LinkItemListView does: resetDetail creates detailListModel,
        // then performDetailSearch populates it via focusedCharacterInspector.
        root.folderLinkController.resetDetail(model: charModel)
        await root.folderLinkController.performDetailSearch()

        let detailList = root.folderLinkController.listModel.detailListModel?.list ?? []
        #expect(!detailList.isEmpty, "detailListModel.list must be populated after detail search")

        // Find the group entry item in the flat detail list (character is auto-opened by shouldOpen)
        let groupItem = try #require(
            detailList.first(where: { $0.source.entryId == groupEntryId }),
            "Group entry must appear in detailListModel.list"
        )
        #expect(groupItem.canOpen == true, "Group entry must have canOpen=true")
        #expect(groupItem.isOpen  == false, "Group entry must start closed")
        #expect(!detailList.contains(where: { $0.source.entryId == subEntryId }),
                "Sub-entry must not be in flat list before toggle")

        // Toggle opens the group entry and loads sub-entries via loadChildrenViaSearch.
        // resetFilter() must then rebuild detailListModel.list (Bug 1 fix).
        root.folderLinkController.toggleFolder(item: groupItem)

        let updatedList = root.folderLinkController.listModel.detailListModel?.list ?? []
        #expect(updatedList.contains(where: { $0.source.entryId == subEntryId }),
                "Sub-entry must appear in detailListModel.list after toggle — resetFilter must update detail list")
    }

    @Test("Closing an open group entry in detail mode removes sub-entries from detailListModel.list")
    func closingGroupEntryUpdatesDetailList() async throws {
        let root = try await makeRoot()
        let (charId, groupEntryId, _, subEntryId) =
            try await makeCharacterWithSubEntry(root: root)

        guard let charModel = root.itemController.itemSync(for: charId) else { return }

        root.folderLinkController.resetDetail(model: charModel)
        await root.folderLinkController.performDetailSearch()

        let groupItem = try #require(
            root.folderLinkController.listModel.detailListModel?.list
                .first(where: { $0.source.entryId == groupEntryId })
        )

        // Open then close
        root.folderLinkController.toggleFolder(item: groupItem)
        #expect(root.folderLinkController.listModel.detailListModel?.list
            .contains(where: { $0.source.entryId == subEntryId }) == true,
                "Sub-entry visible after open")

        let openedItem = try #require(
            root.folderLinkController.listModel.detailListModel?.list
                .first(where: { $0.source.entryId == groupEntryId })
        )
        root.folderLinkController.toggleFolder(item: openedItem)

        #expect(!root.folderLinkController.listModel.detailListModel!.list
            .contains(where: { $0.source.entryId == subEntryId }),
                "Sub-entry must disappear from detailListModel.list after closing the group entry")
    }

    // MARK: - Bug 2: sub-entries use subValueId as itemId

    @Test("Empty inspector search: group entry sub-entries carry subValueId as itemId (not characterId)")
    func emptySearchSubEntriesHaveSubValueIdAsItemId() async throws {
        let root = try await makeRoot()
        let (charId, groupEntryId, subValueId, subEntryId) =
            try await makeCharacterWithSubEntry(root: root)

        let results = await root.searchController.inspectorSearchResults(
            searchText: "",
            listMode: .list,
            displayMode: .medium,
            focusId: charId
        )

        let charResult = try #require(results.first(where: { $0.itemId == charId }))
        let groupResult = try #require(
            charResult.children.first(where: { $0.entryId == groupEntryId }),
            "Group entry must be a child of the character result on empty search"
        )
        let subResult = try #require(
            groupResult.children.first(where: { $0.entryId == subEntryId }),
            "Sub-entry must be a child of the group entry result"
        )

        #expect(subResult.itemId == subValueId,
                "Sub-entry itemId must be subValueId — the sub-value model owns the sub-entry")
        #expect(subResult.itemId != charId,
                "Sub-entry itemId must NOT be characterId — character model doesn't hold sub-entries")
    }

    @Test("FolderListItemModel for sub-entry has model pointing to sub-value (not character)")
    func detailListSubEntryModelPointsToSubValue() async throws {
        let root = try await makeRoot()
        let (charId, groupEntryId, subValueId, subEntryId) =
            try await makeCharacterWithSubEntry(root: root)

        guard let charModel = root.itemController.itemSync(for: charId) else { return }

        root.folderLinkController.resetDetail(model: charModel)
        await root.folderLinkController.performDetailSearch()

        let groupItem = try #require(
            root.folderLinkController.listModel.detailListModel?.list
                .first(where: { $0.source.entryId == groupEntryId })
        )
        root.folderLinkController.toggleFolder(item: groupItem)

        let subEntryItem = try #require(
            root.folderLinkController.listModel.detailListModel?.list
                .first(where: { $0.source.entryId == subEntryId }),
            "Sub-entry must be in detail list after toggle"
        )

        // item.model is set by mapResult via itemSync(for: result.itemId).
        // result.itemId = subValueId for sub-entries (Bug 2 fix).
        // The sub-value model must own the sub-entry — character model does not.
        let subValue = root.itemController.itemSync(for: subValueId)
        #expect(subEntryItem.model != nil,
                "Sub-entry FolderListItemModel.model must not be nil")
        #expect(subEntryItem.source.itemId == subValueId,
                "Sub-entry source.itemId must equal subValueId so model?[entryId] resolves")
        #expect(subValue?.entries.contains(where: { $0.id == subEntryId }) == true,
                "Sanity: sub-value owns the sub-entry")
    }

    // MARK: - Bug 3: search matches sub-entry names and content

    @Test("Search on sub-entry name makes its parent group entry appear in results")
    func searchMatchesSubEntryName() async throws {
        let root = try await makeRoot()
        let (charId, groupEntryId, _, subEntryId) =
            try await makeCharacterWithSubEntry(root: root, subEntryName: "Axe Mastery")

        let results = await root.searchController.inspectorSearchResults(
            searchText: "Axe",
            listMode: .list,
            displayMode: .medium,
            focusId: charId
        )

        let charResult = try #require(results.first(where: { $0.itemId == charId }),
                                      "Character must appear when sub-entry name matches")
        let groupResult = try #require(
            charResult.children.first(where: { $0.entryId == groupEntryId }),
            "Group entry must appear because its sub-entry 'Axe Mastery' matches 'Axe'"
        )
        #expect(!groupResult.children.isEmpty,
                "Group entry must include its sub-entry children when they match the search")
        #expect(groupResult.children.contains(where: { $0.entryId == subEntryId }),
                "Matching sub-entry must be in group entry's children")
        _ = subEntryId
    }

    @Test("Search on sub-entry content makes its parent group entry appear in results")
    func searchMatchesSubEntryContent() async throws {
        let root = try await makeRoot()
        let (charId, groupEntryId, _, subEntryId) =
            try await makeCharacterWithSubEntry(
                root: root,
                subEntryName: "Power Strike",
                subEntryContent: "Cleave through multiple enemies"
            )

        // "Cleave" only in content — not in entry name, group entry name, or sub-value name
        let results = await root.searchController.inspectorSearchResults(
            searchText: "Cleave",
            listMode: .list,
            displayMode: .medium,
            focusId: charId
        )

        let charResult = try #require(results.first(where: { $0.itemId == charId }),
                                      "Character must appear when sub-entry content matches")
        let groupResult = try #require(
            charResult.children.first(where: { $0.entryId == groupEntryId }),
            "Group entry must appear because its sub-entry content contains 'Cleave'"
        )
        #expect(groupResult.children.contains(where: { $0.entryId == subEntryId }),
                "Sub-entry whose content matches must be in group entry's children")
        _ = subEntryId
    }

    @Test("Group entry excluded when only sub-entry content misses the search text")
    func groupEntryExcludedWhenSubEntryContentMisses() async throws {
        let root = try await makeRoot()
        let (charId, groupEntryId, _, _) =
            try await makeCharacterWithSubEntry(
                root: root,
                groupEntryName: "Defense",
                subEntryName:   "Shield Block",
                subEntryContent: "Absorb incoming damage"
            )

        let results = await root.searchController.inspectorSearchResults(
            searchText: "Dragon",    // matches nothing in this character
            listMode: .list,
            displayMode: .medium,
            focusId: charId
        )

        let charResult = try #require(results.first(where: { $0.itemId == charId }),
                                      "Focused character always returns even with no matches")
        #expect(!charResult.children.contains(where: { $0.entryId == groupEntryId }),
                "Group entry must not appear: neither its name, content, sub-value name, nor sub-entry content matches 'Dragon'")
    }

    @Test("Two group entries: only matching one appears, sub-entry children included")
    func onlyMatchingGroupEntryAppears() async throws {
        let root = try await makeRoot()
        let charId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Gimli", itemId: charId)

        // Group entry 1: has sub-entry containing "Axe"
        let group1Id = await root.editController.addNewGroup(itemId: charId)
        root.editController.update(itemId: charId, entryId: group1Id, name: "Combat", content: "")
        let char   = root.itemController.itemOrEmpty(for: charId)
        let entry1 = try #require(char.entries.first(where: { $0.id == group1Id }))
        let sub1   = try #require(entry1.valueId)
        let subE1  = await root.editController.addNewGroup(itemId: sub1)
        root.editController.update(itemId: sub1, entryId: subE1, name: "Axe Throw", content: "")

        // Group entry 2: sub-entry has no mention of "Axe"
        let group2Id = await root.editController.addNewGroup(itemId: charId)
        root.editController.update(itemId: charId, entryId: group2Id, name: "Defense", content: "")
        let char2  = root.itemController.itemOrEmpty(for: charId)
        let entry2 = try #require(char2.entries.first(where: { $0.id == group2Id }))
        let sub2   = try #require(entry2.valueId)
        let subE2  = await root.editController.addNewGroup(itemId: sub2)
        root.editController.update(itemId: sub2, entryId: subE2, name: "Shield Block", content: "")

        let results = await root.searchController.inspectorSearchResults(
            searchText: "Axe",
            listMode: .list,
            displayMode: .medium,
            focusId: charId
        )

        let charResult = try #require(results.first(where: { $0.itemId == charId }))
        #expect(charResult.children.contains(where: { $0.entryId == group1Id }),
                "Group 1 must appear — its sub-entry 'Axe Throw' matches")
        #expect(!charResult.children.contains(where: { $0.entryId == group2Id }),
                "Group 2 must not appear — no 'Axe' anywhere in it")
    }
}

// MARK: - Bug 3: performDetailSearch with folder listMode must not return empty for character inspector

/// Regression test for the bug where `performDetailSearch` using `results(text:)` + `filterId`
/// called `inspectorSearchResults(.folder, focusId: charId)` when `listMode = .folder`.
/// `folderModeCharacterResults(focusId: charId)` then iterated the character's entries,
/// but `buildCharacterFolderNode` skipped sub-values (`groupId != nil`) → empty results.
///
/// Fix: `performDetailSearch` now uses `scopedResults(text:, focusId:)` which in
/// `SearchLinkController` always uses `.list` mode — ensuring `focusedCharacterInspector`
/// is called regardless of the inspector's current listMode toggle.
@MainActor
struct CharacterInspectorFolderModeBugFixTests {

    private func makeRoot() async throws -> CharacterRootModel {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        return root
    }

    @Test("Focused character inspector in folder mode still returns entries (scopedResults always uses list mode)")
    func focusedInspectorFolderModeReturnsEntries() async throws {
        let root = try await makeRoot()
        let charId       = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Gimli", itemId: charId)
        let groupEntryId = await root.editController.addNewGroup(itemId: charId)
        root.editController.update(itemId: charId, entryId: groupEntryId, name: "Axe Skills", content: "")

        guard let charModel = root.itemController.itemSync(for: charId) else {
            #expect(Bool(false), "Character must be findable")
            return
        }

        // Switch to folder mode — the old bug: performDetailSearch called results(text:) which
        // used filterId and listMode=.folder → folderModeCharacterResults(focusId: charId)
        // → iterates character entries → buildCharacterFolderNode skips sub-values → empty list.
        root.folderLinkController.listDisplayModel.listMode = .folder
        root.folderLinkController.resetDetail(model: charModel)
        await root.folderLinkController.performDetailSearch()

        let detailList = root.folderLinkController.listModel.detailListModel?.list ?? []

        #expect(detailList.contains(where: { $0.source.itemId == charId }),
                "Character must appear in detail list even when inspector is in folder mode")
        #expect(detailList.contains(where: { $0.source.entryId == groupEntryId }),
                "Group entry must appear — scopedResults uses list mode, not folder mode")
    }

    @Test("Focused character inspector: folder mode toggle does not break entry display")
    func folderModeTogglePreservesEntries() async throws {
        let root = try await makeRoot()
        let charId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Legolas", itemId: charId)
        _ = await root.editController.addNewGroup(itemId: charId)
        _ = await root.editController.addNewGroup(itemId: charId)

        guard let charModel = root.itemController.itemSync(for: charId) else { return }

        // Start in list mode — should work
        root.folderLinkController.listDisplayModel.listMode = .list
        root.folderLinkController.resetDetail(model: charModel)
        await root.folderLinkController.performDetailSearch()
        let listModeCount = root.folderLinkController.listModel.detailListModel?.list.count ?? 0
        #expect(listModeCount > 0, "Detail list must be populated in list mode")

        // Switch to folder mode — must still return same structure (not empty)
        root.folderLinkController.listDisplayModel.listMode = .folder
        await root.folderLinkController.performDetailSearch()
        let folderModeCount = root.folderLinkController.listModel.detailListModel?.list.count ?? 0
        #expect(folderModeCount == listModeCount,
                "Folder mode toggle must not change the detail list — scopedResults always uses list mode for inspector")
    }
}

// MARK: - Character inspector: toggle during search shows all sub-entries

@MainActor
struct CharacterInspectorToggleAllContentTests {

    private func makeRoot() async throws -> CharacterRootModel {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        return root
    }

    @Test("Focused inspector: toggling group entry during search shows ALL sub-entries — not just matching ones")
    func focusedInspectorGroupEntryToggleShowsAllSubEntries() async throws {
        let root = try await makeRoot()

        let charId       = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Gimli", itemId: charId)
        let groupEntryId = await root.editController.addNewGroup(itemId: charId)
        root.editController.update(itemId: charId, entryId: groupEntryId, name: "Combat Skills", content: "")

        let char       = root.itemController.itemOrEmpty(for: charId)
        let groupEntry = try #require(char.entries.first(where: { $0.id == groupEntryId }))
        let subValueId = try #require(groupEntry.valueId)

        // Add sub-entries: NONE match "Combat" in their name
        let subE1 = await root.editController.addNewGroup(itemId: subValueId)
        let subE2 = await root.editController.addNewGroup(itemId: subValueId)
        let subE3 = await root.editController.addNewGroup(itemId: subValueId)
        root.editController.update(itemId: subValueId, entryId: subE1, name: "Footwork",   content: "Movement")
        root.editController.update(itemId: subValueId, entryId: subE2, name: "Guard",      content: "Defense")
        root.editController.update(itemId: subValueId, entryId: subE3, name: "Riposte",    content: "Counter")

        guard let charModel = root.itemController.itemSync(for: charId) else { return }

        // Search "Combat" → group entry name matches, but sub-entries don't
        root.folderLinkController.resetDetail(model: charModel)
        await root.folderLinkController.performDetailSearch()
        root.folderLinkController.searchModel.searchText = "Combat"
        await root.folderLinkController.performDetailSearch()

        let groupItem = try #require(
            root.folderLinkController.listModel.detailListModel?.list
                .first(where: { $0.source.entryId == groupEntryId }),
            "Group entry must appear when its name matches 'Combat'"
        )
        #expect(groupItem.canOpen == true,  "Group entry has canOpen=true")
        #expect(groupItem.isOpen == false,  "Starts closed (sub-entries don't match 'Combat')")

        // Toggle → ALL sub-entries must appear (not just 'Combat' matches)
        root.folderLinkController.toggleFolder(item: groupItem)

        let detailList = root.folderLinkController.listModel.detailListModel?.list ?? []
        #expect(detailList.contains(where: { $0.source.entryId == subE1 }),
                "Footwork must appear — loadChildrenViaSearch uses empty text, ignores 'Combat' filter")
        #expect(detailList.contains(where: { $0.source.entryId == subE2 }),
                "Guard must appear")
        #expect(detailList.contains(where: { $0.source.entryId == subE3 }),
                "Riposte must appear")
    }

    @Test("Common inspector: toggling character during search shows ALL entries")
    func commonInspectorCharacterToggleShowsAllEntries() async throws {
        let root = try await makeRoot()

        let charId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Aragorn", itemId: charId)

        let e1 = await root.editController.addNewGroup(itemId: charId)
        let e2 = await root.editController.addNewGroup(itemId: charId)
        let e3 = await root.editController.addNewGroup(itemId: charId)
        root.editController.update(itemId: charId, entryId: e1, name: "Sword Skill",   content: "Expert")
        root.editController.update(itemId: charId, entryId: e2, name: "Archery",       content: "Proficient")
        root.editController.update(itemId: charId, entryId: e3, name: "Leadership",    content: "Natural")
        // None of the entry names contain "Aragorn"

        // Search "Aragorn" → character appears by name, canOpen=true, entries don't match
        root.folderLinkController.searchModel.filterId = nil
        root.folderLinkController.searchModel.searchText = "Aragorn"
        await root.folderLinkController.performSearch(source: "test")

        let charItem = try #require(
            root.folderLinkController.listModel.list.first(where: { $0.source.itemId == charId })
        )
        #expect(charItem.canOpen == true,  "Character has canOpen=true")
        #expect(charItem.isOpen == false,  "Starts closed")

        // Toggle → ALL entries must appear (none match "Aragorn" by entry name)
        root.folderLinkController.toggleFolder(item: charItem)

        let flat = root.folderLinkController.listModel.list
        #expect(flat.contains(where: { $0.source.entryId == e1 }), "Sword Skill must appear")
        #expect(flat.contains(where: { $0.source.entryId == e2 }), "Archery must appear")
        #expect(flat.contains(where: { $0.source.entryId == e3 }), "Leadership must appear")
    }
}
#endif
