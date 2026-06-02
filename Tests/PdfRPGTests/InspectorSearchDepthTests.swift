// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import CoreGraphics
import Foundation
import RPGResourcesDebug
import Testing

@testable import PdfRPG

/// Tests for `inspectorBatchListResults` adaptive entry-search depth.
///
/// Rules:
///   - text.count < 3  → no entry search (item-level only)
///   - text.count ≥ 3, item matches  < 10 → wide:  entry name + content
///   - text.count ≥ 3, item matches ≥ 10 → narrow: entry name only
///       └─ if total entry-name hits ≤ 5  → also include content matches
///
/// Relevance order: item name match > entry name match > description/content match.
@MainActor
struct InspectorSearchDepthTests {

    // MARK: - Helpers

    private func makeRoot() async -> PdfRootModel {
        let root = PdfRootModel.testRoot()
        await root.itemController.resetData()
        return root
    }

    /// Calls `inspectorSearchResults` directly (list mode, no focusId).
    private func results(root: PdfRootModel, text: String,
                         displayMode: ListDisplayModel.DisplayMode = .medium) async -> [SearchResult] {
        await root.searchController.inspectorSearchResults(
            searchText: text,
            listMode: .list,
            displayMode: displayMode,
            focusId: nil
        )
    }

    /// Appends a PdfEntryModel with a custom name and content to the given item.
    private func addEntry(to itemId: UUID, name: String, content: String,
                          root: PdfRootModel) -> UUID {
        let id = UUID()
        root.itemController.itemOrEmpty(for: itemId).entries.append(
            PdfEntryModel(id: id, name: name, content: content, pageNumber: "1", bounds: .zero)
        )
        return id
    }

    // MARK: - text.count < 3: no entry search

