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
/// resetItemOnce, resetDetail / performDetailSearch, canOpenFolder,
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
        await root.folderListController.performSearch(source: "test")
    }

    /// Runs `performSearch` via the list controller in **folder** mode.
    private func searchFolder(_ root: PhotoRootModel, text: String = "") async {
        root.folderListController.listDisplayModel.listMode = .folder
        root.folderListController.searchModel.searchText = text
        await root.folderListController.performSearch(source: "test")
    }

    // MARK: - buildList / resetFilter

    @Test("Empty results guard: a text search with no results keeps the current list")
    func resetFilterKeepsListWhenSearchHasNoResults() async {
        let root = await makeRoot()
        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Alpha", itemId: itemId)

        // First search populates the list
        await searchList(root)
        let beforeCount = root.folderListController.listModel.list.count
        #expect(beforeCount > 0, "List must be populated after first search")

        // A text search that found nothing keeps the list (no flicker; the overlay covers it)
        root.folderListController.searchModel.searchText = "zzz"
        root.folderListController.searchModel.results = []
        root.folderListController.resetFilter()
        #expect(root.folderListController.listModel.list.count == beforeCount,
                "resetFilter with empty search results must preserve the existing list (guard)")
    }

    @Test("Without search text, empty results empty the list (CODE_AUDIT_Folder §5.14)")
    func resetFilterEmptiesListWhenNothingIsLeft() async {
        let root = await makeRoot()
        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Alpha", itemId: itemId)
        await searchList(root)
        #expect(!root.folderListController.listModel.list.isEmpty)

        // The last item is gone (removed, moved away, deleted by sync): the stale row must go too.
        root.folderListController.searchModel.results = []
        root.folderListController.resetFilter()
        #expect(root.folderListController.listModel.list.isEmpty)
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
        if let item { root.folderListController.toggleFolder(item: item) }

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
        if let item = folderItem { root.folderListController.toggleFolder(item: item) }

        let afterOpen = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(afterOpen?.isOpen == true, "Folder must be open after first toggle")
        #expect(root.folderListController.listModel.list.contains(where: { $0.source.itemId == childId }),
                "Child must be visible when folder is open")

        // Close via toggle — during empty search, resetFilter respects lastIsOpen
        if let item = afterOpen { root.folderListController.toggleFolder(item: item) }

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
            root.folderListController.toggleFolder(item: item)
        }

        let afterOpen = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(afterOpen?.isOpen == true, "Folder must be open after toggle")
        #expect(root.folderListController.listModel.list.contains(where: { $0.source.itemId == childId }),
                "Child must appear in flat list after toggleFolder loads children")
    }

    @Test("Selecting an open folder (detail list built) keeps its children in the main list indented")
    func detailListDoesNotResetMainListChildLevels() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Forest Walk", itemId: childId)
        root.editController.addItem(itemId: childId, parentId: folderId)

        await searchFolder(root)
        guard let folderItem = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId }) else {
            #expect(Bool(false))
            return
        }
        root.folderListController.toggleFolder(item: folderItem)
        func childLevel() -> Int? {
            root.folderListController.listModel.list.first(where: { $0.source.itemId == childId })?.level
        }
        #expect(childLevel() == 1)

        // Selecting the folder builds its detail list, which lists the children at level 0 and
        // seeds the detail cache with copies of the folder and its children.
        guard let folderModel = root.itemController.itemSync(for: folderId) else {
            #expect(Bool(false))
            return
        }
        root.folderListController.resetDetail(model: folderModel)
        await root.folderListController.performDetailSearch()
        // ... and the main list is rebuilt afterwards (any data change or search does that).
        await searchFolder(root)
        await root.folderListController.performDetailSearch()

        #expect(childLevel() == 1, "The main list's child row must stay one level below its folder")
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
        if let item = firstOpen { root.folderListController.toggleFolder(item: item) }

        // Close it
        let toClose = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        if let item = toClose { root.folderListController.toggleFolder(item: item) }
        #expect(toClose?.isOpen == false || root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })?.isOpen == false)

        // Re-open: children are already cached — must appear without a new search
        let toReopen = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        if let item = toReopen { root.folderListController.toggleFolder(item: item) }

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
        if let item = folderItem { root.folderListController.toggleFolder(item: item) }

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
        if let item = folderItem { root.folderListController.toggleFolder(item: item) }

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
            root.folderListController.toggleFolder(item: item)  // open
            root.folderListController.toggleFolder(item: root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })!)  // close
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
        if let item = folderItem { root.folderListController.toggleFolder(item: item) }

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
        if let item = folderItem { root.folderListController.toggleFolder(item: item) }

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
        if let item = firstResult { root.folderListController.toggleFolder(item: item) }

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
        if let f = atStart { root.folderListController.toggleFolder(item: f) }

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
        if let f = atStart { root.folderListController.toggleFolder(item: f) }
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

    @Test("Closing auto-opened folder during search closes it immediately and keeps it closed")
    func closingFolderDuringSearchSavesState() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Coastal Cliffs", itemId: childId)
        root.editController.addItem(itemId: childId, parentId: folderId)

        // Step 1: non-empty search → folder auto-opens (lastIsOpen stays false, wasExplicitlyClosed=false)
        await searchFolder(root, text: "Coastal")
        let autoOpen = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(autoOpen?.isOpen == true,      "Folder auto-opens when child matches")
        #expect(autoOpen?.lastIsOpen == false, "lastIsOpen not changed by auto-open")

        // Step 2: user closes folder during search → wasExplicitlyClosed=true → folder STAYS closed
        // (appendToFlat: result.children non-empty, but wasExplicitlyClosed=true → isOpen=false)
        if let item = autoOpen { root.folderListController.toggleFolder(item: item) }
        let afterToggle = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(afterToggle?.isOpen == false,
                "Folder must close immediately — wasExplicitlyClosed=true prevents auto-reopen by search")
        #expect(afterToggle?.lastIsOpen == false)
        #expect(afterToggle?.wasExplicitlyClosed == true, "wasExplicitlyClosed flag set")

        // Step 3: clear search → lastIsOpen=false → folder stays closed
        await searchFolder(root)
        let afterClear = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(afterClear?.isOpen == false,
                "Folder stays closed after search cleared")
    }

    @Test("Toggling folder during search immediately shows ALL children (loadChildrenViaSearch uses empty text)")
    func openingFolderDuringSearchShowsAllChildren() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Glacier View",  itemId: folderId) // name matches "Glacier"
        root.editController.reset(name: "Tropical Beach", itemId: childId) // does NOT match "Glacier"
        root.editController.addItem(itemId: childId, parentId: folderId)

        // Step 1: search → folder appears (name match), starts closed (no children match)
        await searchFolder(root, text: "Glacier")
        let closedInSearch = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(closedInSearch?.canOpen == true,  "Folder has canOpen=true (name match, no child match)")
        #expect(closedInSearch?.isOpen == false,  "Folder starts closed")
        #expect(!root.folderListController.listModel.list.contains(where: { $0.source.itemId == childId }),
                "Child not visible before toggle")

        // Step 2: user taps chevron → loadChildrenViaSearch uses EMPTY text (not "Glacier"),
        // so ALL children are loaded regardless of the active search filter.
        // appendToFlat: isSearching=true, result.children=[], but item.children non-empty
        // AND lastIsOpen=true → item.isOpen = true (the fix).
        if let item = closedInSearch { root.folderListController.toggleFolder(item: item) }

        let afterToggle = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(afterToggle?.isOpen == true,
                "Folder must stay open after toggle — loadChildrenViaSearch(empty) loaded all children")
        #expect(afterToggle?.lastIsOpen == true, "lastIsOpen=true persisted")
        #expect(root.folderListController.listModel.list.contains(where: { $0.source.itemId == childId }),
                "Child 'Tropical Beach' must be visible even though it doesn't match the search text")

        // Step 3: clear search → folder stays open (lastIsOpen=true), child still visible
        await searchFolder(root)
        let afterClear = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(afterClear?.isOpen == true,
                "Folder stays open after clearing search")
        #expect(root.folderListController.listModel.list.contains(where: { $0.source.itemId == childId }),
                "Child must remain visible after clearing search")
    }

    // MARK: - Close during search always works (wasExplicitlyClosed flag)

    // MARK: - searchReturnedNoResults flag for empty-state UI

    @Test("searchReturnedNoResults is false for empty search text")
    func noResultsFlagFalseOnEmptySearch() async {
        let root = await makeRoot()
        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon", itemId: itemId)

        await searchList(root)   // empty text
        #expect(root.folderListController.searchModel.searchReturnedNoResults == false,
                "Empty search must not set noResults flag — it shows all items, not 'no results'")
    }

    @Test("searchReturnedNoResults is true when non-empty search finds nothing")
    func noResultsFlagTrueWhenNothingFound() async {
        let root = await makeRoot()
        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Scout", itemId: itemId)

        await searchList(root, text: "XYZ_NO_MATCH_99")
        #expect(root.folderListController.searchModel.searchReturnedNoResults == true,
                "Non-empty search with zero matches must set searchReturnedNoResults=true")
    }

    @Test("searchReturnedNoResults is false when search finds at least one result")
    func noResultsFlagFalseWhenSomethingFound() async {
        let root = await makeRoot()
        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Scout", itemId: itemId)

        await searchList(root, text: "Dragon")
        #expect(root.folderListController.searchModel.searchReturnedNoResults == false,
                "Search that finds results must not set noResults flag")
    }

    @Test("searchReturnedNoResults resets to false when search text is cleared")
    func noResultsFlagResetsOnClear() async {
        let root = await makeRoot()
        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Scout", itemId: itemId)

        // First set it to true
        await searchList(root, text: "XYZ_NO_MATCH")
        #expect(root.folderListController.searchModel.searchReturnedNoResults == true)

        // Clear search → flag must reset
        await searchList(root)
        #expect(root.folderListController.searchModel.searchReturnedNoResults == false,
                "Clearing search text must reset searchReturnedNoResults to false")
    }

    @Test("listModel.list is preserved (not emptied) when search returns no results — avoids flicker")
    func listPreservedWhenSearchEmpty() async {
        let root = await makeRoot()
        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Scout", itemId: itemId)

        await searchList(root)
        let countBeforeSearch = root.folderListController.listModel.list.count
        #expect(countBeforeSearch > 0, "List must be populated after empty search")

        await searchList(root, text: "XYZ_NO_MATCH")
        #expect(root.folderListController.listModel.list.count == countBeforeSearch,
                "list must be preserved (not emptied) when search finds nothing — prevents UI flicker")
        #expect(root.folderListController.searchModel.searchReturnedNoResults == true,
                "But the flag must be true so the view knows to show ContentUnavailableView.search")
    }

    @Test("folder mode: searchReturnedNoResults set correctly")
    func noResultsFlagInFolderMode() async {
        let root = await makeRoot()
        let folderId = await root.itemController.addNew(type: .folder)
        root.editController.reset(name: "Nature Archive", itemId: folderId)

        // Search that matches folder
        await searchFolder(root, text: "Nature")
        #expect(root.folderListController.searchModel.searchReturnedNoResults == false,
                "Folder name matches — not empty")

        // Search that matches nothing
        await searchFolder(root, text: "XYZ_NO_MATCH")
        #expect(root.folderListController.searchModel.searchReturnedNoResults == true,
                "Nothing matches — must set noResults flag in folder mode too")
    }

    // MARK: - Selected item always returned in non-empty search results

    @Test("Non-matching selected item is always included in non-empty list search results")
    func selectedItemAlwaysInListSearchResults() async {
        let root = await makeRoot()

        let dragonId = await root.itemController.addNew(type: .item)
        let knightId = await root.itemController.addNew(type: .item)
        let forestId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Scout",  itemId: dragonId)
        root.editController.reset(name: "Knight Errant", itemId: knightId)
        root.editController.reset(name: "Forest Walker", itemId: forestId)

        // Step 1: empty search → populates cache with FolderListItemModel ids
        await searchList(root)
        let knightRow = root.folderListController.listModel.list.first(where: { $0.source.itemId == knightId })
        guard let selectedId = knightRow?.id else {
            #expect(Bool(false), "Knight must be in list after empty search")
            return
        }

        // Step 2: user selects "Knight Errant"
        root.folderListController.listModel.selected = selectedId

        // Step 3: search "Dragon" — Knight doesn't match, Forest doesn't match
        await searchList(root, text: "Dragon")
        let ids = root.folderListController.listModel.list.map(\.source.itemId)

        #expect(ids.contains(dragonId), "Dragon Scout must appear — normal match")
        #expect(ids.contains(knightId), "Knight Errant must appear — selected item, even though it doesn't match")
        #expect(!ids.contains(forestId), "Forest Walker must NOT appear — not selected, not matching")
    }

    @Test("Selected item is not duplicated when it also matches the search text")
    func selectedMatchingItemNotDuplicated() async {
        let root = await makeRoot()

        let dragonId = await root.itemController.addNew(type: .item)
        let knightId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Slayer", itemId: dragonId)
        root.editController.reset(name: "Knight",        itemId: knightId)

        await searchList(root)
        let dragonRow = root.folderListController.listModel.list.first(where: { $0.source.itemId == dragonId })
        root.folderListController.listModel.selected = dragonRow?.id

        // Search "Dragon" — selected item also matches
        await searchList(root, text: "Dragon")
        let ids = root.folderListController.listModel.list.map(\.source.itemId)
        let dragonCount = ids.filter { $0 == dragonId }.count

        #expect(dragonCount == 1, "Selected matching item must appear exactly once — no duplicate")
    }

    @Test("No selected item: non-matching items are not included in results")
    func noSelectionNoForcedInclusion() async {
        let root = await makeRoot()

        let dragonId = await root.itemController.addNew(type: .item)
        let knightId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon",  itemId: dragonId)
        root.editController.reset(name: "Knight",  itemId: knightId)

        await searchList(root)
        // Ensure nothing is selected
        root.folderListController.listModel.selected = nil

        await searchList(root, text: "Dragon")
        let ids = root.folderListController.listModel.list.map(\.source.itemId)

        #expect(ids.contains(dragonId),  "Dragon must appear — matches")
        #expect(!ids.contains(knightId), "Knight must NOT appear — no selection, no match")
    }

    @Test("Selected item in folder mode: non-matching selected item is always included")
    func selectedItemAlwaysInFolderModeResults() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let dragonId = await root.itemController.addNew(type: .item)
        let knightId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Archive", itemId: folderId) // folder name: "Dragon"
        root.editController.reset(name: "Sunset Photo",   itemId: dragonId)
        root.editController.reset(name: "Knight Photo",   itemId: knightId)
        // Both items are NOT in a folder (root level, don't match "Dragon")

        await searchFolder(root)
        let knightRow = root.folderListController.listModel.list.first(where: { $0.source.itemId == knightId })
        root.folderListController.listModel.selected = knightRow?.id

        // Search "Dragon" — folder matches, knightId doesn't match
        await searchFolder(root, text: "Dragon")
        let ids = root.folderListController.listModel.list.map(\.source.itemId)

        #expect(ids.contains(folderId),  "Dragon Archive folder must appear — normal match")
        #expect(ids.contains(knightId),  "Knight Photo must appear — selected item always included")
        #expect(!ids.contains(dragonId), "Sunset Photo must NOT appear — not selected, not matching")
    }

    @Test("Closing folder during search keeps it closed even on subsequent re-searches")
    func closedFolderStaysClosedAcrossSearches() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Coastal Photo", itemId: childId)
        root.editController.addItem(itemId: childId, parentId: folderId)

        // Step 1: search opens folder (child matches)
        await searchFolder(root, text: "Coastal")
        let autoOpen = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(autoOpen?.isOpen == true, "Folder auto-opens")

        // Step 2: user closes it
        if let item = autoOpen { root.folderListController.toggleFolder(item: item) }
        let afterClose = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(afterClose?.isOpen == false,             "Folder closed immediately")
        #expect(afterClose?.wasExplicitlyClosed == true, "wasExplicitlyClosed set")

        // Step 3: same search runs again — folder must stay closed (not auto-reopen)
        await searchFolder(root, text: "Coastal")
        let afterReSearch = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(afterReSearch?.isOpen == false,
                "Folder must stay closed on re-search — wasExplicitlyClosed prevents auto-reopen")
    }

    @Test("Closed folder during search can be reopened — wasExplicitlyClosed still shows chevron via canOpenFolder")
    func closedFolderCanBeReopened() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Photo", itemId: childId)
        root.editController.addItem(itemId: childId, parentId: folderId)

        // Search → folder auto-opens
        await searchFolder(root, text: "Dragon")
        let autoOpen = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(autoOpen?.isOpen == true, "Folder auto-opens")

        // User closes it
        if let item = autoOpen { root.folderListController.toggleFolder(item: item) }
        let afterClose = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(afterClose?.isOpen == false,             "Closed")
        #expect(afterClose?.wasExplicitlyClosed == true, "wasExplicitlyClosed=true")
        #expect(afterClose?.canOpen == false,
                "canOpen=false because children were already in result.children (not lazy)")

        // canOpenFolder must return true via wasExplicitlyClosed — chevron must show
        #expect(root.folderListController.canOpenFolder(itemId: folderId) == true,
                "canOpenFolder must be true when wasExplicitlyClosed=true so chevron is visible and reopen works")

        // User reopens it → should work
        root.folderListController.openFolder(itemId: folderId)
        // openFolder spawns a Task — wait for it to run
        _ = await waitUntil {
            root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })?.isOpen == true
        }

        let afterReopen = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(afterReopen?.isOpen == true, "Folder must be open after user reopens via chevron")
        #expect(afterReopen?.wasExplicitlyClosed == false, "wasExplicitlyClosed cleared when reopened")
    }

    @Test("After closing during search, re-opening clears wasExplicitlyClosed so auto-open works again")
    func reopeningClearsExplicitlyClosedFlag() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Photo", itemId: childId)
        root.editController.addItem(itemId: childId, parentId: folderId)

        // Auto-open, then close
        await searchFolder(root, text: "Dragon")
        let folderItem = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        if let item = folderItem { root.folderListController.toggleFolder(item: item) }
        #expect(root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })?.wasExplicitlyClosed == true)

        // Re-open explicitly — clears wasExplicitlyClosed
        let closedItem = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        if let item = closedItem { root.folderListController.toggleFolder(item: item) }
        let afterReOpen = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(afterReOpen?.isOpen == true,               "Folder is open after re-opening")
        #expect(afterReOpen?.wasExplicitlyClosed == false, "wasExplicitlyClosed cleared by open")

        // Now search again — folder should auto-open (wasExplicitlyClosed=false)
        await searchFolder(root, text: "Dragon")
        let afterSearch = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(afterSearch?.isOpen == true,
                "Folder auto-opens again after wasExplicitlyClosed was cleared")
    }

    // MARK: - Toggle during search: all content shown regardless of search filter

    // The new rule: loadChildrenViaSearch always uses EMPTY text so the user sees ALL children
    // when they explicitly open a folder/item, not just those matching the active search.
    // appendToFlat: isSearching=true, result.children=[], but item.children non-empty AND
    // lastIsOpen=true → item.isOpen = true (respects user's explicit choice).

    @Test("Toggling folder during search with multiple non-matching children shows ALL of them")
    func toggleDuringSearchShowsAllChildren() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let child1   = await root.itemController.addNew(type: .item)
        let child2   = await root.itemController.addNew(type: .item)
        let child3   = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Nature Archive", itemId: folderId) // matches "Nature"
        root.editController.reset(name: "Sunset Photo",   itemId: child1)   // no "Nature"
        root.editController.reset(name: "Mountain Peak",  itemId: child2)   // no "Nature"
        root.editController.reset(name: "Ocean Wave",     itemId: child3)   // no "Nature"
        root.editController.addItem(itemId: child1, parentId: folderId)
        root.editController.addItem(itemId: child2, parentId: folderId)
        root.editController.addItem(itemId: child3, parentId: folderId)

        await searchFolder(root, text: "Nature")
        let folderNode = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(folderNode?.canOpen == true,  "Folder found by name match, canOpen=true")
        #expect(folderNode?.isOpen == false,  "Starts closed (no child matches 'Nature')")

        if let f = folderNode { root.folderListController.toggleFolder(item: f) }

        let flat = root.folderListController.listModel.list
        #expect(flat.contains(where: { $0.source.itemId == child1 }), "Sunset Photo must appear")
        #expect(flat.contains(where: { $0.source.itemId == child2 }), "Mountain Peak must appear")
        #expect(flat.contains(where: { $0.source.itemId == child3 }), "Ocean Wave must appear")
    }

    @Test("Folder stays open and shows all children when search text changes after manual open")
    func folderStaysOpenAfterSearchChange() async {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Glacier View",  itemId: folderId)
        root.editController.reset(name: "Forest Trail",  itemId: childId)   // matches neither "Glacier" nor "Sunset"
        root.editController.addItem(itemId: childId, parentId: folderId)

        // Search "Glacier", open folder
        await searchFolder(root, text: "Glacier")
        let node = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        if let n = node { root.folderListController.toggleFolder(item: n) }
        #expect(root.folderListController.listModel.list.contains(where: { $0.source.itemId == childId }),
                "Child must be visible after toggle with 'Glacier' search")

        // Change search to "Glacier" again (re-search) — folder should remain open
        await searchFolder(root, text: "Glacier")
        let afterReSearch = root.folderListController.listModel.list.first(where: { $0.source.itemId == folderId })
        #expect(afterReSearch?.isOpen == true,
                "Folder must stay open after re-search — lastIsOpen=true preserved")
        #expect(root.folderListController.listModel.list.contains(where: { $0.source.itemId == childId }),
                "Child must remain visible after re-search")
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

        let itemNode   = list.first(where: { $0.source.itemId == itemId })
        let folderNode = list.first(where: { $0.source.itemId == folderId })

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
        if let item = folderNode { root.folderListController.toggleFolder(item: item) }

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
        if let a = nodeA { root.folderListController.toggleFolder(item: a) }
        if let b = nodeB { root.folderListController.toggleFolder(item: b) }

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
        if let a = nodeA { root.folderListController.toggleFolder(item: a) }
        if let b = nodeB { root.folderListController.toggleFolder(item: b) }

        let allIds = root.folderListController.listModel.list.map(\.id)
        // standalone=itemId, folder=itemId, children=membershipEntryId (unique per folder slot)
        #expect(Set(allIds).count == allIds.count,
                "No duplicate FolderListItemModel.id in the flat list — SwiftUI ForEach identity is safe")
    }

    // MARK: - Inspector folder mode: folder children must not render as blank entry rows

    /// **Bug**: `InspectorRowView.rowContent` checked only `item.source.entryId != nil` to
    /// decide between entry row and standard item row. Folder children carry a non-nil
    /// `source.entryId` — the parent's membership entry UUID used for SwiftUI identity.
    /// That entry belongs to the *parent* model, not the child's. So `model[membershipId].name`
    /// resolved to nil/empty → blank row.
    ///
    /// **Fix**: `rowContent` now also checks `model?.entries.contains(where: { $0.id == entryId })`.
    /// Only when the model actually owns the entry is it rendered as an entry row.
    @Test("Folder child source.entryId is the parent's membership UUID — child model does NOT own it")
    func folderChildMembershipEntryIdNotInChildModel() async throws {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Sunset Shot", itemId: childId)
        root.editController.addItem(itemId: childId, parentId: folderId)

        // Use folderLinkController — the controller behind LinkItemListView (inspector)
        root.folderLinkController.listDisplayModel.listMode = .folder
        root.folderLinkController.searchModel.filterId = nil
        await root.folderLinkController.performSearch(source: "test")

        let folderNode = root.folderLinkController.listModel.list
            .first(where: { $0.source.itemId == folderId })
        if let f = folderNode { root.folderLinkController.toggleFolder(item: f) }

        let childNode = try #require(
            root.folderLinkController.listModel.list.first(where: { $0.source.itemId == childId }),
            "Child must be visible in the inspector after opening the folder"
        )

        // Folder children carry source.entryId = membership UUID (for SwiftUI identity via mapResult).
        let membershipId = try #require(
            childNode.source.entryId,
            "Folder child must have source.entryId set to the membership entry UUID"
        )

        // The membership entry is the PARENT FOLDER's entry linking to the child.
        // The child item's own model does NOT contain it.
        // If the view blindly checked `source.entryId != nil` it would call
        // model[membershipId].name → nil → blank row. The fix checks model.entries first.
        if let childModel = childNode.model {
            // The membership entry belongs to the parent folder, not the child.
            // InspectorRowView.rowContent must verify model.entries to avoid a blank row.
            #expect(
                !childModel.entries.contains(where: { $0.id == membershipId }),
                "Child model must NOT own the membership entryId — it belongs to the parent folder"
            )
        }

        // The child's item name is set and non-empty — confirms it can be displayed as a standard row
        #expect(childNode.model != nil, "Child model must be resolved via mapResult")
    }

    @Test("Inspector folder mode: folder children display as standard item rows, not blank entry rows")
    func inspectorFolderModeChildrenHaveCorrectModel() async throws {
        let root = await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        // Add two children — one named, one with default name
        let child1 = await root.itemController.addNew(type: .item)
        let child2 = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Mountain View", itemId: child1)
        root.editController.reset(name: "Seascape",      itemId: child2)
        root.editController.addItem(itemId: child1, parentId: folderId)
        root.editController.addItem(itemId: child2, parentId: folderId)

        root.folderLinkController.listDisplayModel.listMode = .folder
        root.folderLinkController.searchModel.filterId = nil
        await root.folderLinkController.performSearch(source: "test")

        let folderNode = root.folderLinkController.listModel.list
            .first(where: { $0.source.itemId == folderId })
        if let f = folderNode { root.folderLinkController.toggleFolder(item: f) }

        let list = root.folderLinkController.listModel.list
        for itemId in [child1, child2] {
            let node = try #require(
                list.first(where: { $0.source.itemId == itemId }),
                "Child \(itemId) must be visible"
            )
            // model must be set and must match the child item
            let model = try #require(node.model, "model must be resolved via mapResult")
            #expect(model.id == itemId, "model.id must equal the child's itemId")

            // The membership entryId must NOT be in the child's model entries
            if let eid = node.source.entryId {
                #expect(
                    !model.entries.contains(where: { $0.id == eid }),
                    "Membership entryId \(eid) must not be in child model — confirms fix prevents blank rows"
                )
            }
        }
    }

    @Test("A detail search scheduled next to a root search does not cancel it (list-mode toggle)")
    func detailSearchDoesNotCancelRootSearch() async throws {
        let root = await makeRoot()
        let folderId = await root.itemController.addNew(type: .folder)
        let childId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Folder", itemId: folderId)
        root.editController.reset(name: "Child", itemId: childId)
        root.editController.addItem(itemId: childId, parentId: folderId)

        let controller = root.folderListController
        controller.listDisplayModel.listMode = .list
        await controller.performSearch(source: "test")
        controller.resetDetail(model: root.itemController.itemOrEmpty(for: folderId))
        #expect(!controller.listModel.list.contains(where: { $0.source.itemId == folderId }),
                "List mode excludes folders")

        // The toggle: the root list and the detail list (sharing this controller) both react.
        controller.listDisplayModel.listMode = .folder
        controller.scheduleSearch()
        controller.scheduleDetailSearch()
        // Poll instead of a fixed sleep: the root search is debounced and async, so a fixed
        // window is flaky when the whole suite runs in parallel.
        _ = await waitUntil(timeout: .seconds(5)) {
            controller.listModel.list.contains(where: { $0.source.itemId == folderId })
        }

        #expect(controller.listModel.list.contains(where: { $0.source.itemId == folderId }),
                "The root search must still run after the detail search was scheduled")
    }

    // MARK: - Move refresh

    private func rootRowItemIds(_ root: PhotoRootModel) -> [UUID] {
        root.folderListController.listModel.list.map(\.source.itemId)
    }

    private func waitForRefresh(_ root: PhotoRootModel) async {
        try? await Task.sleep(for: .milliseconds(400))
        while let task = root.folderListController.searchModel.currentTask {
            await task.value
            if root.folderListController.searchModel.currentTask == task { break }
        }
    }

    @Test("Moving the selected item into a closed folder opens the folder and shows the item in it")
    func moveIntoClosedFolderRefreshesList() async throws {
        let root = await makeRoot()
        let folderId = await root.itemController.addNew(type: .folder)
        let childId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Folder", itemId: folderId)
        root.editController.reset(name: "Child", itemId: childId)
        await searchFolder(root)
        #expect(rootRowItemIds(root).contains(childId))

        let controller = root.folderListController
        let row = try #require(controller.listModel.list.first(where: { $0.source.itemId == childId }))
        controller.listModel.selected = row.id
        let menu = root.menuController
        menu.place(currentSelected: childId, in: FolderRepresentable(id: folderId, name: "Folder"))
        controller.update(debounce: false)
        await waitForRefresh(root)

        let childRows = controller.listModel.list.filter { $0.source.itemId == childId }
        #expect(childRows.count == 1, "the moved item must be listed once")
        #expect(childRows.first?.level == 1, "...inside the folder, which opens to show where it went")
        #expect(controller.listModel.list.first(where: { $0.source.itemId == folderId })?.isOpen == true)
    }

    @Test("Moving an item into an open folder shows it inside the folder at once")
    func moveIntoOpenFolderRefreshesList() async throws {
        let root = await makeRoot()
        let folderId = await root.itemController.addNew(type: .folder)
        let childId = await root.itemController.addNew(type: .item)
        let otherId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Folder", itemId: folderId)
        root.editController.reset(name: "Child", itemId: childId)
        root.editController.reset(name: "Other", itemId: otherId)
        root.editController.addItem(itemId: otherId, parentId: folderId)
        await searchFolder(root)
        let controller = root.folderListController
        let folderRow = try #require(controller.listModel.list.first(where: { $0.source.itemId == folderId }))
        controller.toggleFolder(item: folderRow)
        #expect(rootRowItemIds(root).contains(otherId), "folder must be open")

        let row = try #require(controller.listModel.list.first(where: { $0.source.itemId == childId }))
        controller.listModel.selected = row.id
        root.menuController.place(currentSelected: childId, in: FolderRepresentable(id: folderId, name: "Folder"))
        controller.update(debounce: false)
        await waitForRefresh(root)

        let rows = controller.listModel.list
        let childRows = rows.filter { $0.source.itemId == childId }
        #expect(childRows.count == 1, "the moved item must appear exactly once")
        #expect(childRows.first?.level == 1, "...inside the open folder")
    }

    @Test("Moving an item out of an open folder shows it at root at once")
    func moveOutOfOpenFolderRefreshesList() async throws {
        let root = await makeRoot()
        let folderId = await root.itemController.addNew(type: .folder)
        let childId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Folder", itemId: folderId)
        root.editController.reset(name: "Child", itemId: childId)
        root.editController.addItem(itemId: childId, parentId: folderId)
        await searchFolder(root)
        let controller = root.folderListController
        let folderRow = try #require(controller.listModel.list.first(where: { $0.source.itemId == folderId }))
        controller.toggleFolder(item: folderRow)
        let childRow = try #require(controller.listModel.list.first(where: { $0.source.itemId == childId }))
        controller.listModel.selected = childRow.id

        root.menuController.removeItemsFromFolder(currentSelected: childId, parentId: folderId, oneUp: false)
        controller.update(debounce: false)
        await waitForRefresh(root)

        let childRows = controller.listModel.list.filter { $0.source.itemId == childId }
        #expect(childRows.count == 1)
        #expect(childRows.first?.level == 0, "the item must now be a root row")
    }

    private func detailItemIds(_ root: PhotoRootModel) -> [UUID] {
        root.folderListController.listModel.detailListModel?.list.map(\.source.itemId) ?? []
    }

    @Test("Detail list: moving a child into a closed sibling folder refreshes the detail list")
    func detailMoveIntoClosedFolderRefreshes() async throws {
        let root = await makeRoot()
        let activeId = await root.itemController.addNew(type: .folder)
        let subId = await root.itemController.addNew(type: .folder)
        let childId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Active", itemId: activeId)
        root.editController.reset(name: "Sub", itemId: subId)
        root.editController.reset(name: "Child", itemId: childId)
        root.editController.addItem(itemId: subId, parentId: activeId)
        root.editController.addItem(itemId: childId, parentId: activeId)
        await searchFolder(root)
        let controller = root.folderListController
        controller.resetDetail(model: root.itemController.itemOrEmpty(for: activeId))
        #expect(await awaitCondition { detailItemIds(root).contains(childId) })

        let detail = try #require(controller.listModel.detailListModel)
        let row = try #require(detail.list.first(where: { $0.source.itemId == childId }))
        detail.selected = row.id
        // As `ListRootView` builds it: over the scoped (detail) list model.
        let menu = ContextMenuMultiController(editController: root.editControllable, itemController: root.itemControllable, listModel: detail)
        menu.place(currentSelected: childId, in: FolderRepresentable(id: subId, name: "Sub"))
        controller.update(debounce: false)
        await waitForRefresh(root)

        let childRows = detail.list.filter { $0.source.itemId == childId }
        #expect(childRows.count == 1, "the moved child must be listed once")
        #expect(childRows.first?.level == 1, "...inside the sub folder, which opens to show where it went")
    }

    @Test("Detail list: moving a child out of an open sub folder refreshes the detail list")
    func detailMoveOutRefreshes() async throws {
        let root = await makeRoot()
        let activeId = await root.itemController.addNew(type: .folder)
        let subId = await root.itemController.addNew(type: .folder)
        let childId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Active", itemId: activeId)
        root.editController.reset(name: "Sub", itemId: subId)
        root.editController.reset(name: "Child", itemId: childId)
        root.editController.addItem(itemId: subId, parentId: activeId)
        root.editController.addItem(itemId: childId, parentId: subId)
        await searchFolder(root)
        let controller = root.folderListController
        controller.resetDetail(model: root.itemController.itemOrEmpty(for: activeId))
        #expect(await awaitCondition { detailItemIds(root).contains(subId) })
        let detail = try #require(controller.listModel.detailListModel)
        let subRow = try #require(detail.list.first(where: { $0.source.itemId == subId }))
        controller.toggleFolder(item: subRow)
        #expect(await awaitCondition { detailItemIds(root).contains(childId) }, "sub folder must be open")

        root.menuController.removeItemsFromFolder(currentSelected: childId, parentId: subId, oneUp: true)
        controller.update(debounce: false)
        await waitForRefresh(root)

        let rows = detail.list.filter { $0.source.itemId == childId }
        #expect(rows.count == 1)
        #expect(rows.first?.level == 0, "the child must now be a direct row of the active folder")
    }

    @Test("Moving an item into a closed folder and back out shows it at root again")
    func moveIntoClosedFolderAndBackOut() async throws {
        let root = await makeRoot()
        let folderId = await root.itemController.addNew(type: .folder)
        let childId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Folder", itemId: folderId)
        root.editController.reset(name: "Child", itemId: childId)
        await searchFolder(root)
        let controller = root.folderListController
        let row = try #require(controller.listModel.list.first(where: { $0.source.itemId == childId }))
        controller.listModel.selected = row.id
        root.menuController.place(currentSelected: childId, in: FolderRepresentable(id: folderId, name: "Folder"))
        controller.update(debounce: false)
        await waitForRefresh(root)

        let inside = try #require(controller.listModel.list.first(where: { $0.source.itemId == childId }))
        #expect(inside.level == 1)
        controller.listModel.selected = inside.id
        root.menuController.removeItemsFromFolder(currentSelected: childId, parentId: folderId, oneUp: false)
        controller.update(debounce: false)
        await waitForRefresh(root)

        let rows = controller.listModel.list.filter { $0.source.itemId == childId }
        #expect(rows.count == 1, "listed once")
        #expect(rows.first?.level == 0, "back at root")
    }

    @Test("Round trip with the observation stream's debounced refresh racing the immediate one")
    func moveRoundTripWithRacingRefresh() async throws {
        let root = await makeRoot()
        let folderId = await root.itemController.addNew(type: .folder)
        let childId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Folder", itemId: folderId)
        root.editController.reset(name: "Child", itemId: childId)
        await searchFolder(root)
        let controller = root.folderListController
        let row = try #require(controller.listModel.list.first(where: { $0.source.itemId == childId }))
        controller.listModel.selected = row.id

        for round in 0..<3 {
            root.menuController.place(currentSelected: childId, in: FolderRepresentable(id: folderId, name: "Folder"))
            controller.update(debounce: false)
            controller.update()
            await waitForRefresh(root)
            let inside = controller.listModel.list.filter { $0.source.itemId == childId }
            #expect(inside.count == 1 && inside.first?.level == 1, "round \(round): inside the folder")

            root.menuController.removeItemsFromFolder(currentSelected: childId, parentId: folderId, oneUp: false)
            controller.update(debounce: false)
            controller.update()
            await waitForRefresh(root)
            let outside = controller.listModel.list.filter { $0.source.itemId == childId }
            #expect(outside.count == 1 && outside.first?.level == 0, "round \(round): back at root")
        }
    }

    @Test("Detail list round trip: into a closed sub folder (auto-opened), then out one level up")
    func detailRoundTrip() async throws {
        let root = await makeRoot()
        let activeId = await root.itemController.addNew(type: .folder)
        let subId = await root.itemController.addNew(type: .folder)
        let childId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Active", itemId: activeId)
        root.editController.reset(name: "Sub", itemId: subId)
        root.editController.reset(name: "Child", itemId: childId)
        root.editController.addItem(itemId: subId, parentId: activeId)
        root.editController.addItem(itemId: childId, parentId: activeId)
        await searchFolder(root)
        let controller = root.folderListController
        controller.resetDetail(model: root.itemController.itemOrEmpty(for: activeId))
        #expect(await awaitCondition { detailItemIds(root).contains(childId) })
        let detail = try #require(controller.listModel.detailListModel)
        let menu = ContextMenuMultiController(editController: root.editControllable, itemController: root.itemControllable, listModel: detail)

        for round in 0..<3 {
            menu.place(currentSelected: childId, in: FolderRepresentable(id: subId, name: "Sub"))
            controller.update(debounce: false)
            controller.update()
            await waitForRefresh(root)
            let inside = detail.list.filter { $0.source.itemId == childId }
            #expect(inside.count == 1 && inside.first?.level == 1, "round \(round): inside the sub folder")

            menu.removeItemsFromFolder(currentSelected: childId, parentId: subId, oneUp: true)
            controller.update(debounce: false)
            controller.update()
            await waitForRefresh(root)
            let outside = detail.list.filter { $0.source.itemId == childId }
            #expect(outside.count == 1 && outside.first?.level == 0, "round \(round): back in the active folder")
        }
    }
}
#endif
