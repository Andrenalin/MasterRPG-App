// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import CoreGraphics
import Foundation
import RPGResourcesDebug
import Testing

@testable import CoreRPG
@testable import PdfRPG

/// Regression tests for two inspector toggle bugs:
///
/// **Bug 1 — Circular parent/child reference (crash)**
/// `SearchLinkController.results(text:, focusId:)` used to call `inspectorScopedListResults` for
/// non-`specialCategory` items, which returned the item itself (not its entries).
/// `loadChildrenViaSearch` stored the item as its own child (`item.children = [item]`).
/// `flattenCachedChildren` then recursed infinitely → crash.
///
/// Fix: `loadChildrenViaSearch` now routes through the synchronous `syncExpandResults`, whose
/// non-folder branch is structurally guaranteed to return flat entry results (`entryId` always
/// set, never the item itself) — see the `toggleFolder*` tests below. `results(text:, focusId:)`
/// and its `inspectorEntryResults` helper (the original fix's home) were later found to have no
/// production callers — `loadChildrenViaSearch` had already migrated to `syncExpandResults` — and
/// were removed as dead code; this regression's coverage now lives entirely on the current path.
///
/// **Bug 2 — `performDetailSearch` lost scope in list mode**
/// `performDetailSearch` was changed to use `results(text:)` with `filterId`.
/// `SearchListController.results(text:)` only passes `filterId` as `focusId` when
/// `listMode == .folder`; in list mode it passed `nil` → returned all items (unscoped).
///
/// Fix: `performDetailSearch` now uses `scopedResults(text:, focusId:)` which always
/// passes the focusId regardless of listMode.
@MainActor
struct InspectorToggleBugFixTests {

    // MARK: - Helpers

    private func makeRoot() async -> PdfRootModel {
        let root = PdfRootModel.testRoot()
        await root.itemController.resetData()
        return root
    }

    private func addEntry(to itemId: UUID, name: String, content: String,
                          root: PdfRootModel) -> UUID {
        let id = UUID()
        root.itemController.itemOrEmpty(for: itemId).entries.append(
            PdfEntryModel(id: id, name: name, content: content, pageNumber: "1", bounds: .zero)
        )
        return id
    }

    // MARK: - Bug 1: toggleFolder must not crash via circular reference

    @Test("toggleFolder on inspector item with canOpen loads entries as children — no crash")
    func toggleFolderLoadsEntriesNotCircularSelf() async throws {
        let root   = await makeRoot()
        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Tome", itemId: itemId, forceSave: false)
        let entryId = addEntry(to: itemId, name: "Fire Chapter", content: "Dragons breathe fire", root: root)

        // Populate the link inspector list (unscoped, no parentModel)
        root.folderLinkController.searchModel.filterId = nil
        await root.folderLinkController.performSearch(source: "test")

        let listItem = try #require(
            root.folderLinkController.listModel.list.first(where: { $0.source.itemId == itemId }),
            "Item must appear in inspector list"
        )
        #expect(listItem.canOpen == true, "Item with entries must have canOpen=true")
        #expect(listItem.isOpen  == false, "Item must start closed")

        // Before the fix this caused infinite recursion in flattenCachedChildren → crash
        root.folderLinkController.toggleFolder(item: listItem)