    @Test("text shorter than 3 chars does not search entries — neither name nor content")
    func shortTextSkipsEntrySearch() async {
        let root = await makeRoot()

        // Item name does NOT contain "dr"
        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Rulebook", itemId: itemId)
        let entryId = addEntry(to: itemId, name: "Dragon Chapter", content: "About dr monsters", root: root)

        // "dr" is 2 chars → entry search disabled
        let res = await results(root: root, text: "dr")

        for result in res {
            #expect(result.children.isEmpty,
                    "2-char text must produce no entry children — entry search is disabled")
        }
        #expect(!res.map(\.itemId).contains(itemId),
                "Item must not appear: name doesn't match 'dr', entries not searched")
        _ = entryId
    }

    @Test("text of exactly 3 chars enables entry search")
    func threeCharTextEnablesEntrySearch() async {
        let root = await makeRoot()

        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Rulebook", itemId: itemId)
        let entryId = addEntry(to: itemId, name: "Dra Chapter", content: "irrelevant", root: root)
        // "Dra" matches entry name "Dra Chapter" exactly — 3-char text

        let res = await results(root: root, text: "Dra")

        let itemResult = try? res.first(where: { $0.itemId == itemId })
        #expect(itemResult != nil, "Item must appear via entry name match at 3 chars")
        #expect(itemResult?.children.contains(where: { $0.entryId == entryId }) == true,
                "Matching entry must be a child at 3-char threshold")
    }

    // MARK: - text.count ≥ 3, item matches < 10: wide entry search

    @Test("fewer than 10 item matches → entry content is also searched")
    func fewItemMatchesTriggersContentSearch() async {
        let root = await makeRoot()

        // 2 items match "Dragon" by name (< 10 → wide mode)
        let item1 = await root.itemController.addNew(type: .item)
        let item2 = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Guide",  itemId: item1)
        root.editController.reset(name: "Dragon Manual", itemId: item2)

        // item3 does NOT match by name, but has an entry whose CONTENT contains "Dragon"
        let item3 = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Monster Book", itemId: item3)
        let contentEntryId = addEntry(to: item3, name: "Chapter Three",
                                      content: "Includes a fearsome dragon encounter", root: root)

        let res = await results(root: root, text: "Dragon")

        // 2 item-level matches → wide mode → item3 pulled in by content match
        #expect(res.map(\.itemId).contains(item3),
                "Item3 must be pulled in by entry content match when < 10 item-level matches")
        let item3Result = try? res.first(where: { $0.itemId == item3 })
        #expect(item3Result?.children.contains(where: { $0.entryId == contentEntryId }) == true,
                "Content-matching entry must be a child of item3")
    }

    @Test("fewer than 10 item matches → entry whose name matches also appears")
    func fewItemMatchesIncludesEntryNameMatch() async {
        let root = await makeRoot()

        let item1 = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Guide", itemId: item1)

        // Add entry with matching name and unrelated content
        let nameEntryId = addEntry(to: item1, name: "Dragon Abilities",
                                   content: "Various powers listed here", root: root)

        let res = await results(root: root, text: "Dragon")

        let item1Result = try? res.first(where: { $0.itemId == item1 })
        #expect(item1Result?.children.contains(where: { $0.entryId == nameEntryId }) == true,
                "Entry matching by name must appear as child in wide mode")
    }

    // MARK: - text.count ≥ 3, item matches ≥ 10: narrow entry search (name only)

    @Test("10 or more item matches restricts entry search to name only — content excluded")
    func manyItemMatchesRestrictsToNameOnly() async {
        let root = await makeRoot()

        // 10 items all match "Dragon" by name → triggers ≥ 10 threshold
        var topItemIds: [UUID] = []
        for i in 1...10 {
            let id = await root.itemController.addNew(type: .item)
            root.editController.reset(name: "Dragon \(i)", itemId: id)
            topItemIds.append(id)
        }

        // Add entry to first item: content only (no name match) — should be EXCLUDED in narrow mode
        let contentOnlyEntry = addEntry(to: topItemIds[0], name: "Chapter One",
                                        content: "A fierce dragon lurks here", root: root)
        // Also add 6 entry NAME matches (> 5) to keep expand-to-content from triggering
        for i in 0..<6 {
            _ = addEntry(to: topItemIds[i], name: "Dragon Section \(i)",
                         content: "irrelevant", root: root)
        }

        let res = await results(root: root, text: "Dragon")

        let first = try? res.first(where: { $0.itemId == topItemIds[0] })
        #expect(first?.children.contains(where: { $0.entryId == contentOnlyEntry }) == false,
                "Content-only entry must NOT appear when ≥ 10 item matches and > 5 name hits")
    }

    @Test("10 or more item matches but ≤ 5 entry name hits upgrades to include content matches")
    func manyItemsFewEntryNameHitsExpandsToContent() async {
        let root = await makeRoot()

        // 10 items match "Dragon" by name
        var topItemIds: [UUID] = []
        for i in 1...10 {
            let id = await root.itemController.addNew(type: .item)
            root.editController.reset(name: "Dragon \(i)", itemId: id)
            topItemIds.append(id)
        }

        // Add exactly 3 entry NAME matches (≤ 5 → expand-to-content triggers)
        _ = addEntry(to: topItemIds[0], name: "Dragon Lore",    content: "irrelevant", root: root)
        _ = addEntry(to: topItemIds[1], name: "Dragon Tactics", content: "irrelevant", root: root)
        _ = addEntry(to: topItemIds[2], name: "Dragon History", content: "irrelevant", root: root)

        // Add an entry that only matches in CONTENT — must appear because expand-to-content is active
        let contentEntry = addEntry(to: topItemIds[3], name: "Chapter Four",
                                    content: "Dragons breathe fire and guard their hoard", root: root)

        let res = await results(root: root, text: "Dragon")

        let item4Result = try? res.first(where: { $0.itemId == topItemIds[3] })
        #expect(item4Result?.children.contains(where: { $0.entryId == contentEntry }) == true,
                "Content entry must appear when total entry-name hits ≤ 5 (expand-to-content)")
    }

    @Test("10 or more item matches with exactly 5 entry name hits also includes content (boundary)")
    func fiveEntryNameHitsBoundaryExpandsToContent() async {
        let root = await makeRoot()

        var topItemIds: [UUID] = []
        for i in 1...10 {
            let id = await root.itemController.addNew(type: .item)
            root.editController.reset(name: "Dragon \(i)", itemId: id)
            topItemIds.append(id)
        }

        // Exactly 5 name matches (boundary — must still expand)
        for i in 0..<5 {
            _ = addEntry(to: topItemIds[i], name: "Dragon Entry \(i)", content: "irrelevant", root: root)
        }

        let contentEntry = addEntry(to: topItemIds[5], name: "Chapter Six",
                                    content: "A powerful dragon awaits", root: root)

        let res = await results(root: root, text: "Dragon")

        let item6Result = try? res.first(where: { $0.itemId == topItemIds[5] })
        #expect(item6Result?.children.contains(where: { $0.entryId == contentEntry }) == true,
                "5 name hits is the boundary — content must still be included (≤ 5)")
    }

    @Test("exactly 6 entry name hits (> 5) keeps name-only mode — content entry excluded")
    func sixEntryNameHitsKeepsNameOnlyMode() async {
        let root = await makeRoot()

        var topItemIds: [UUID] = []
        for i in 1...10 {
            let id = await root.itemController.addNew(type: .item)
            root.editController.reset(name: "Dragon \(i)", itemId: id)
            topItemIds.append(id)
        }

        // 6 name matches (> 5 → stay in name-only mode)
        for i in 0..<6 {
            _ = addEntry(to: topItemIds[i], name: "Dragon Entry \(i)", content: "irrelevant", root: root)
        }

        let contentEntry = addEntry(to: topItemIds[6], name: "Chapter Seven",
                                    content: "Legends tell of a mighty dragon here", root: root)

        let res = await results(root: root, text: "Dragon")

        let item7Result = try? res.first(where: { $0.itemId == topItemIds[6] })
        #expect(item7Result?.children.contains(where: { $0.entryId == contentEntry }) == false,
                "6 name hits exceeds threshold — content-only entry must be excluded")
    }

    // MARK: - Relevance ordering

    @Test("relevance: item name match > entry name match > description/content match")
    func relevanceOrderItemNameThenEntryNameThenContent() async {
        let root = await makeRoot()

        // itemNameMatch: name = "Dragon Guide"        → item name match (high)
        let itemNameMatch = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Guide", itemId: itemNameMatch)

        // entryNameMatch: name = "Adventurer's Log"   → item name doesn't match
        //   entry name = "Dragon Slayer"              → entry name match (medium)
        let entryNameMatch = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Adventurer's Log", itemId: entryNameMatch)
        _ = addEntry(to: entryNameMatch, name: "Dragon Slayer", content: "irrelevant", root: root)

        // contentOnly: name = "Field Notes"           → item name doesn't match
        //   entry content = "...dragon..."            → content match (low)
        let contentOnly = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Field Notes", itemId: contentOnly)
        _ = addEntry(to: contentOnly, name: "Chapter One",
                     content: "Spotted a dragon near the ruins", root: root)

        // 3 item-level matches (< 10 → wide mode so all three appear)
        // But only itemNameMatch has an item-level name match; the others are pulled in by entries.
        let res = await results(root: root, text: "Dragon")
        let ids = res.map(\.itemId)

        #expect(ids.contains(itemNameMatch), "Item name match must appear")
        #expect(ids.contains(entryNameMatch), "Entry name match must appear")
        #expect(ids.contains(contentOnly), "Content match must appear (wide mode, < 10 items)")

        let nameIdx    = try? ids.firstIndex(of: itemNameMatch)
        let entryIdx   = try? ids.firstIndex(of: entryNameMatch)
        let contentIdx = try? ids.firstIndex(of: contentOnly)

        if let n = nameIdx, let e = entryIdx {
            #expect(n <= e, "Item name match must rank at or above entry name match")
        }
        if let e = entryIdx, let c = contentIdx {
            #expect(e <= c, "Entry name match must rank at or above content-only match")
        }
    }

    @Test("entry children sorted: entry name match before content-only match within same item")
    func entryChildrenSortedByRelevance() async {
        let root = await makeRoot()

        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Codex", itemId: itemId)

        // Insert content match FIRST to prove sorting is not insertion order
        let contentEntryId = addEntry(to: itemId, name: "Chapter Two",
                                      content: "Discussion of dragon biology", root: root)
        let nameEntryId    = addEntry(to: itemId, name: "Dragon Types",
                                      content: "Fire, ice, poison", root: root)

        let res = await results(root: root, text: "Dragon")

        let itemResult = try? res.first(where: { $0.itemId == itemId })
        let children = itemResult?.children ?? []
        #expect(children.count >= 2, "Both entries must appear")

        let nameIdx    = children.firstIndex(where: { $0.entryId == nameEntryId })
        let contentIdx = children.firstIndex(where: { $0.entryId == contentEntryId })

        if let n = nameIdx, let c = contentIdx {
            #expect(n < c, "Entry name match must rank above content-only entry within same item")
        }
    }
}
#endif
