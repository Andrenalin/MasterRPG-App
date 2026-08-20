// @copyright André Trettin

import CoreRPG
@testable import DiceRPG
import Foundation
@testable import PdfRPG
import Testing
@testable import TableRPG

/// Regression coverage: the inspector must not reorder a table's entries (rows) when the
/// search field is empty. Only an active search filter may re-sort by relevance/name —
/// browsing/expanding a table with no search text must preserve the table's own row order.
@MainActor
@Suite("Inspector entry order")
struct InspectorEntryOrderTests {

    // MARK: - Helpers

    private func makeRoot() -> TableRootModel {
        TableRootModel.testRoot(
            diceRoot: DiceRootModel.testRoot(),
            pdfRoot: PdfRootModel.testRoot()
        )
    }

    private func makeSearchLinkController(root: TableRootModel) -> SearchLinkController {
        SearchLinkController(
            searchController: root.searchControllable,
            searchModel: SearchModel(tagController: .preview, module: .table),
            listDisplayModel: ListDisplayModel()
        )
    }

    private func makeTable(entryNames: [String]) -> TableModel {
        TableModel(
            id: UUID(),
            name: "Random Encounters",
            entries: entryNames.map { TableEntryModel.fixture(name: $0) }
        )
    }

    // MARK: - SearchLinkController.syncExpandResults (chevron expand, empty-search rebuild)

    @Test("syncExpandResults on empty search preserves table entry (row) order")
    func syncExpandPreservesTableRowOrder() {
        let root = makeRoot()
        let controller = makeSearchLinkController(root: root)

        // Deliberately non-alphabetical row order — this is the order a GM authored the table in.
        let table = makeTable(entryNames: ["Zombie Horde", "Ancient Dragon", "Mimic Chest"])
        root.itemController.replace(model: table, isInsert: true)

        let results = controller.syncExpandResults(focusId: table.id)
        let names = results.compactMap(\.entryName)

        #expect(names == ["Zombie Horde", "Ancient Dragon", "Mimic Chest"],
                "Table row order must be preserved, not alphabetized, when there is no search")
        #expect(names != names.sorted { $0.localizedCompare($1) == .orderedAscending },
                "Sanity check: the fixture order is not already alphabetical")
    }

    // MARK: - SearchControllable.inspectorEntryResults (results(text:focusId:) path)

    @Test("inspectorEntryResults with empty search text preserves table entry order")
    func inspectorEntryResultsEmptySearchPreservesOrder() {
        let root = makeRoot()
        let table = makeTable(entryNames: ["Zombie Horde", "Ancient Dragon", "Mimic Chest"])
        root.itemController.replace(model: table, isInsert: true)

        let results = root.searchControllable.inspectorEntryResults(
            searchText: "",
            itemId: table.id,
            displayMode: .medium
        )
        let names = results.compactMap(\.entryName)

        #expect(names == ["Zombie Horde", "Ancient Dragon", "Mimic Chest"],
                "Empty search text must return entries in table order, not alphabetical order")
    }

    @Test("inspectorEntryResults with active search text filters to matching entries only")
    func inspectorEntryResultsNonEmptySearchFilters() {
        let root = makeRoot()
        let table = makeTable(entryNames: ["Zombie Horde", "Ancient Dragon", "Mimic Chest"])
        root.itemController.replace(model: table, isInsert: true)

        let results = root.searchControllable.inspectorEntryResults(
            searchText: "Zomb",
            itemId: table.id,
            displayMode: .medium
        )
        let names = results.compactMap(\.entryName)

        // Only "Zombie Horde" contains "Zomb".
        #expect(names == ["Zombie Horde"],
                "Non-empty search must filter to matching entries only")
    }

    @Test("inspectorEntryResults with active search text sorts multiple matches alphabetically")
    func inspectorEntryResultsNonEmptySearchSortsMatches() {
        let root = makeRoot()
        // Authored (row) order deliberately reversed relative to alphabetical order.
        let table = makeTable(entryNames: ["Zeta Ambush", "Alpha Ambush", "Omega Solo"])
        root.itemController.replace(model: table, isInsert: true)

        let results = root.searchControllable.inspectorEntryResults(
            searchText: "Ambush",
            itemId: table.id,
            displayMode: .medium
        )
        let names = results.compactMap(\.entryName)

        #expect(names == ["Alpha Ambush", "Zeta Ambush"],
                "An active search filter must sort its matches alphabetically, not by row order")
    }

    @Test("results(text:focusId:) via SearchLinkController preserves order for empty search")
    func resultsTextFocusIdEmptySearchPreservesOrder() async {
        let root = makeRoot()
        let controller = makeSearchLinkController(root: root)

        let table = makeTable(entryNames: ["Zombie Horde", "Ancient Dragon", "Mimic Chest"])
        root.itemController.replace(model: table, isInsert: true)

        let results = await controller.results(text: "", focusId: table.id)
        let names = results.compactMap(\.entryName)

        #expect(names == ["Zombie Horde", "Ancient Dragon", "Mimic Chest"],
                "Expanding a table entry with no active search must not reorder its rows")
    }
}
