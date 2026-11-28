// @copyright André Trettin

#if canImport(Testing)
@testable import CoreRPG
import DiceRPG
import Foundation
import PdfRPG
import Testing

@testable import TableRPG

/// The editor window (macOS, iPad, visionOS) stays open while a game runs. Every edit it makes
/// reaches the database, and the game's in-memory copy of a loaded table shows it too, while a
/// change only the game copy has (here its description) stays out of the library.
@Suite("Table editor window during a game")
@MainActor
struct TableEditorWindowDuringGameTests {
    private static let libraryDescription = "Library description"
    private static let sessionDescription = "Session description"

    @MainActor
    private struct Fixture {
        let store: GameEditorStore
        let root: TableRootModel
        let itemId: UUID
        let entryId: UUID

        var game: GameEditorHarness<ItemController> { GameEditorHarness(itemController: root.itemController) }

        func expectEdit(sourceLocation: SourceLocation = #_sourceLocation, _ isEdited: (TableModel) -> Bool) async throws {
            try await game.expectEdit(
                itemId,
                libraryDescription: TableEditorWindowDuringGameTests.libraryDescription,
                sessionDescription: TableEditorWindowDuringGameTests.sessionDescription,
                sourceLocation: sourceLocation,
                isEdited
            )
        }
    }

    /// A table with one entry in the library and the database, a running game and, when
    /// `loaded`, the table in game memory with a change of its own.
    private func makeFixture(loaded: Bool = true) async throws -> Fixture {
        let store = try GameEditorStore(bundles: [CoreRPG.Resources.bundle, TableRPG.Resources.bundle])
        let root = TableRootModel.testRoot(diceRoot: DiceRootModel.testRoot(), pdfRoot: PdfRootModel.testRoot())
        root.itemController.itemDataModel.dataController = DataController(context: store.context, token: NetworkModules.table.token)
        let itemId = await root.itemController.addNew(type: .item)
        root.editController.update(id: itemId, name: "Loot", description: Self.libraryDescription, category: nil, tags: ["treasure"], forceSave: false)
        let entryId = root.editController.addNewEntry(itemId: itemId, forceSave: false)
        root.editController.update(itemId: itemId, entryId: entryId, name: "1", content: "Gold", forceSave: false)

        let fixture = Fixture(store: store, root: root, itemId: itemId, entryId: entryId)
        fixture.game.startGame()
        if loaded {
            fixture.game.loadIntoGame(itemId) { $0.description = Self.sessionDescription }
        }
        // Selecting the item in the editor starts its undo history.
        root.editController.editorModel.undoManaged.removeAll()
        return fixture
    }

    @Test("The header editor's name, tags and category reach the database and the game copy")
    func headerEdit() async throws {
        let fixture = try await makeFixture()

        fixture.root.editController.update(id: fixture.itemId, name: "Dragon Hoard", description: nil, category: .loot, tags: ["dragon", "treasure"], forceSave: true)

        try await fixture.expectEdit { $0.name == "Dragon Hoard" && $0.tags == ["dragon", "treasure"] && $0.category == .loot }
    }

    @Test("The entry editor's name and content reach the database and the game copy")
    func entryEditorEdit() async throws {
        let fixture = try await makeFixture()

        fixture.root.editController.update(itemId: fixture.itemId, entryId: fixture.entryId, name: "2", content: "Silver", forceSave: true)

        try await fixture.expectEdit { table in
            table.entries.first { $0.id == fixture.entryId }.map { $0.name == "2" && $0.content == "Silver" } ?? false
        }
    }