        let children = root.folderLinkController.listModel.list.filter {
            $0.source.entryId != nil && $0.source.itemId == itemId
        }
        #expect(!children.isEmpty,
                "Entries must appear in the flat list after toggle")
        #expect(children.allSatisfy { $0.id != listItem.id },
                "No child id must equal the parent id — circular reference is gone")
        #expect(children.contains(where: { $0.source.entryId == entryId }),
                "The actual PDF entry must appear as a child")
    }

    @Test("toggleFolder: child ids are entryIds (not itemId) — confirming no self-reference")
    func toggleFolderChildIdsAreEntryIds() async throws {
        let root   = await makeRoot()
        let itemId = await root.itemController.addNew(type: .item)
        let e1     = addEntry(to: itemId, name: "Entry A", content: "", root: root)
        let e2     = addEntry(to: itemId, name: "Entry B", content: "", root: root)

        root.folderLinkController.searchModel.filterId = nil
        await root.folderLinkController.performSearch(source: "test")

        let listItem = try #require(
            root.folderLinkController.listModel.list.first(where: { $0.source.itemId == itemId })
        )
        root.folderLinkController.toggleFolder(item: listItem)

        let childIds    = listItem.children.map(\.id)
        let entryIdSet  = Set([e1, e2])

        #expect(childIds.allSatisfy { entryIdSet.contains($0) },
                "Each child FolderListItemModel.id must be an entryId, not the parent itemId")
        #expect(!childIds.contains(itemId),
                "itemId must never appear as a child id")
    }

    // MARK: - Bug 2: performDetailSearch scopes correctly even when listMode is .list

    @Test("performDetailSearch scopes to folder even when listDisplayModel.listMode is .list")
    func performDetailSearchScopesInListMode() async throws {
        let root      = await makeRoot()
        let folderId  = await root.itemController.addNew(type: .folder)
        let childId   = await root.itemController.addNew(type: .item)
        let unrelated = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Folder",    itemId: folderId, forceSave: false)
        root.editController.reset(name: "Child",     itemId: childId, forceSave: false)
        root.editController.reset(name: "Unrelated", itemId: unrelated, forceSave: false)
        root.editController.addItem(itemId: childId, parentId: folderId)

        guard let folderModel = root.itemController.itemSync(for: folderId) else {
            #expect(Bool(false), "Folder must be findable")
            return
        }

        // Explicitly set list mode — the old bug: scopedResults was using results(text:) which
        // in SearchListController only passes filterId as focusId in .folder mode,
        // so .list mode returned everything (unscoped).
        root.folderListController.listDisplayModel.listMode = .list

        root.folderListController.resetDetail(model: folderModel)
        await root.folderListController.performDetailSearch()

        let detail   = try #require(root.folderListController.listModel.detailListModel)
        let detailIds = detail.list.map(\.source.itemId)

        #expect(detailIds.contains(childId),
                "Folder child must appear in detail list even with listMode=.list")
        #expect(!detailIds.contains(unrelated),
                "Unrelated item must NOT appear — scopedResults must scope to folder regardless of listMode")
        #expect(!detailIds.contains(folderId),
                "The folder itself must not appear in its own detail list")
    }

    @Test("performDetailSearch scopes correctly in folder mode too (baseline)")
    func performDetailSearchScopesInFolderMode() async throws {
        let root      = await makeRoot()
        let folderId  = await root.itemController.addNew(type: .folder)
        let childId   = await root.itemController.addNew(type: .item)
        let unrelated = await root.itemController.addNew(type: .item)
        root.editController.addItem(itemId: childId, parentId: folderId)

        guard let folderModel = root.itemController.itemSync(for: folderId) else { return }

        root.folderListController.listDisplayModel.listMode = .folder
        root.folderListController.resetDetail(model: folderModel)
        await root.folderListController.performDetailSearch()

        let detailIds = root.folderListController.listModel.detailListModel?.list.map(\.source.itemId) ?? []
        #expect(detailIds.contains(childId),   "Child must appear")
        #expect(!detailIds.contains(unrelated), "Unrelated must not appear")
    }
}

// MARK: - Inspector: toggle during search shows ALL content

/// The rule: `loadChildrenViaSearch` always uses EMPTY search text so the user sees ALL
/// entries/children when they tap the chevron, not just the subset matching the filter.
@MainActor
struct InspectorToggleShowsAllContentTests {

    private func makeRoot() async -> PdfRootModel {
        let root = PdfRootModel.testRoot()
        await root.itemController.resetData()
        return root
    }

    private func addEntry(to itemId: UUID, name: String, content: String,
                          root: PdfRootModel) -> UUID {
        let id = UUID()
        root.itemController.itemOrEmpty(for: itemId).entries.append(
            PdfEntryModel(id: id, name: name, content: content, pageNumber: "1", bounds: .zero)
        )
        return id
    }

