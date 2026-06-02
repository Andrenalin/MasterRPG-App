// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import CoreGraphics
import Foundation
import RPGResourcesDebug
import Testing

@testable import PdfRPG

@MainActor
struct SearchControllerTests {

    // MARK: - List mode, empty search

    @Test("Empty list search returns all regular items and excludes folders/collections")
    func emptyListSearchExcludesFolders() async throws {
        let root = PdfRootModel.testRoot()
        await root.itemController.resetData()

        let item1 = await root.itemController.addNew(type: .item)
        let item2 = await root.itemController.addNew(type: .item)
        let folder = await root.itemController.addNew(type: .folder)

        let results = await root.searchController.listSearchResults(
            searchText: "",
            listMode: .list,
            displayMode: .medium,
            focusId: nil
        )

        let ids = results.map(\.itemId)
        #expect(ids.contains(item1))
        #expect(ids.contains(item2))
        #expect(!ids.contains(folder), "Folders must be excluded in list mode")
        #expect(results.allSatisfy { !$0.category.isCollection && $0.category != .folder },
                "No special-category items may appear in list mode")
    }

    @Test("Empty list search returns items sorted alphabetically")
    func emptyListSearchSortsAlphabetically() async throws {
        let root = PdfRootModel.testRoot()
        await root.itemController.resetData()

        let idC = await root.itemController.addNew(type: .item)
        let idA = await root.itemController.addNew(type: .item)
        let idB = await root.itemController.addNew(type: .item)

        root.itemController.itemOrEmpty(for: idC).name = "Charlie"
        root.itemController.itemOrEmpty(for: idA).name = "Alice"
        root.itemController.itemOrEmpty(for: idB).name = "Bob"

        let results = await root.searchController.listSearchResults(
            searchText: "",
            listMode: .list,
            displayMode: .medium,
            focusId: nil
        )

        let names = results.map(\.itemName)
        let sortedNames = names.sorted { $0.localizedCompare($1) == .orderedAscending }
        #expect(names == sortedNames, "Items must be sorted alphabetically by localized name")
    }

    // MARK: - List mode: children invariant

    @Test("List mode search results never carry children — empty search")
    func listModeEmptySearchResultsHaveNoChildren() async throws {
        let root = PdfRootModel.testRoot()
        await root.itemController.resetData()

        // Add a folder with an item inside it
        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.addItem(itemId: childId, parentId: folderId)
        let _ = await root.itemController.addNew(type: .item)

        let results = await root.searchController.listSearchResults(
            searchText: "",
            listMode: .list,
            displayMode: .medium,
            focusId: nil
        )

        #expect(!results.isEmpty, "List must return items")
        for result in results {
            #expect(result.children.isEmpty,
                    "List mode must never return children in SearchResult (got non-empty children for \(result.itemName))")
        }
    }

    @Test("List mode search results never carry children — non-empty search")
    func listModeSearchResultsHaveNoChildren() async throws {
        let root = PdfRootModel.testRoot()
        await root.itemController.resetData()

        let folderId = await root.itemController.addNew(type: .folder)
        root.itemController.itemOrEmpty(for: folderId).name = "Rules folder"
        let childId = await root.itemController.addNew(type: .item)
        root.itemController.itemOrEmpty(for: childId).name = "Rules inside folder"
        root.editController.addItem(itemId: childId, parentId: folderId)

        let standaloneId = await root.itemController.addNew(type: .item)
        root.itemController.itemOrEmpty(for: standaloneId).name = "Rules standalone"

        let results = await root.searchController.listSearchResults(
            searchText: "Rules",
            listMode: .list,
            displayMode: .medium,
            focusId: nil
        )

        // The child item inside the folder should match and appear flat in list mode
        #expect(results.contains(where: { $0.itemId == childId }),
                "Child items inside folders must still appear in list mode search")
        // But NO result — whether a regular item or a folder child — may carry children
        for result in results {
            #expect(result.children.isEmpty,
                    "List mode must never return children in SearchResult (got non-empty children for \(result.itemName))")
        }
    }

    // MARK: - Folder mode, no focus (root content)

    @Test("Empty folder search without focus returns root-level items; folder children are lazy-loaded")
    func emptyFolderSearchWithoutFocusReturnsRootContent() async throws {
        let root = PdfRootModel.testRoot()
        await root.itemController.resetData()

        let rootItemId = await root.itemController.addNew(type: .item)
        let folderId   = await root.itemController.addNew(type: .folder)
        let childId    = await root.itemController.addNew(type: .item)
        root.editController.addItem(itemId: childId, parentId: folderId)

        let results = await root.searchController.listSearchResults(
            searchText: "",
            listMode: .folder,
            displayMode: .medium,
            focusId: nil
        )

        let rootIds = results.map(\.itemId)
        #expect(rootIds.contains(rootItemId), "Root-level regular items must appear")
        #expect(rootIds.contains(folderId),   "Root-level folders must appear")
        #expect(!rootIds.contains(childId),   "Child items must not appear at root level")

        // Lazy loading: children are NOT pre-fetched on empty search.
        // FolderListControllable.toggleFolder calls loadFolderChildren on demand.
        let folderResult = try #require(results.first(where: { $0.itemId == folderId }))
        #expect(folderResult.children.isEmpty,
                "SearchResult.children must be empty for empty search — children load on open")
    }

    @Test("Empty folder search without focus sorts root items alphabetically")
    func emptyFolderSearchWithoutFocusSortsRootAlphabetically() async throws {
        let root = PdfRootModel.testRoot()
        await root.itemController.resetData()

        let idC = await root.itemController.addNew(type: .item)
        let idA = await root.itemController.addNew(type: .item)
        let idB = await root.itemController.addNew(type: .item)

        root.itemController.itemOrEmpty(for: idC).name = "Charlie"
        root.itemController.itemOrEmpty(for: idA).name = "Alice"
        root.itemController.itemOrEmpty(for: idB).name = "Bob"

        let results = await root.searchController.listSearchResults(
            searchText: "",
            listMode: .folder,
            displayMode: .medium,
            focusId: nil
        )

        let names = results.map(\.itemName)
        let sorted = names.sorted { $0.localizedCompare($1) == .orderedAscending }
        #expect(names == sorted, "Root items must be sorted alphabetically")
    }

    // MARK: - Folder mode, with focus (folder content)

    @Test("Empty folder search with focus returns only direct children of that folder")
    func emptyFolderSearchWithFocusReturnsFolderContent() async throws {
        let root = PdfRootModel.testRoot()
        await root.itemController.resetData()

        let folderId   = await root.itemController.addNew(type: .folder)
        let childId1   = await root.itemController.addNew(type: .item)
        let childId2   = await root.itemController.addNew(type: .item)
        let unrelatedId = await root.itemController.addNew(type: .item)

        root.editController.addItem(itemId: childId1, parentId: folderId)
        root.editController.addItem(itemId: childId2, parentId: folderId)

        let results = await root.searchController.listSearchResults(
            searchText: "",
            listMode: .folder,
            displayMode: .medium,
            focusId: folderId
        )

        let ids = results.map(\.itemId)
        #expect(ids.contains(childId1), "First child must appear")
        #expect(ids.contains(childId2), "Second child must appear")
        #expect(!ids.contains(unrelatedId), "Items outside the folder must not appear")
        #expect(!ids.contains(folderId),    "The folder itself must not appear in its own results")
    }

    @Test("Empty folder search with focus sorts children alphabetically")
    func emptyFolderSearchWithFocusSortsChildrenAlphabetically() async throws {
        let root = PdfRootModel.testRoot()
        await root.itemController.resetData()

        let folderId = await root.itemController.addNew(type: .folder)
        let idC = await root.itemController.addNew(type: .item)
        let idA = await root.itemController.addNew(type: .item)
        let idB = await root.itemController.addNew(type: .item)

        root.itemController.itemOrEmpty(for: idC).name = "Charlie"
        root.itemController.itemOrEmpty(for: idA).name = "Alice"
        root.itemController.itemOrEmpty(for: idB).name = "Bob"

        root.editController.addItem(itemId: idC, parentId: folderId)
        root.editController.addItem(itemId: idA, parentId: folderId)
        root.editController.addItem(itemId: idB, parentId: folderId)

        let results = await root.searchController.listSearchResults(
            searchText: "",
            listMode: .folder,
            displayMode: .medium,
            focusId: folderId
        )

        let names = results.map(\.itemName)
        let sorted = names.sorted { $0.localizedCompare($1) == .orderedAscending }
        #expect(names == sorted, "Folder children must be sorted alphabetically")
    }

    @Test("Focused folder search children carry the folder entry's UUID as entryId")
    func focusedFolderSearchChildrenCarryEntryId() async throws {
        let root = PdfRootModel.testRoot()
        await root.itemController.resetData()

        let folderId = await root.itemController.addNew(type: .folder)
        let childId  = await root.itemController.addNew(type: .item)
        root.editController.addItem(itemId: childId, parentId: folderId)

        let results = await root.searchController.listSearchResults(
            searchText: "",
            listMode: .folder,
            displayMode: .medium,
            focusId: folderId
        )

        let child = try #require(results.first(where: { $0.itemId == childId }))
        // entryId must be set — it is the folder's membership entry UUID used as
        // FolderListItemModel.id so the same item in multiple collections gets
        // independent SwiftUI identities. (For PdfEntryModel, entry.id == childId
        // by design; other modules use a distinct entry UUID.)
        #expect(child.entryId != nil, "Child result must carry the folder entry's UUID as entryId")
    }

    // MARK: - Inspector search

    // Helper: creates an item with two named entries
    private func makeItemWithEntries(root: PdfRootModel, itemName: String, entries: [(name: String, content: String)]) async -> UUID {
        let itemId = await root.itemController.addNew(type: .item)
        root.itemController.itemOrEmpty(for: itemId).name = itemName
        for entry in entries {
            root.itemController.itemOrEmpty(for: itemId).entries.append(
                PdfEntryModel(id: UUID(), name: entry.name, content: entry.content, pageNumber: "1", bounds: .zero)
            )
        }
        return itemId
    }

    @Test("Inspector list: entry name match makes entry a child of item result")
    func inspectorListEntryNameMatchIsChild() async throws {
        let root = PdfRootModel.testRoot()
        await root.itemController.resetData()

        let itemId = await makeItemWithEntries(root: root, itemName: "Adventure Book", entries: [
            (name: "Dragon Encounter", content: "A tough fight")
        ])

        let results = await root.searchController.inspectorSearchResults(
            searchText: "Dragon",
            listMode: .list,
            displayMode: .medium,
            focusId: nil
        )

        let itemResult = try #require(results.first(where: { $0.itemId == itemId }),
                                      "Item must appear because its entry name matches")
        #expect(!itemResult.children.isEmpty, "Matching entry must be a child of the item result")
        #expect(itemResult.children.allSatisfy { $0.entryId != nil },
                "All children must carry their entry UUID")
    }

    @Test("Inspector list: matching entries are children, not flat siblings")
    func inspectorListEntryResultsAreNotFlatSiblings() async throws {
        let root = PdfRootModel.testRoot()
        await root.itemController.resetData()

        let itemId = await makeItemWithEntries(root: root, itemName: "Rulebook", entries: [
            (name: "Dragon rules", content: "How to fight dragons"),
            (name: "Other rules",  content: "Unrelated content")
        ])

        let results = await root.searchController.inspectorSearchResults(
            searchText: "Dragon",
            listMode: .list,
            displayMode: .medium,
            focusId: nil
        )

        // There must be exactly one top-level result for this item (not one per matching entry)
        let itemResults = results.filter { $0.itemId == itemId && $0.entryId == nil }
        #expect(itemResults.count == 1, "Item must appear exactly once at the top level")

        let itemResult = try #require(itemResults.first)
        // The matching entries are children, not top-level results
        #expect(results.filter { $0.entryId != nil }.isEmpty,
                "Entry-level results must not appear at the top level")
        #expect(itemResult.children.count == 1,
                "Only the matching entry (Dragon rules) must be a child")
    }

    @Test("Inspector list: entry content is always searched in compact display mode")
    func inspectorListEntryContentSearchedInCompactMode() async throws {
        let root = PdfRootModel.testRoot()
        await root.itemController.resetData()

        // Item name does NOT contain "Dragon" so compact item-level search won't match.
        // Entry content DOES contain "Dragon" — inspector must always search entry content.
        let itemId = await makeItemWithEntries(root: root, itemName: "Rules Book", entries: [
            (name: "Chapter One", content: "Describes a Dragon lair")
        ])

        let results = await root.searchController.inspectorSearchResults(
            searchText: "Dragon",
            listMode: .list,
            displayMode: .compact,   // compact mode: item-level only name; entry always name+content
            focusId: nil
        )

        let itemResult = try #require(results.first(where: { $0.itemId == itemId }),
                                      "Item must appear: inspector always searches entry content regardless of compact mode")
        #expect(!itemResult.children.isEmpty, "Entry content match must produce a child")
    }

    @Test("Inspector list: item not matching but entry does — item included with entry child")
    func inspectorListItemIncludedWhenOnlyEntryMatches() async throws {
        let root = PdfRootModel.testRoot()
        await root.itemController.resetData()

        // Item name and description don't contain "Dragon" at all
        let itemId = await makeItemWithEntries(root: root, itemName: "Knights Tale", entries: [
            (name: "Dragon Sighting", content: "They saw one")
        ])

        let results = await root.searchController.inspectorSearchResults(
            searchText: "Dragon",
            listMode: .list,
            displayMode: .medium,
            focusId: nil
        )

        let itemResult = try #require(results.first(where: { $0.itemId == itemId }),
                                      "Item must be included even if only its entries match")
        #expect(!itemResult.children.isEmpty)
    }

    @Test("Inspector list: no item or entry match — item excluded")
    func inspectorListItemExcludedWhenNoMatch() async throws {
        let root = PdfRootModel.testRoot()
        await root.itemController.resetData()

        let itemId = await makeItemWithEntries(root: root, itemName: "Knights Tale", entries: [
            (name: "Chapter One", content: "About brave knights")
        ])

        let results = await root.searchController.inspectorSearchResults(
            searchText: "Dragon",
            listMode: .list,
            displayMode: .medium,
            focusId: nil
        )

        #expect(!results.contains(where: { $0.itemId == itemId }),
                "Item with no matching name, description, or entries must be excluded")
    }

    @Test("Inspector list: item matches and entries match — single result with entry children")
    func inspectorListItemAndEntriesMatchProduceSingleResult() async throws {
        let root = PdfRootModel.testRoot()
        await root.itemController.resetData()

        let itemId = await makeItemWithEntries(root: root, itemName: "Dragon Compendium", entries: [
            (name: "Dragon types",  content: "Fire and ice"),
            (name: "Dragon lairs",  content: "Where they live"),
            (name: "Other chapter", content: "Unrelated")
        ])

        let results = await root.searchController.inspectorSearchResults(
            searchText: "Dragon",
            listMode: .list,
            displayMode: .medium,
            focusId: nil
        )

        let itemResults = results.filter { $0.itemId == itemId }
        #expect(itemResults.count == 1, "Item must appear exactly once even when both item and entries match")
        let itemResult = try #require(itemResults.first)
        #expect(itemResult.children.count == 2, "Only 'Dragon types' and 'Dragon lairs' entries match")
    }

    @Test("Inspector list: entry children sorted by relevance (name match ranks above content match)")
    func inspectorListEntryChildrenSortedByRelevance() async throws {
        let root = PdfRootModel.testRoot()
        await root.itemController.resetData()

        let entryNameMatchId = UUID()
        let entryContentMatchId = UUID()

        let itemId = await root.itemController.addNew(type: .item)
        // Insert content-match first so insertion order != expected relevance order
        root.itemController.itemOrEmpty(for: itemId).entries = [
            PdfEntryModel(id: entryContentMatchId, name: "Chapter Two",   content: "About a dragon", pageNumber: "2", bounds: .zero),
            PdfEntryModel(id: entryNameMatchId,    name: "Dragon basics", content: "Fire type",      pageNumber: "1", bounds: .zero)
        ]

        let results = await root.searchController.inspectorSearchResults(
            searchText: "dragon",
            listMode: .list,
            displayMode: .medium,
            focusId: nil
        )

        let itemResult = try #require(results.first(where: { $0.itemId == itemId }))
        let childIds = itemResult.children.compactMap(\.entryId)
        #expect(childIds.count == 2)
        let nameMatchPos    = try #require(childIds.firstIndex(of: entryNameMatchId))
        let contentMatchPos = try #require(childIds.firstIndex(of: entryContentMatchId))
        #expect(nameMatchPos < contentMatchPos,
                "Entry with name match must rank higher than entry with content-only match")
    }
}
#endif