    @Test("The sheet editor adds, duplicates, moves and removes entries in the database and the game copy")
    func sheetEditorEntryOperations() async throws {
        let fixture = try await makeFixture()
        let sheet = try #require(fixture.root.editController.editorModel.sheetRootModel)
        sheet.reset(itemId: fixture.itemId)

        let addedId = try #require(sheet.addNewEntry(in: sheet.sheetModel))
        try await fixture.expectEdit { $0.entries.map(\.id) == [fixture.entryId, addedId] }

        let original = try #require(sheet.sheetModel.entries.first { $0.source.entryId == fixture.entryId })
        sheet.duplicateEntry(entryModel: original, in: sheet.sheetModel)
        try await fixture.expectEdit { $0.entries.count == 3 && $0.entries.filter { $0.content == "Gold" }.count == 2 }

        let added = try #require(sheet.sheetModel.entries.first { $0.source.entryId == addedId })
        let positionBefore = try #require(fixture.game.game(fixture.itemId)?.entries.firstIndex { $0.id == addedId })
        sheet.moveEntry(entryModel: added, in: sheet.sheetModel, up: true)
        let order = try #require(fixture.game.game(fixture.itemId)).entries.map(\.id)
        #expect(order.firstIndex(of: addedId) == positionBefore - 1, "the added entry moved one up")
        try await fixture.expectEdit { $0.entries.map(\.id) == order }

        let removed = try #require(sheet.sheetModel.entries.first { $0.source.entryId == fixture.entryId })
        sheet.removeEntry(entryModel: removed, from: sheet.sheetModel)
        try await fixture.expectEdit { $0.entries.count == 2 && !$0.entries.contains { $0.id == fixture.entryId } }
    }

    @Test("The quick entry editor's replaced entries reach the database and the game copy")
    func quickEntryEditorMerge() async throws {
        let fixture = try await makeFixture()
        let entries = [
            TableEntryModel(id: fixture.entryId, name: "1", content: "Gold"),
            TableEntryModel(id: UUID(), name: "2", content: "Gems")
        ]

        let blocked = fixture.root.editController.merge(itemId: fixture.itemId, entries: entries, recoverEntries: nil, forceSave: true)

        #expect(blocked.isEmpty)
        try await fixture.expectEdit { $0.entries.map(\.content) == ["Gold", "Gems"] }
    }

    @Test("The selected dice reach the database and the game copy")
    func diceSelection() async throws {
        let fixture = try await makeFixture()
        let diceId = UUID()

        fixture.root.editController.add(diceId: diceId, itemId: fixture.itemId, forceSave: true)

        try await fixture.expectEdit { $0.diceId == diceId }
    }

    @Test("Undo and redo of an editor edit change the database and the game copy")
    func undoAndRedo() async throws {
        let fixture = try await makeFixture()
        fixture.root.editController.update(id: fixture.itemId, name: "Dragon Hoard", description: nil, category: nil, tags: nil, forceSave: true)

        fixture.root.editController.undo()
        try await fixture.expectEdit { $0.name == "Loot" }

        fixture.root.editController.redo()
        try await fixture.expectEdit { $0.name == "Dragon Hoard" }
    }

    @Test("An edit of a table the game has not loaded reaches the database and makes no game copy")
    func editOfTableNotInGame() async throws {
        let fixture = try await makeFixture(loaded: false)

        fixture.root.editController.update(id: fixture.itemId, name: "Dragon Hoard", description: nil, category: nil, tags: nil, forceSave: true)
        fixture.root.editController.add(diceId: UUID(), itemId: fixture.itemId, forceSave: true)

        try await fixture.game.expectLibraryEditWithoutGameCopy(fixture.itemId) { $0.name == "Dragon Hoard" && $0.diceId != nil }
    }

    @Test("Without the editor, an in-game edit stays in game memory")
    func inGameEditStaysInGameMemory() async throws {
        let fixture = try await makeFixture()

        fixture.root.editController.update(id: fixture.itemId, name: "Session name", description: nil, category: nil, tags: nil, forceSave: false)
        fixture.root.editController.add(diceId: UUID(), itemId: fixture.itemId, forceSave: false)

        try await fixture.game.expectGameOnly(fixture.itemId) { $0.name == "Session name" }
        try await fixture.game.expectGameOnly(fixture.itemId) { $0.diceId != nil }
    }
}
#endif