    @Test("Inspector: toggling item during search shows ALL entries — not just matching ones")
    func inspectorToggleShowsAllEntries() async throws {
        let root   = await makeRoot()
        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Codex", itemId: itemId, forceSave: false)  // name matches "Dragon"

        // Add entries: only one matches "Dragon" in its name
        let e1 = addEntry(to: itemId, name: "Dragon Lore",  content: "About fire", root: root)
        let e2 = addEntry(to: itemId, name: "Chapter Two",  content: "Unrelated",  root: root)
        let e3 = addEntry(to: itemId, name: "Chapter Three", content: "Also unrelated", root: root)

        // Search "Dragon" → item appears by name, canOpen=true
        root.folderLinkController.searchModel.filterId = nil
        await root.folderLinkController.performSearch(source: "test")

        let listItem = try #require(
            root.folderLinkController.listModel.list.first(where: { $0.source.itemId == itemId })
        )
        #expect(listItem.canOpen == true,  "Item with entries has canOpen=true")
        #expect(listItem.isOpen == false,  "Starts closed")

        // Toggle → ALL entries must appear (not just "Dragon Lore")
        root.folderLinkController.toggleFolder(item: listItem)

        let flat = root.folderLinkController.listModel.list
        #expect(flat.contains(where: { $0.source.entryId == e1 }), "Dragon Lore must appear")
        #expect(flat.contains(where: { $0.source.entryId == e2 }), "Chapter Two must appear (no filter)")
        #expect(flat.contains(where: { $0.source.entryId == e3 }), "Chapter Three must appear (no filter)")
    }

    @Test("Inspector folder mode: toggling folder during search shows ALL folder children")
    func inspectorFolderToggleShowsAllChildren() async throws {
        let root     = await makeRoot()
        let folderId = await root.itemController.addNew(type: .folder)
        let child1   = await root.itemController.addNew(type: .item)
        let child2   = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Archive",  itemId: folderId, forceSave: false) // matches "Dragon"
        root.editController.reset(name: "Coastal Shot",    itemId: child1, forceSave: false)   // no "Dragon"
        root.editController.reset(name: "Forest Path",     itemId: child2, forceSave: false)   // no "Dragon"
        root.editController.addItem(itemId: child1, parentId: folderId)
        root.editController.addItem(itemId: child2, parentId: folderId)

        root.folderLinkController.listDisplayModel.listMode = .folder
        root.folderLinkController.searchModel.filterId = nil
        await root.folderLinkController.performSearch(source: "test")

        let folderNode = try #require(
            root.folderLinkController.listModel.list.first(where: { $0.source.itemId == folderId })
        )
        #expect(folderNode.canOpen == true,  "Folder found by name, canOpen=true")
        #expect(folderNode.isOpen == false,  "Starts closed (no children match)")

        root.folderLinkController.toggleFolder(item: folderNode)

        let flat = root.folderLinkController.listModel.list
        #expect(flat.contains(where: { $0.source.itemId == child1 }),
                "Coastal Shot must appear even though it doesn't match 'Dragon'")
        #expect(flat.contains(where: { $0.source.itemId == child2 }),
                "Forest Path must appear even though it doesn't match 'Dragon'")
    }

    @Test("Inspector: item stays open and shows all entries when search changes after toggle")
    func inspectorItemStaysOpenAfterSearchChange() async throws {
        let root   = await makeRoot()
        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Manual", itemId: itemId, forceSave: false)
        let e1 = addEntry(to: itemId, name: "Intro",   content: "No match", root: root)
        let e2 = addEntry(to: itemId, name: "Dragon Chapter", content: "Fire", root: root)

        root.folderLinkController.searchModel.filterId = nil
        await root.folderLinkController.performSearch(source: "test")

        let listItem = try #require(
            root.folderLinkController.listModel.list.first(where: { $0.source.itemId == itemId })
        )
        // Open it
        root.folderLinkController.toggleFolder(item: listItem)
        #expect(root.folderLinkController.listModel.list.contains(where: { $0.source.entryId == e1 }),
                "All entries visible after toggle")
        #expect(root.folderLinkController.listModel.list.contains(where: { $0.source.entryId == e2 }),
                "All entries visible after toggle")

        // Re-run the same search — item should stay open with all entries
        await root.folderLinkController.performSearch(source: "test")
        let afterReSearch = root.folderLinkController.listModel.list
            .first(where: { $0.source.itemId == itemId })
        #expect(afterReSearch?.isOpen == true,
                "Item stays open after re-search (lastIsOpen=true preserved)")
        #expect(root.folderLinkController.listModel.list.contains(where: { $0.source.entryId == e1 }),
                "All entries remain visible after re-search")
    }
}
#endif
