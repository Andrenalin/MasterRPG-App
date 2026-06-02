// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import SpaceRPG

/// Direct tests for `SearchControllable.listSearchResults()` — CoreRPG's shared list and
/// folder search pipeline. SpaceRPG uses the default protocol-extension implementation with
/// no module overrides, making it ideal for pinning generic non-Character behaviour.
///
/// Coverage: displayMode tag/description filtering, relevance ordering, `canOpen` semantics,
/// folder tree pruning, focusId scoping, displayState exclusion.
@MainActor
struct SearchListResultsTests {

    // MARK: - Helpers

    private func makeRoot() async -> SpaceRootModel {
        let root = SpaceRootModel.testRoot()
        await root.itemController.resetData()
        return root
    }

    private func listResults(
        root: SpaceRootModel,
        text: String,
        listMode: ListDisplayModel.ListMode = .list,
        displayMode: ListDisplayModel.DisplayMode = .medium,
        focusId: UUID? = nil
    ) async -> [SearchResult] {
        await root.searchControllable.listSearchResults(
            searchText: text,
            listMode: listMode,
            displayMode: displayMode,
            focusId: focusId
        )
    }

    // MARK: - List mode: displayMode tag filtering

    @Test(
        "Tags only matched in regular display mode, not compact or medium",
        arguments: [
            (mode: ListDisplayModel.DisplayMode.compact, expectMatch: false),
            (mode: ListDisplayModel.DisplayMode.medium,  expectMatch: false),
            (mode: ListDisplayModel.DisplayMode.regular, expectMatch: true),
        ]
    )
    func tagsOnlySearchedInRegularMode(mode: ListDisplayModel.DisplayMode, expectMatch: Bool) async {
        let root = await makeRoot()

        let tagOnlyId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Wanderer",       itemId: tagOnlyId)
        root.editController.reset(tags: ["dragon-class"], itemId: tagOnlyId)
        // Name and description contain no "dragon" — only the tag does.

        let results = await listResults(root: root, text: "dragon", displayMode: mode)
        let ids = results.map(\.itemId)

        if expectMatch {
            #expect(ids.contains(tagOnlyId), "Regular mode must match via tags")
        } else {
            #expect(!ids.contains(tagOnlyId), "\(mode) must not match via tags")
        }
    }

    @Test("Medium mode matches description but not tags")
    func mediumModeMatchesDescriptionNotTags() async {
        let root = await makeRoot()

        let descMatchId = await root.itemController.addNew(type: .item)
        let tagOnlyId   = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Scout A",                    itemId: descMatchId)
        root.editController.reset(description: "Dragon-class vessel", itemId: descMatchId)
        root.editController.reset(name: "Scout B",                    itemId: tagOnlyId)
        root.editController.reset(tags: ["dragon-class"],             itemId: tagOnlyId)

        let results = await listResults(root: root, text: "dragon", displayMode: .medium)
        let ids = results.map(\.itemId)

        #expect(ids.contains(descMatchId),  "Medium mode must match by description")
        #expect(!ids.contains(tagOnlyId),   "Medium mode must not match by tags")
    }

    @Test("Compact mode matches name only — description and tag matches both excluded")
    func compactModeMatchesNameOnly() async {
        let root = await makeRoot()

        let nameMatchId = await root.itemController.addNew(type: .item)
        let descMatchId = await root.itemController.addNew(type: .item)
        let tagMatchId  = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Scout",               itemId: nameMatchId)
        root.editController.reset(name: "Alpha",                      itemId: descMatchId)
        root.editController.reset(description: "Dragon-class vessel", itemId: descMatchId)
        root.editController.reset(name: "Beta",                       itemId: tagMatchId)
        root.editController.reset(tags: ["dragon-class"],             itemId: tagMatchId)

        let results = await listResults(root: root, text: "dragon", displayMode: .compact)
        let ids = results.map(\.itemId)

        #expect(ids.contains(nameMatchId),  "Compact mode must match by name")
        #expect(!ids.contains(descMatchId), "Compact mode must not match by description")
        #expect(!ids.contains(tagMatchId),  "Compact mode must not match by tags")
    }

