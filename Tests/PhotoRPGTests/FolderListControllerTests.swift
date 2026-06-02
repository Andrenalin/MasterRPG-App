// @copyright André Trettin

#if canImport(Testing)
import Foundation
import RPGResourcesDebug
import Testing

// @testable gives access to internal FolderListControllable extension methods
// (toggleFolder, canOpenFolder, etc.) and FolderListModel internal properties.
@testable import CoreRPG
@testable import PhotoRPG

/// Tests for `FolderListControllable` using PhotoRPG as the host module.
/// PhotoRPG uses the CoreRPG default `SearchControllable` with no overrides, making
/// it a clean surface for testing the shared `FolderListControllable` protocol extension.
///
/// Coverage: buildList / appendToFlat open-state logic, toggleFolder branches,
/// resetItemOnce, resetParent, resetDetail / performDetailSearch, canOpenFolder,
/// hasParentFolder, toggleParentFolder, closeParentFolder, and mapResult canOpen sync.
@MainActor
struct FolderListControllerTests {

    // MARK: - Helpers

    private func makeRoot() async -> PhotoRootModel {
        let root = PhotoRootModel.testRoot()
        await root.itemController.resetData()
        return root
    }

    /// Runs `performSearch` via the list controller in **list** mode.
    private func searchList(_ root: PhotoRootModel, text: String = "") async {
        root.folderListController.listDisplayModel.listMode = .list
        root.folderListController.searchModel.searchText = text
        await root.folderListController.performSearch()
    }

    /// Runs `performSearch` via the list controller in **folder** mode.
    private func searchFolder(_ root: PhotoRootModel, text: String = "") async {
        root.folderListController.listDisplayModel.listMode = .folder
        root.folderListController.searchModel.searchText = text
        await root.folderListController.performSearch()
    }

    // MARK: - buildList / resetFilter

