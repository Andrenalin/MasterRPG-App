// @copyright André Trettin

#if canImport(Testing)
@testable import CoreRPG
import Foundation
import Testing

@testable import RuleRPG

/// The editor window (macOS, iPad, visionOS) stays open while a game runs. Every edit it makes
/// reaches the database, and the game's in-memory copy of a loaded rule shows it too, while a
/// change only the game copy has (here its description) stays out of the library.
@Suite("Rule editor window during a game")
@MainActor
struct RuleEditorWindowDuringGameTests {
    private static let libraryDescription = "Library description"
    private static let sessionDescription = "Session description"

    @MainActor
    private struct Fixture {
        let store: GameEditorStore
        let root: RuleRootModel
        let itemId: UUID
        let entryId: UUID

        var game: GameEditorHarness<ItemController> { GameEditorHarness(itemController: root.itemController) }

        func expectEdit(sourceLocation: SourceLocation = #_sourceLocation, _ isEdited: (RuleModel) -> Bool) async throws {
            try await game.expectEdit(
                itemId,
                libraryDescription: RuleEditorWindowDuringGameTests.libraryDescription,
                sessionDescription: RuleEditorWindowDuringGameTests.sessionDescription,
                sourceLocation: sourceLocation,
                isEdited
            )
        }
    }

    /// A rule with one section in the library and the database, a running game and, when
    /// `loaded`, the rule in game memory with a change of its own.
    private func makeFixture(loaded: Bool = true) async throws -> Fixture {
        let store = try GameEditorStore(bundles: [CoreRPG.Resources.bundle, RuleRPG.Resources.bundle])
        let root = RuleRootModel.testRoot()
        root.itemController.itemDataModel.dataController = DataController(context: store.context, token: NetworkModules.rule.token)
        let itemId = await root.itemController.addNew(type: .item)
        root.editController.update(id: itemId, name: "Fireball", description: Self.libraryDescription, category: nil, tags: ["spell"])
        let entryId = root.editController.addNewEntry(itemId: itemId)
        root.editController.update(itemId: itemId, entryId: entryId, name: "Damage", content: "3d6", forceSave: false)

        let fixture = Fixture(store: store, root: root, itemId: itemId, entryId: entryId)
        fixture.game.startGame()
        if loaded {
            fixture.game.loadIntoGame(itemId) { $0.description = Self.sessionDescription }
        }
        // Selecting the item in the editor starts its undo history.
        root.editController.editorModel.undoManaged.resetValue(root.editController.editModel(for: itemId))
        return fixture
    }

    @Test("The header editor's name and tags reach the database and the game copy")
    func headerEdit() async throws {
        let fixture = try await makeFixture()

        fixture.root.editController.update(id: fixture.itemId, name: "Greater Fireball", description: nil, category: nil, tags: ["fire", "spell"], forceSave: true)

        try await fixture.expectEdit { $0.name == "Greater Fireball" && $0.tags == ["fire", "spell"] }
    }

    @Test("The entry editor's name and content reach the database and the game copy")
    func entryEditorEdit() async throws {
        let fixture = try await makeFixture()

        fixture.root.editController.update(itemId: fixture.itemId, entryId: fixture.entryId, name: "Area", content: "6 m", forceSave: true)

        try await fixture.expectEdit { rule in
            rule.entries.first { $0.id == fixture.entryId }.map { $0.name == "Area" && $0.content == "6 m" } ?? false
        }
    }

    @Test("The sheet editor adds, duplicates, moves and removes sections in the database and the game copy")
    func sheetEditorEntryOperations() async throws {
        let fixture = try await makeFixture()
        let sheet = try #require(fixture.root.editController.editorModel.sheetRootModel)
        sheet.reset(itemId: fixture.itemId)

        let addedId = try #require(sheet.addNewEntry(in: sheet.sheetModel))
        try await fixture.expectEdit { $0.entries.map(\.id) == [fixture.entryId, addedId] }

        let original = try #require(sheet.sheetModel.entries.first { $0.source.entryId == fixture.entryId })
        sheet.duplicateEntry(entryModel: original, in: sheet.sheetModel)
        try await fixture.expectEdit { $0.entries.count == 3 && $0.entries.filter { $0.content == "3d6" }.count == 2 }

        let added = try #require(sheet.sheetModel.entries.first { $0.source.entryId == addedId })
        let positionBefore = try #require(fixture.game.game(fixture.itemId)?.entries.firstIndex { $0.id == addedId })
        sheet.moveEntry(entryModel: added, in: sheet.sheetModel, up: true)
        let order = try #require(fixture.game.game(fixture.itemId)).entries.map(\.id)
        #expect(order.firstIndex(of: addedId) == positionBefore - 1, "the added section moved one up")
        try await fixture.expectEdit { $0.entries.map(\.id) == order }

        let removed = try #require(sheet.sheetModel.entries.first { $0.source.entryId == fixture.entryId })
        sheet.removeEntry(entryModel: removed, from: sheet.sheetModel)
        try await fixture.expectEdit { $0.entries.count == 2 && !$0.entries.contains { $0.id == fixture.entryId } }
    }

    @Test("The quick entry editor's replaced sections reach the database and the game copy")
    func quickEntryEditorMerge() async throws {
        let fixture = try await makeFixture()
        let entries = [
            RuleEntryModel(id: fixture.entryId, name: "Damage", content: "3d6"),
            RuleEntryModel(id: UUID(), name: "Range", content: "30 m")
        ]

        let blocked = fixture.root.editController.merge(itemId: fixture.itemId, entries: entries, recoverEntries: nil, forceSave: true)

        #expect(blocked.isEmpty)
        try await fixture.expectEdit { $0.entries.map(\.name) == ["Damage", "Range"] }
    }

    @Test("The source metadata editor reaches the database and the game copy")
    func sourceMetadata() async throws {
        let fixture = try await makeFixture()
        let metadata = RuleSourceMetadata(systemTitle: "Dungeon Slayers", packageName: "Spells")

        fixture.root.editController.reset(sourceMetadata: metadata, itemId: fixture.itemId, forceSave: true)

        try await fixture.expectEdit { $0.sourceMetadata == metadata }
    }

    @Test("Undo and redo of an editor edit change the database and the game copy")
    func undoAndRedo() async throws {
        let fixture = try await makeFixture()
        let metadata = RuleSourceMetadata(systemTitle: "Dungeon Slayers")
        fixture.root.editController.reset(sourceMetadata: metadata, itemId: fixture.itemId, forceSave: true)

        fixture.root.editController.undo()
        try await fixture.expectEdit { $0.sourceMetadata != metadata }

        fixture.root.editController.redo()
        try await fixture.expectEdit { $0.sourceMetadata == metadata }
    }

    @Test("An edit of a rule the game has not loaded reaches the database and makes no game copy")
    func editOfRuleNotInGame() async throws {
        let fixture = try await makeFixture(loaded: false)

        fixture.root.editController.update(id: fixture.itemId, name: "Greater Fireball", description: nil, category: nil, tags: nil, forceSave: true)

        try await fixture.game.expectLibraryEditWithoutGameCopy(fixture.itemId) { $0.name == "Greater Fireball" }
    }

    @Test("Without the editor, an in-game edit stays in game memory")
    func inGameEditStaysInGameMemory() async throws {
        let fixture = try await makeFixture()

        fixture.root.editController.update(itemId: fixture.itemId, entryId: fixture.entryId, name: "Damage", content: "4d6", forceSave: false)

        try await fixture.game.expectGameOnly(fixture.itemId) { $0.entries.first?.content == "4d6" }
    }
}
#endif