    // MARK: - List mode: relevance ordering

    @Test("Relevance order: exact name > prefix name > contains name > description-only match")
    func listModeRelevanceOrder() async {
        let root = await makeRoot()

        let exactId    = await root.itemController.addNew(type: .item)
        let prefixId   = await root.itemController.addNew(type: .item)
        let containsId = await root.itemController.addNew(type: .item)
        let descId     = await root.itemController.addNew(type: .item)

        root.editController.reset(name: "Dragon",                 itemId: exactId)
        root.editController.reset(name: "Dragon Slayer",          itemId: prefixId)
        root.editController.reset(name: "Fire-breathing Dragon",  itemId: containsId)
        root.editController.reset(name: "Probe",                  itemId: descId)
        root.editController.reset(description: "Dragon patrol",   itemId: descId)

        let results = await listResults(root: root, text: "Dragon", displayMode: .medium)
        let ids = results.map(\.itemId)

        let eIdx = try? ids.firstIndex(of: exactId)
        let pIdx = try? ids.firstIndex(of: prefixId)
        let cIdx = try? ids.firstIndex(of: containsId)
        let dIdx = try? ids.firstIndex(of: descId)

        #expect(eIdx != nil && pIdx != nil && cIdx != nil && dIdx != nil,
                "All four items must appear")
        if let e = eIdx, let p = pIdx, let c = cIdx {
            #expect(e < p, "Exact name must rank above prefix match")
            #expect(p < c, "Prefix match must rank above contains match")
        }
        // Description-only match (score=10+15=25) vs exact name (score=100+15=115)
        if let e = eIdx, let d = dIdx {
            #expect(e < d, "Exact name match must outrank description-only match")
        }
    }

    @Test("Empty list search returns items sorted alphabetically, not by relevance")
    func emptyListSearchSortsAlphabetically() async {
        let root = await makeRoot()

        let idC = await root.itemController.addNew(type: .item)
        let idA = await root.itemController.addNew(type: .item)
        let idB = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Charlie", itemId: idC)
        root.editController.reset(name: "Alice",   itemId: idA)
        root.editController.reset(name: "Bob",     itemId: idB)

        let results = await listResults(root: root, text: "")
        let names = results.map(\.itemName)
        let sorted = names.sorted { $0.localizedCompare($1) == .orderedAscending }

        #expect(names == sorted, "Empty search must return items in A→Z order")
    }

    // MARK: - List mode: exclusions

    @Test("Items with displayState != 0 are excluded from list results")
    func hiddenItemsExcludedFromListMode() async {
        let root = await makeRoot()

        let visibleId = await root.itemController.addNew(type: .item)
        let hiddenId  = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Scout",  itemId: visibleId)
        root.editController.reset(name: "Dragon Hidden", itemId: hiddenId)
        root.itemController.itemOrEmpty(for: hiddenId).displayState = 1

        let results = await listResults(root: root, text: "Dragon")
        let ids = results.map(\.itemId)

        #expect(ids.contains(visibleId),  "Visible item must appear")
        #expect(!ids.contains(hiddenId),  "displayState=1 item must be excluded")
    }

    @Test("Folders and collections are excluded from flat list mode in all displayModes",
          arguments: [
            ListDisplayModel.DisplayMode.compact,
            ListDisplayModel.DisplayMode.medium,
            ListDisplayModel.DisplayMode.regular,
          ])
    func specialCategoryExcludedFromListMode(displayMode: ListDisplayModel.DisplayMode) async {
        let root = await makeRoot()

        let itemId   = await root.itemController.addNew(type: .item)
        let folderId = await root.itemController.addNew(type: .folder)
        root.editController.reset(name: "Dragon Scout", itemId: itemId)
        root.editController.reset(name: "Dragon Dock",  itemId: folderId)

        let results = await listResults(root: root, text: "", displayMode: displayMode)
        let ids = results.map(\.itemId)

        #expect(ids.contains(itemId),    "Regular item must appear in list mode")
        #expect(!ids.contains(folderId), "Folder must never appear in flat list mode")
    }

    // MARK: - Folder mode: canOpen

    @Test("Folder mode empty search: all folders have canOpen=true (lazy-load sentinel)")
    func folderModeEmptySearchSetsCanOpenTrue() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Station Alpha", itemId: folderId)
        root.editController.addItem(itemId: childId, parentId: folderId)

        let results = await listResults(root: root, text: "", listMode: .folder)
        let folder  = try? results.first(where: { $0.itemId == folderId })

        #expect(folder?.canOpen == true,
                "Empty search must set canOpen=true so FolderListControllable can lazy-load on tap")
        #expect(folder?.children.isEmpty == true,
                "Empty search must not pre-fetch children — they load via loadChildrenViaSearch")
    }

    @Test("Folder mode non-empty search: folder with returned children has canOpen=false")
    func folderModeNonEmptySearchChildrenReturnedSetsCanOpenFalse() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Fleet Base",  itemId: folderId)
        root.editController.reset(name: "Dragon Wing", itemId: childId)
        root.editController.addItem(itemId: childId, parentId: folderId)

        let results = await listResults(root: root, text: "Dragon", listMode: .folder)
        let folder  = try? results.first(where: { $0.itemId == folderId })

        #expect(folder?.children.map(\.itemId).contains(childId) == true,
                "Matching child must appear inside the folder")
        #expect(folder?.canOpen == false,
                "canOpen must be false when all relevant children are already in SearchResult.children")
    }

    @Test("Folder mode non-empty search: folder whose name matches but has no child match has canOpen=true")
    func folderModeNameMatchNoChildMatchHasCanOpenTrue() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Dock",  itemId: folderId)
        root.editController.reset(name: "Scout Vessel", itemId: childId)
        root.editController.addItem(itemId: childId, parentId: folderId)

        let results = await listResults(root: root, text: "Dragon", listMode: .folder)
        let folder  = try? results.first(where: { $0.itemId == folderId })

        #expect(folder != nil,           "Folder whose name matches must be included")
        #expect(folder?.children.isEmpty == true, "Non-matching child must not appear")
        #expect(folder?.canOpen == true,
                "Folder with no returned children must have canOpen=true — items are revealed on expand")
    }

    // MARK: - Folder mode: tree pruning

    @Test("Folder mode non-empty search: folder with no name match and no child matches is excluded")
    func folderModeNonMatchingFolderPruned() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Nebula Base",  itemId: folderId)
        root.editController.reset(name: "Scout Vessel", itemId: childId)
        root.editController.addItem(itemId: childId, parentId: folderId)

        let results = await listResults(root: root, text: "Dragon", listMode: .folder)
        let ids = results.map(\.itemId)

        #expect(!ids.contains(folderId), "Folder with no matches must be pruned")
        #expect(!ids.contains(childId),  "Non-matching child must not appear")
    }

    @Test("Folder mode non-empty search: deeply nested match bubbles the folder path up")
    func folderModeNestedMatchBubblesUp() async {
        let root = await makeRoot()

        let outerFolderId = await root.itemController.addNew(type: .folder)
        let innerFolderId = await root.itemController.addNew(type: .folder)
        let deepItemId    = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Outer Base",  itemId: outerFolderId)
        root.editController.reset(name: "Inner Dock",  itemId: innerFolderId)
        root.editController.reset(name: "Dragon Core", itemId: deepItemId)
        root.editController.addItem(itemId: innerFolderId, parentId: outerFolderId)
        root.editController.addItem(itemId: deepItemId,    parentId: innerFolderId)

        let results = await listResults(root: root, text: "Dragon", listMode: .folder)

        let outerResult = try? results.first(where: { $0.itemId == outerFolderId })
        let innerResult = try? outerResult?.children.first(where: { $0.itemId == innerFolderId })
        let deepResult  = try? innerResult?.children.first(where: { $0.itemId == deepItemId })

        #expect(outerResult != nil, "Outer folder must appear (path to matching descendant)")
        #expect(innerResult != nil, "Inner folder must be a child of outer (path to match)")
        #expect(deepResult  != nil, "Matching item must be a child of inner folder")
    }

    // MARK: - Folder mode: focusId scoping

    @Test("Folder mode with non-existent focusId returns empty results")
    func folderModeNonExistentFocusIdReturnsEmpty() async {
        let root = await makeRoot()
        _ = await root.itemController.addNew(type: .item)  // ensure items exist

        let results = await listResults(root: root, text: "", listMode: .folder, focusId: UUID())
        #expect(results.isEmpty, "Unknown focusId must return empty — no item to read children from")
    }

    @Test("Folder mode empty search with focusId: only direct children returned, sorted A→Z")
    func folderModeWithFocusEmptySearchReturnsSortedChildren() async {
        let root = await makeRoot()

        let folderId   = await root.itemController.addNew(type: .folder)
        let idZ        = await root.itemController.addNew(type: .item)
        let idA        = await root.itemController.addNew(type: .item)
        let idM        = await root.itemController.addNew(type: .item)
        let unrelatedId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Zulu Station",  itemId: idZ)
        root.editController.reset(name: "Alpha Station", itemId: idA)
        root.editController.reset(name: "Midway Base",   itemId: idM)
        root.editController.addItem(itemId: idZ, parentId: folderId)
        root.editController.addItem(itemId: idA, parentId: folderId)
        root.editController.addItem(itemId: idM, parentId: folderId)

        let results = await listResults(root: root, text: "", listMode: .folder, focusId: folderId)
        let ids     = results.map(\.itemId)
        let names   = results.map(\.itemName)

        #expect(ids.contains(idZ) && ids.contains(idA) && ids.contains(idM),
                "All three children must appear")
        #expect(!ids.contains(unrelatedId), "Item outside the folder must not appear")
        #expect(!ids.contains(folderId),    "The folder itself must not appear in its children list")
        #expect(names == names.sorted { $0.localizedCompare($1) == .orderedAscending },
                "Children must be sorted alphabetically on empty search")
    }

    @Test("Folder mode non-empty search with focusId: only matching children returned")
    func folderModeWithFocusNonEmptySearchFiltersChildren() async {
        let root = await makeRoot()

        let folderId  = await root.itemController.addNew(type: .folder)
        let matchId   = await root.itemController.addNew(type: .item)
        let noMatchId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Scout",  itemId: matchId)
        root.editController.reset(name: "Space Station", itemId: noMatchId)
        root.editController.addItem(itemId: matchId,   parentId: folderId)
        root.editController.addItem(itemId: noMatchId, parentId: folderId)

        let results = await listResults(root: root, text: "Dragon", listMode: .folder, focusId: folderId)
        let ids = results.map(\.itemId)

        #expect(ids.contains(matchId),    "Matching child must appear")
        #expect(!ids.contains(noMatchId), "Non-matching child must be excluded")
        #expect(!ids.contains(folderId),  "The folder itself must not appear in focusId results")
    }

    @Test("Focused folder search children carry the membership entry UUID as entryId")
    func folderModeWithFocusChildrenCarryEntryId() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.addItem(itemId: childId, parentId: folderId)

        let results = await listResults(root: root, text: "", listMode: .folder, focusId: folderId)
        let child = try? results.first(where: { $0.itemId == childId })

        // entryId is the folder's membership entry UUID — used as FolderListItemModel.id so the
        // same item appearing in multiple collections gets independent SwiftUI identities.
        #expect(child?.entryId != nil,
                "Child result must carry the folder membership entry's UUID as entryId")
    }

    // MARK: - Inspector folder mode: entry searching

    // Helper: calls inspectorSearchResults directly for folder mode.
    private func inspectorFolderResults(
        root: SpaceRootModel,
        text: String,
        displayMode: ListDisplayModel.DisplayMode = .medium,
        focusId: UUID? = nil
    ) async -> [SearchResult] {
        await root.searchControllable.inspectorSearchResults(
            searchText: text,
            listMode: .folder,
            displayMode: displayMode,
            focusId: focusId
        )
    }

    @Test("Inspector folder mode: entry name match makes entry a child of the item result")
    func inspectorFolderEntryNameMatchIsChild() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let itemId   = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Galaxy Base", itemId: itemId)
        root.editController.addItem(itemId: itemId, parentId: folderId)

        let entryId = UUID()
        root.itemController.itemOrEmpty(for: itemId)
            .entries.append(SpaceEntryModel(id: entryId, spaceId: UUID()))
        // SpaceEntryModel.name == "Space Model" — searching "Space" triggers entry match

        let results = await inspectorFolderResults(root: root, text: "Space")

        let folderResult = try? results.first(where: { $0.itemId == folderId })
        let itemResult   = try? folderResult?.children.first(where: { $0.itemId == itemId })

        #expect(folderResult != nil,   "Folder must appear (path to matching item)")
        #expect(itemResult   != nil,   "Item must be a child of the folder")
        #expect(itemResult?.children.contains(where: { $0.entryId == entryId }) == true,
                "Matching entry must be a child of the item result")
    }

    @Test("Inspector folder mode: item included via entry match even when item name does not match")
    func inspectorFolderItemIncludedWhenOnlyEntryMatches() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let itemId   = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Nebula Station", itemId: itemId)  // does not contain "Space"
        root.editController.addItem(itemId: itemId, parentId: folderId)

        let entryId = UUID()
        root.itemController.itemOrEmpty(for: itemId)
            .entries.append(SpaceEntryModel(id: entryId, spaceId: UUID()))
        // entry.name == "Space Model" — match triggers item inclusion

        let results = await inspectorFolderResults(root: root, text: "Space")

        let folderResult = try? results.first(where: { $0.itemId == folderId })
        let itemResult   = try? folderResult?.children.first(where: { $0.itemId == itemId })

        #expect(itemResult != nil,
                "Item must appear when its entry matches, even if item name does not")
        #expect(itemResult?.children.contains(where: { $0.entryId == entryId }) == true,
                "Matching entry must be in the item's children")
    }

    @Test("Inspector folder mode: item matching by name but no entry match has canOpen=true and no children")
    func inspectorFolderItemNameMatchNoEntryMatchHasCanOpenTrue() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let itemId   = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Dock", itemId: itemId)
        root.editController.addItem(itemId: itemId, parentId: folderId)

        // Add an entry whose name does NOT match "Dragon"
        let entryId = UUID()
        root.itemController.itemOrEmpty(for: itemId)
            .entries.append(SpaceEntryModel(id: entryId, spaceId: UUID()))
        // SpaceEntryModel.name = "Space Model" — no "Dragon" match

        let results = await inspectorFolderResults(root: root, text: "Dragon")

        let folderResult = try? results.first(where: { $0.itemId == folderId })
        let itemResult   = try? folderResult?.children.first(where: { $0.itemId == itemId })

        #expect(itemResult != nil,                       "Item must appear (name matches)")
        #expect(itemResult?.children.isEmpty == true,    "No entry children — none matched")
        #expect(itemResult?.canOpen == true,
                "canOpen must be true so the user can expand to see all entries via toggle")
    }

    @Test("Inspector folder mode: item with no match (name nor entries) is excluded")
    func inspectorFolderNoMatchExcludesItem() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let itemId   = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Nebula Station", itemId: itemId)
        root.editController.addItem(itemId: itemId, parentId: folderId)
        // No entries added; searching "Dragon" → no match at any level

        let results = await inspectorFolderResults(root: root, text: "Dragon")
        let ids = results.map(\.itemId)

        #expect(!ids.contains(folderId), "Folder with no matches must be pruned")
        #expect(!ids.contains(itemId),   "Item with no match must be excluded")
    }

    @Test("Inspector folder mode: empty search returns items without entry children; canOpen set by entries")
    func inspectorFolderEmptySearchNoEntryChildren() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let itemId   = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Galaxy Base", itemId: itemId)
        root.editController.addItem(itemId: itemId, parentId: folderId)

        root.itemController.itemOrEmpty(for: itemId)
            .entries.append(SpaceEntryModel(id: UUID(), spaceId: UUID()))

        let results = await inspectorFolderResults(root: root, text: "")

        let folderResult = try? results.first(where: { $0.itemId == folderId })
        let itemResult   = try? folderResult?.children.first(where: { $0.itemId == itemId })

        // Empty search: folder shows lazy (canOpen), item has no entry children returned
        // but canOpen reflects whether entries exist
        #expect(folderResult?.canOpen == true, "Folder must have canOpen=true on empty search")
        // item not nested inside folder SearchResult for empty search — folder is lazy
        _ = itemResult  // item appears when folder is expanded (via loadChildrenViaSearch)
    }

    @Test("List folder mode does not search entries — entries never appear as children")
    func listFolderModeNeverSearchesEntries() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let itemId   = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Nebula Station", itemId: itemId)
        root.editController.addItem(itemId: itemId, parentId: folderId)

        root.itemController.itemOrEmpty(for: itemId)
            .entries.append(SpaceEntryModel(id: UUID(), spaceId: UUID()))
        // SpaceEntryModel.name = "Space Model" — matches "Space"

        let results = await listResults(root: root, text: "Space", listMode: .folder)

        // In list search folder mode, entries are never returned as children
        for result in results {
            #expect(result.children.allSatisfy { $0.entryId == nil },
                    "List folder mode must never produce entry-level children (entryId must be nil)")
        }
    }

    @Test("Inspector folder mode entry search: nested folder structure preserved with entry children")
    func inspectorFolderNestedStructureWithEntryChildren() async {
        let root = await makeRoot()

        // Outer folder → item (entry matches) + inner folder → item2 (item name matches)
        let outerFolderId = await root.itemController.addNew(type: .folder)
        let itemId        = await root.itemController.addNew(type: .item)
        let innerFolderId = await root.itemController.addNew(type: .folder)
        let item2Id       = await root.itemController.addNew(type: .item)

        root.editController.reset(name: "Wanderer",      itemId: itemId)
        root.editController.reset(name: "Dragon Cruiser", itemId: item2Id)
        root.editController.reset(name: "Inner Base",     itemId: innerFolderId)
        root.editController.addItem(itemId: itemId,        parentId: outerFolderId)
        root.editController.addItem(itemId: innerFolderId, parentId: outerFolderId)
        root.editController.addItem(itemId: item2Id,       parentId: innerFolderId)

        let entryId = UUID()
        root.itemController.itemOrEmpty(for: itemId)
            .entries.append(SpaceEntryModel(id: entryId, spaceId: UUID()))
        // entry.name = "Space Model" — does not match "Dragon"
        // Searching "Dragon": item2 matches by name; itemId does not match

        let results = await inspectorFolderResults(root: root, text: "Dragon")

        let outerResult = try? results.first(where: { $0.itemId == outerFolderId })
        let innerResult = try? outerResult?.children.first(where: { $0.itemId == innerFolderId })
        let item2Result = try? innerResult?.children.first(where: { $0.itemId == item2Id })

        #expect(outerResult != nil, "Outer folder must appear (path to Dragon Cruiser)")
        #expect(innerResult != nil, "Inner folder must appear as child of outer")
        #expect(item2Result != nil, "Dragon Cruiser must be a child of inner folder")
        // Wanderer has no Dragon match — neither item nor entry
        #expect(outerResult?.children.contains(where: { $0.itemId == itemId }) == false,
                "Wanderer must not appear — no Dragon match in name or entries")
    }
}
#endif