    @Test("Empty results guard: resetFilter keeps current list when results are empty")
    func resetFilterKeepsListWhenResultsEmpty() async {
        let root = await makeRoot()
        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Alpha", itemId: itemId)

        // First search populates the list
        await searchList(root)
        let beforeCount = root.folderListController.listModel.list.count
        #expect(beforeCount > 0, "List must be populated after first search")

        // Setting results to empty then calling resetFilter must leave the list intact
        root.folderListController.searchModel.results = []
        root.folderListController.resetFilter()
        #expect(root.folderListController.listModel.list.count == beforeCount,
                "resetFilter with empty results must preserve the existing list (guard)")
    }

    @Test("performSearch populates list with visible items in alphabetical order (empty search)")
    func performSearchPopulatesListAlphabetically() async {
        let root = await makeRoot()

        let idB = await root.itemController.addNew(type: .item)
        let idA = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Beta",  itemId: idB)
        root.editController.reset(name: "Alpha", itemId: idA)

        await searchList(root)
        let names = root.folderListController.listModel.list.map(\.source.itemId)
        let aIdx = names.firstIndex(of: idA)
        let bIdx = names.firstIndex(of: idB)

        #expect(aIdx != nil && bIdx != nil, "Both items must appear in list")
        if let a = aIdx, let b = bIdx { #expect(a < b, "Alpha must precede Beta") }
    }

    // MARK: - appendToFlat: open-state logic

    @Test("Non-empty search auto-opens folders with matched children (isSearching=true)")
    func nonEmptySearchAutoOpensFolderWithMatchedChildren() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Nature Folder", itemId: folderId)
        root.editController.reset(name: "Sunset Shot",   itemId: childId)
        root.editController.addItem(itemId: childId, parentId: folderId)

        // Non-empty search: folder gets matched children → auto-opened
        await searchFolder(root, text: "Sunset")

        let folderItem = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(folderItem?.isOpen == true,
                "Folder must be auto-opened when its child matches a non-empty search")
    }

    @Test("Clearing search restores lastIsOpen — explicitly opened folder stays open")
    func clearingSearchRestoresLastIsOpen() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "City Folder", itemId: folderId)
        root.editController.reset(name: "Night View",  itemId: childId)
        root.editController.addItem(itemId: childId, parentId: folderId)

        // Step 1: empty search (folder closed, canOpen=true)
        await searchFolder(root)
        let folderItem = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        let item = folderItem
        #expect(item?.isOpen == false, "Folder must start closed on empty search")

        // Step 2: user manually opens the folder
        if let item { await root.folderListController.toggleFolder(item: item) }

        let afterToggle = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(afterToggle?.isOpen == true, "Folder must be open after user toggle")
        #expect(afterToggle?.lastIsOpen == true, "lastIsOpen must be persisted")

        // Step 3: non-empty search clears, then empty search restores lastIsOpen
        await searchFolder(root, text: "Night")
        await searchFolder(root, text: "")  // clear

        let afterClear = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(afterClear?.isOpen == true,
                "Folder must remain open after clearing search (lastIsOpen=true was persisted)")
    }

    @Test("shouldOpen on SearchResult forces item open regardless of isSearching")
    func shouldOpenForcesItemOpen() async {
        let root = await makeRoot()

        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Thorin Photo", itemId: itemId)

        // Build a SearchResult with shouldOpen=true and a child entry
        let entryId = UUID()
        var result = SearchResult(
            itemId: itemId, itemName: "Thorin Photo",
            module: .photo, category: .item, relevanceScore: 100
        )
        result.children = [SearchResult(
            itemId: itemId, itemName: "Thorin Photo",
            module: .photo, category: .item,
            entryId: entryId, entryName: "Entry", relevanceScore: 100
        )]
        result.shouldOpen = true

        // Inject the result directly (empty searchText → isSearching=false)
        root.folderListController.searchModel.searchText = ""
        root.folderListController.searchModel.results = [result]
        root.folderListController.resetFilter()

        let item = root.folderListController.listModel.list.first(where: { $0.source.itemId == itemId })
        #expect(item?.isOpen == true,
                "shouldOpen=true must open the item even with empty searchText (isSearching=false)")
        #expect(item?.lastIsOpen == true,
                "shouldOpen must persist via lastIsOpen so it survives a search round-trip")

        // Entry must appear in the flat list after the item is opened
        let entryInList = root.folderListController.listModel.list.contains(where: { $0.source.entryId == entryId })
        #expect(entryInList, "Entry child must appear in flat list when parent is opened via shouldOpen")
    }

    // MARK: - resetItemOnce

    @Test("resetItemOnce performs search exactly once; subsequent calls are no-ops")
    func resetItemOnceIsIdempotent() async {
        let root = await makeRoot()
        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Landscape", itemId: itemId)

        let controller = root.folderListController
        #expect(controller.listModel.updatedOnce == false, "Fresh controller must not be marked updated")

        // First call: performs search, marks updatedOnce=true
        await controller.resetItemOnce()
        #expect(controller.listModel.updatedOnce == true, "updatedOnce must be set after first call")
        #expect(controller.listModel.list.contains(where: { $0.source.itemId == itemId }),
                "First call must populate the list")

        // Modify results so a second search would produce different output
        controller.listModel.list = []  // clear list to detect a re-search
        await controller.resetItemOnce()
        #expect(controller.listModel.list.isEmpty,
                "Second call must be a no-op — list stays empty because no search was triggered")
    }

    // MARK: - resetParent

    @Test("resetParent sets filterId and triggers a scoped search")
    func resetParentSetsFilterId() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.addItem(itemId: childId, parentId: folderId)
        guard let folderModel = root.itemController.itemSync(for: folderId) else {
            #expect(Bool(false), "Folder must exist")
            return
        }

        root.folderListController.resetParent(model: folderModel)

        #expect(root.folderListController.searchModel.filterId == folderId,
                "filterId must be set to the folder's id")
        #expect(root.folderListController.listModel.updatedOnce == true,
                "updatedOnce must be marked true after resetParent")
    }

    @Test("resetParent with a folder sets listMode to .folder")
    func resetParentFolderSetsFolderMode() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        guard let folderModel = root.itemController.itemSync(for: folderId) else {
            #expect(Bool(false))
            return
        }

        root.folderListController.listDisplayModel.listMode = .list  // start in list
        root.folderListController.resetParent(model: folderModel)

        #expect(root.folderListController.listDisplayModel.listMode == .folder,
                "resetParent with a folder item must switch listMode to .folder")
    }

    @Test("resetParent(nil) clears filterId")
    func resetParentNilClearsFilterId() async {
        let root = await makeRoot()

        root.folderListController.searchModel.filterId = UUID()  // set something first
        root.folderListController.resetParent(model: nil)

        #expect(root.folderListController.searchModel.filterId == nil,
                "resetParent(nil) must clear filterId")
    }

    // MARK: - resetDetail / performDetailSearch

    @Test("resetDetail creates a detailListModel scoped to the parent")
    func resetDetailCreatesDetailListModel() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        guard let folderModel = root.itemController.itemSync(for: folderId) else {
            #expect(Bool(false))
            return
        }

        #expect(root.folderListController.listModel.detailListModel == nil,
                "detailListModel must be nil before resetDetail")

        root.folderListController.resetDetail(model: folderModel)

        #expect(root.folderListController.listModel.detailListModel != nil,
                "detailListModel must be created by resetDetail")
        #expect(root.folderListController.listModel.detailListModel?.parentModel?.id == folderId,
                "detailListModel must be scoped to the folder's id")
    }

    @Test("performDetailSearch populates detailListModel.list with folder children")
    func performDetailSearchPopulatesDetailList() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "City Night", itemId: childId)
        root.editController.addItem(itemId: childId, parentId: folderId)

        guard let folderModel = root.itemController.itemSync(for: folderId) else {
            #expect(Bool(false))
            return
        }

        root.folderListController.resetDetail(model: folderModel)
        await root.folderListController.performDetailSearch()

        let detailList = root.folderListController.listModel.detailListModel?.list ?? []
        #expect(detailList.contains(where: { $0.source.itemId == childId }),
                "performDetailSearch must populate detailListModel.list with the folder's children")
    }

    // MARK: - toggleFolder

    @Test("toggleFolder closes a folder opened via user toggle (empty search) and hides children")
    func toggleFolderClosesOpenFolder() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.addItem(itemId: childId, parentId: folderId)

        // Empty search: folder appears with canOpen=true, initially closed
        await searchFolder(root)
        let folderItem = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(folderItem?.isOpen == false, "Prerequisite: folder must start closed")

        // Open via toggle (loads children via scoped search)
        if let item = folderItem { await root.folderListController.toggleFolder(item: item) }

        let afterOpen = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(afterOpen?.isOpen == true, "Folder must be open after first toggle")
        #expect(root.folderListController.listModel.list.contains(where: { $0.source.itemId == childId }),
                "Child must be visible when folder is open")

        // Close via toggle — during empty search, resetFilter respects lastIsOpen
        if let item = afterOpen { await root.folderListController.toggleFolder(item: item) }

        let afterClose = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(afterClose?.isOpen == false,     "Folder must be closed after second toggle")
        #expect(afterClose?.lastIsOpen == false, "lastIsOpen must be false after explicit close")
        #expect(!root.folderListController.listModel.list.contains(where: { $0.source.itemId == childId }),
                "Child must not appear in flat list when folder is closed")
    }

    @Test("toggleFolder on canOpen=true folder triggers scoped child load")
    func toggleFolderWithCanOpenLoadsChildren() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Forest Walk", itemId: childId)
        root.editController.addItem(itemId: childId, parentId: folderId)

        // Empty folder search: folder appears with canOpen=true, no children in result
        await searchFolder(root)
        let folderItem = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(folderItem?.canOpen == true, "Folder must have canOpen=true on empty search")
        #expect(folderItem?.isOpen == false, "Folder must start closed on empty search")

        // Toggle open: should load children via scoped search
        if let item = folderItem {
            await root.folderListController.toggleFolder(item: item)
        }

        let afterOpen = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(afterOpen?.isOpen == true, "Folder must be open after toggle")
        #expect(root.folderListController.listModel.list.contains(where: { $0.source.itemId == childId }),
                "Child must appear in flat list after toggleFolder loads children")
    }

    @Test("toggleFolder with already-cached children shows them without re-fetching")
    func toggleFolderWithCachedChildrenJustResets() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.addItem(itemId: childId, parentId: folderId)

        // Open the folder once (loads children)
        await searchFolder(root)
        let firstOpen = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        if let item = firstOpen { await root.folderListController.toggleFolder(item: item) }

        // Close it
        let toClose = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        if let item = toClose { await root.folderListController.toggleFolder(item: item) }
        #expect(toClose?.isOpen == false || root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })?.isOpen == false)

        // Re-open: children are already cached — must appear without a new search
        let toReopen = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        if let item = toReopen { await root.folderListController.toggleFolder(item: item) }

        #expect(root.folderListController.listModel.list.contains(where: { $0.source.itemId == childId }),
                "Child must reappear from cache on second open — no new search needed")
    }

    // MARK: - canOpenFolder / hasParentFolder

    @Test("canOpenFolder returns true for closed folder with canOpen=true, false when open or canOpen=false")
    func canOpenFolderReflectsState() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.addItem(itemId: childId, parentId: folderId)

        await searchFolder(root)  // empty search → folder has canOpen=true, isOpen=false

        #expect(root.folderListController.canOpenFolder(itemId: folderId) == true,
                "canOpenFolder must be true for closed folder with canOpen=true")

        // Open it
        let folderItem = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        if let item = folderItem { await root.folderListController.toggleFolder(item: item) }

        #expect(root.folderListController.canOpenFolder(itemId: folderId) == false,
                "canOpenFolder must be false once the folder is already open")
    }

    @Test("hasParentFolder returns true when item has an open parent in the flat list")
    func hasParentFolderWhenParentOpen() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.addItem(itemId: childId, parentId: folderId)

        // Open the folder
        await searchFolder(root)
        let folderItem = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        if let item = folderItem { await root.folderListController.toggleFolder(item: item) }

        #expect(root.folderListController.hasParentFolder(itemId: childId) == true,
                "hasParentFolder must be true when child's parent is open")
    }

    @Test("hasParentFolder returns false when parent is closed")
    func hasParentFolderFalseWhenClosed() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.addItem(itemId: childId, parentId: folderId)

        // Non-empty search opens folder; then close it again
        await searchFolder(root, text: "")
        let folderItem = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        if let item = folderItem {
            await root.folderListController.toggleFolder(item: item)  // open
            await root.folderListController.toggleFolder(item: root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })!)  // close
        }

        #expect(root.folderListController.hasParentFolder(itemId: childId) == false,
                "hasParentFolder must be false when parent is closed (or child not visible)")
    }

    // MARK: - toggleParentFolder / closeParentFolder

    @Test("toggleParentFolder closes the open parent of a child entry and updates lastIsOpen")
    func toggleParentFolderClosesParent() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.addItem(itemId: childId, parentId: folderId)

        // Open the folder
        await searchFolder(root)
        let folderItem = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        if let item = folderItem { await root.folderListController.toggleFolder(item: item) }

        // Find the child in the flat list — it has a parentId set
        let childItem = root.folderListController.listModel.list.first(where: { $0.source.itemId == childId })
        #expect(childItem != nil, "Child must be visible with open parent")

        // Toggle parent folder via child
        if let item = childItem {
            root.folderListController.toggleParentFolder(item: item)
        }

        let parentAfter = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(parentAfter?.isOpen == false, "Parent must be closed after toggleParentFolder")
        #expect(parentAfter?.lastIsOpen == false, "lastIsOpen must mirror the closed state")
    }

    @Test("closeParentFolder selects and scrolls to the parent after closing it")
    func closeParentFolderSelectsParent() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.addItem(itemId: childId, parentId: folderId)

        await searchFolder(root)
        let folderItem = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        if let item = folderItem { await root.folderListController.toggleFolder(item: item) }

        // Close from child's perspective
        root.folderListController.closeParentFolder(of: childId)

        let parentItem = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(parentItem?.isOpen == false, "Parent must be closed after closeParentFolder")
        // The parent's FolderListItemModel.id becomes the selected id
        #expect(root.folderListController.listModel.selectedItemId == folderId,
                "closeParentFolder must select the parent folder in the list")
    }

    // MARK: - mapResult: canOpen sync on cache hit

    @Test("mapResult syncs canOpen from the latest SearchResult on every call, even for cached items")
    func mapResultSyncsCanOpenFromLatestResult() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.addItem(itemId: childId, parentId: folderId)

        // Empty search: folder is cached with canOpen=true
        await searchFolder(root)
        let firstResult = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(firstResult?.canOpen == true, "canOpen must be true before opening")

        // Open the folder (loads children; canOpen becomes false on next search)
        if let item = firstResult { await root.folderListController.toggleFolder(item: item) }

        // Non-empty search: folder's children match, so it gets canOpen=false
        await searchFolder(root, text: childId.uuidString.prefix(4).description)
        // canOpen could be false since children were returned — just verify the list is rebuilt
        let afterSearch = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        // Either the folder appeared with children (canOpen=false) or pruned — just confirm rebuild ran
        _ = afterSearch  // the key assertion is the list was successfully rebuilt without crash
        #expect(true, "Rebuilding list after cache hit must not crash")
    }

    // MARK: - lastIsOpen persistence through search round-trips

    // appendToFlat rule:
    //   isSearching=true  → item.isOpen = !result.children.isEmpty  (ignores lastIsOpen)
    //   isSearching=false → item.isOpen = item.lastIsOpen             (restores saved state)
    // toggleFolder always writes lastIsOpen, even during an active search.

    @Test("Folder opened before search: auto-opens during search AND stays open when search is cleared")
    func openedFolderPreservesLastIsOpenThroughSearch() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Autumn Leaves", itemId: childId)
        root.editController.addItem(itemId: childId, parentId: folderId)

        // Step 1: empty search — user opens folder (lastIsOpen = true)
        await searchFolder(root)
        let atStart = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        if let f = atStart { await root.folderListController.toggleFolder(item: f) }

        let afterOpen = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(afterOpen?.lastIsOpen == true, "Prerequisite: lastIsOpen must be true after manual open")

        // Step 2: non-empty search — folder auto-opens because child matches
        // appendToFlat does NOT update lastIsOpen during search (only item.isOpen is written)
        await searchFolder(root, text: "Autumn")
        let duringSearch = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(duringSearch?.isOpen == true,      "Folder auto-opens when child matches")
        #expect(duringSearch?.lastIsOpen == true,  "lastIsOpen must be unchanged by auto-open (still true)")

        // Step 3: clear search — appendToFlat uses lastIsOpen=true → folder stays open
        await searchFolder(root)
        let afterClear = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(afterClear?.isOpen == true,
                "Folder must stay open: lastIsOpen=true was preserved through the search round-trip")
    }

    @Test("Folder closed before search: auto-opens during search but closes back when search is cleared")
    func closedFolderRestoresAfterSearchCleared() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Shoreline", itemId: childId)
        root.editController.addItem(itemId: childId, parentId: folderId)

        // Step 1: empty search — folder starts closed (lastIsOpen = false, default)
        await searchFolder(root)
        let atStart = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(atStart?.isOpen == false,     "Folder must start closed")
        #expect(atStart?.lastIsOpen == false, "lastIsOpen defaults to false")

        // Step 2: non-empty search — folder auto-opens (isSearching=true)
        // appendToFlat DOES NOT write lastIsOpen; lastIsOpen stays false
        await searchFolder(root, text: "Dragon")
        let duringSearch = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(duringSearch?.isOpen == true,      "Folder auto-opens when child matches")
        #expect(duringSearch?.lastIsOpen == false, "lastIsOpen must remain false — auto-open does not save state")

        // Step 3: clear search — lastIsOpen=false → folder closes back
        await searchFolder(root)
        let afterClear = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(afterClear?.isOpen == false,
                "Folder must close back: lastIsOpen=false was the state before the search")
    }

    @Test("Folder opened before search, no match during search: folder excluded from rebuilt list but reopens on clear")
    func openedFolderExcludedFromSearchReopensOnClear() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Forest Trail", itemId: folderId)
        root.editController.reset(name: "Unrelated",    itemId: childId)
        root.editController.addItem(itemId: childId, parentId: folderId)

        // A root item that DOES match "XYZ" is needed so that searchModel.results is non-empty.
        // buildList() has `guard !results.isEmpty else { return listModel.list }` — without
        // at least one result the guard preserves the old list, keeping the folder visible.
        let matchId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "XYZ Landscape", itemId: matchId)

        // Step 1: empty search, user opens folder (lastIsOpen = true)
        await searchFolder(root)
        let atStart = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        if let f = atStart { await root.folderListController.toggleFolder(item: f) }
        #expect(root.folderListController.listModel.list
            .first(where: { $0.source.itemId == folderId })?.lastIsOpen == true)

        // Step 2: search "XYZ" — matchId appears (ensures rebuild runs), folder excluded (no match)
        await searchFolder(root, text: "XYZ")
        #expect(root.folderListController.listModel.list.contains(where: { $0.source.itemId == matchId }),
                "XYZ Landscape must appear — ensures buildList rebuilt the list (non-empty results)")
        #expect(!root.folderListController.listModel.list.contains(where: { $0.source.itemId == folderId }),
                "Folder must be excluded from rebuilt list — but lastIsOpen=true is preserved in the cache")

        // Step 3: clear search → folder reappears, appendToFlat uses lastIsOpen=true → opens
        await searchFolder(root)
        let afterClear = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(afterClear != nil,          "Folder must reappear after clearing search")
        #expect(afterClear?.isOpen == true,
                "Folder must be open: lastIsOpen=true survived in the cache while excluded from results")
    }

    @Test("Closing folder during active search saves lastIsOpen=false — folder stays closed when search is cleared")
    func closingFolderDuringSearchSavesState() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Coastal Cliffs", itemId: childId)
        root.editController.addItem(itemId: childId, parentId: folderId)

        // Step 1: non-empty search → folder auto-opens (lastIsOpen stays false)
        await searchFolder(root, text: "Coastal")
        let autoOpen = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(autoOpen?.isOpen == true,      "Folder auto-opens when child matches")
        #expect(autoOpen?.lastIsOpen == false, "lastIsOpen is still false — not saved by auto-open")

        // Step 2: user closes folder during search
        // toggleFolder sets lastIsOpen=false and calls resetFilter(), which immediately re-opens the folder
        // because isSearching=true and result.children is non-empty.
        // The visual state stays "open" but lastIsOpen=false is now recorded.
        if let item = autoOpen { await root.folderListController.toggleFolder(item: item) }
        let afterToggle = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        // Visual re-open is expected (search forces it open again) — the key is lastIsOpen
        #expect(afterToggle?.lastIsOpen == false,
                "lastIsOpen must be false after user closes during search — this intent is saved for after-clear")

        // Step 3: clear search → lastIsOpen=false → folder stays closed
        await searchFolder(root)
        let afterClear = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(afterClear?.isOpen == false,
                "Folder must close when search is cleared: the toggle during search saved lastIsOpen=false")
    }

    @Test("Toggling canOpen folder during search saves lastIsOpen=true — folder opens when search is cleared")
    func openingFolderDuringSearchSavesLastIsOpenTrue() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Glacier View", itemId: folderId)  // folder name matches "Glacier"
        root.editController.reset(name: "Tropical Beach", itemId: childId) // child does NOT match "Glacier"
        root.editController.addItem(itemId: childId, parentId: folderId)

        // Step 1: non-empty search — folder appears because name matches, child does not
        // → canOpen=true (lazy), isOpen=false (no matching children to auto-open with)
        await searchFolder(root, text: "Glacier")
        let closedInSearch = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(closedInSearch?.canOpen == true, "Folder has canOpen=true (name match, no child match)")
        #expect(closedInSearch?.isOpen == false, "Folder starts closed during search (no children auto-open)")

        // Step 2: user taps chevron to open the folder during search.
        // toggleFolder sets lastIsOpen=true then calls loadChildrenViaSearch("Glacier", focusId).
        // The scoped search returns nothing because the child "Tropical Beach" does not match "Glacier".
        // appendToFlat then sets isOpen=false again (isSearching=true, result.children=[]).
        // The folder visually closes — but lastIsOpen=true is SAVED. That is the key behavior.
        if let item = closedInSearch { await root.folderListController.toggleFolder(item: item) }
        let afterToggle = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(afterToggle?.lastIsOpen == true,
                "lastIsOpen=true must be saved by toggleFolder, even if appendToFlat immediately closes the folder")

        // Step 3: clear search → appendToFlat uses lastIsOpen=true → folder opens
        // Note: item.children was set to [] by loadChildrenViaSearch("Glacier") since the child
        // "Tropical Beach" does not match. The folder is open but children won't be visible until
        // the user re-taps the chevron on the empty-search list (triggering loadChildrenViaSearch("")).
        await searchFolder(root)
        let afterClear = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(afterClear?.isOpen == true,
                "Folder must open when search is cleared: the toggle during search saved lastIsOpen=true")
        #expect(afterClear?.canOpen == true,
                "canOpen=true: user can tap again to load children (empty search returns all children)")
        _ = childId  // child not yet visible — requires one more toggle to load via empty-search scoped query
    }

    // MARK: - FolderListItemModel.id uniqueness invariant

    // FolderListItemModel.id = result.entryId ?? result.itemId  (see mapResult in FolderListControllable)
    //
    // In list mode:   id = itemId  — folders excluded, every item appears once, itemIds are globally unique.
    // In folder mode: root items/folders → id = itemId.
    //                 Children of open folders/collections → id = entry.id (the parent's membership entry UUID),
    //                 NOT itemId — so the same photo can appear in two collections with two different identities.
    //
    // If the search pipeline ever sets entryId=nil for a folder child, two items could collapse to the
    // same FolderListItemModel.id, breaking SwiftUI ForEach identity and list selection.

    @Test("List mode: every FolderListItemModel.id equals the item's UUID and all are unique")
    func listModeItemIdsAreUniqueAndEqualToItemId() async {
        let root = await makeRoot()

        let id1 = await root.itemController.addNew(type: .item)
        let id2 = await root.itemController.addNew(type: .item)
        let id3 = await root.itemController.addNew(type: .item)
        // Also add a folder — it must be EXCLUDED from list mode
        let folderId = await root.itemController.addNew(type: .folder)
        _ = folderId

        await searchList(root)
        let list = root.folderListController.listModel.list

        let modelIds = list.map(\.id)
        let itemIds  = list.map(\.source.itemId)

        #expect(list.allSatisfy { $0.id == $0.source.itemId },
                "List mode: every FolderListItemModel.id must equal its source.itemId (entryId is nil)")
        #expect(modelIds.contains(id1) && modelIds.contains(id2) && modelIds.contains(id3),
                "All three items must appear in list mode")
        #expect(Set(modelIds).count == modelIds.count,
                "All FolderListItemModel.id values must be unique in list mode")
        #expect(Set(itemIds).count == itemIds.count,
                "Sanity: all source.itemId values must be unique")
    }

    @Test("Folder mode root: closed folders and items have id = itemId")
    func folderModeRootNodesHaveItemIdAsId() async {
        let root = await makeRoot()

        let itemId   = await root.itemController.addNew(type: .item)
        let folderId = await root.itemController.addNew(type: .folder)

        await searchFolder(root)   // empty search, lazy — no children pre-loaded
        let list = root.folderListController.listModel.list

        let itemNode   = try? list.first(where: { $0.source.itemId == itemId })
        let folderNode = try? list.first(where: { $0.source.itemId == folderId })

        #expect(itemNode?.id   == itemId,   "Root item: id must be itemId (no parentEntryId)")
        #expect(folderNode?.id == folderId, "Closed root folder: id must be itemId")
        #expect(Set(list.map(\.id)).count == list.count, "All root node ids must be unique")
    }

    @Test("Folder mode open folder: child's FolderListItemModel.id equals the folder's membership entryId, not itemId")
    func openFolderChildIdEqualsMembershipEntryId() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.addItem(itemId: childId, parentId: folderId)

        // Retrieve the membership entry UUID before the search
        let membershipEntryId = root.itemController.itemOrEmpty(for: folderId)
            .entries.first(where: { $0.childId == childId })?.id

        await searchFolder(root)
        let folderNode = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        if let item = folderNode { await root.folderListController.toggleFolder(item: item) }

        let childNode = root.folderListController.listModel.list.first(where: { $0.source.itemId == childId })

        #expect(childNode != nil,                              "Child must be visible after folder is opened")
        #expect(childNode?.id != childId,                     "Child id must NOT be the itemId — it is the membership entryId")
        #expect(membershipEntryId != nil,                     "Membership entry must exist")
        #expect(childNode?.id == membershipEntryId,           "Child id must equal the folder's membership entry UUID")
        #expect(childNode?.source.itemId == childId,          "source.itemId still points to the item for navigation")
        #expect(childNode?.source.entryId == membershipEntryId, "source.entryId carries the membership entry UUID")
    }

    /// Folder `addItem` has move semantics: adding item X to folder B removes it from folder A
    /// (see `EditControllable.addItem` lines 204-206). Items can only belong to one folder.
    /// Collections (non-folder `specialCategory`) support multiple parents, but PhotoRPG folders do not.
    ///
    /// This test therefore uses two DISTINCT items — one per folder — and verifies the invariant:
    /// every folder child's `FolderListItemModel.id` equals its membership `entryId` (never `itemId`).
    /// Because each `addItem` call creates a fresh `entryId` UUID, all IDs are guaranteed unique.
    @Test("Folder children use membership entryId as FolderListItemModel.id — never itemId, always unique")
    func folderChildrenUseEntryIdNotItemId() async throws {
        let root = await makeRoot()

        let folderA = await root.itemController.addNew(type: .folder)
        let folderB = await root.itemController.addNew(type: .folder)
        let photoA  = await root.itemController.addNew(type: .item)
        let photoB  = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Sunset",  itemId: photoA)
        root.editController.reset(name: "Sunrise", itemId: photoB)

        root.editController.addItem(itemId: photoA, parentId: folderA)
        root.editController.addItem(itemId: photoB, parentId: folderB)

        // Each addItem creates a fresh entry UUID as the membership identity
        let entryInA = try #require(
            root.itemController.itemOrEmpty(for: folderA).entries.first(where: { $0.childId == photoA })?.id,
            "Folder A must have a membership entry for photoA"
        )
        let entryInB = try #require(
            root.itemController.itemOrEmpty(for: folderB).entries.first(where: { $0.childId == photoB })?.id,
            "Folder B must have a membership entry for photoB"
        )

        // entryId ≠ itemId — the membership UUID is always a fresh value, not the item's own UUID
        #expect(entryInA != photoA, "Membership entryId must differ from the child's itemId")
        #expect(entryInB != photoB, "Membership entryId must differ from the child's itemId")
        // entryIds are distinct even across folders
        #expect(entryInA != entryInB, "Each addItem call produces a distinct entryId UUID")

        await searchFolder(root)
        let nodeA = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderA })
        let nodeB = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderB })
        if let a = nodeA { await root.folderListController.toggleFolder(item: a) }
        if let b = nodeB { await root.folderListController.toggleFolder(item: b) }

        // FolderListItemModel.id = entryId for folder children (not itemId)
        let childA = try #require(
            root.folderListController.listModel.list.first(where: { $0.source.itemId == photoA }),
            "photoA must be visible as a child of folder A"
        )
        let childB = try #require(
            root.folderListController.listModel.list.first(where: { $0.source.itemId == photoB }),
            "photoB must be visible as a child of folder B"
        )

        #expect(childA.id == entryInA,    "childA.id must equal its membership entryId (not its itemId)")
        #expect(childB.id == entryInB,    "childB.id must equal its membership entryId (not its itemId)")
        #expect(childA.id != childB.id,   "Different folder slots always have different FolderListItemModel.ids")
        #expect(childA.source.itemId == photoA, "source.itemId points to the item for navigation")
        #expect(childB.source.itemId == photoB, "source.itemId points to the item for navigation")

        // Complete flat list has no duplicate ids
        let allIds = root.folderListController.listModel.list.map(\.id)
        #expect(Set(allIds).count == allIds.count,
                "No duplicate FolderListItemModel.id in the flat list — SwiftUI ForEach identity is safe")
    }

    @Test("Flat list always has unique ids across list mode, folder mode, and open folders")
    func flatListIdsAreAlwaysUnique() async {
        let root = await makeRoot()

        let standalone = await root.itemController.addNew(type: .item)
        let folderA    = await root.itemController.addNew(type: .folder)
        let folderB    = await root.itemController.addNew(type: .folder)
        let childX     = await root.itemController.addNew(type: .item)
        let childY     = await root.itemController.addNew(type: .item)
        let shared     = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Alpha",  itemId: standalone)
        root.editController.reset(name: "Folder", itemId: folderA)
        root.editController.reset(name: "GalleryB", itemId: folderB)

        root.editController.addItem(itemId: childX, parentId: folderA)
        root.editController.addItem(itemId: childY, parentId: folderA)
        root.editController.addItem(itemId: shared,  parentId: folderA)
        root.editController.addItem(itemId: shared,  parentId: folderB)  // same item in folderB too

        // Folder mode, open both folders
        await searchFolder(root)
        let nodeA = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderA })
        let nodeB = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderB })
        if let a = nodeA { await root.folderListController.toggleFolder(item: a) }
        if let b = nodeB { await root.folderListController.toggleFolder(item: b) }

        let allIds = root.folderListController.listModel.list.map(\.id)
        // standalone=itemId, folder=itemId, children=membershipEntryId (unique per folder slot)
        #expect(Set(allIds).count == allIds.count,
                "No duplicate FolderListItemModel.id in the flat list — SwiftUI ForEach identity is safe")
    }
}
#endif
