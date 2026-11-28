// @copyright André Trettin

#if canImport(Testing)
@testable import CoreRPG
import DiceRPG
import Foundation
import PdfRPG
import PhotoRPG
import TableRPG
import Testing

@testable import CharacterRPG

/// The editor window (macOS, iPad, visionOS) stays open while a game runs. Every edit it makes
/// reaches the database, and the game's in-memory copy of a loaded character shows it too, while
/// a change only the game copy has (here its description) stays out of the library.
@Suite("Character editor window during a game")
@MainActor
struct CharacterEditorWindowDuringGameTests {
    private static let libraryDescription = "Library description"
    private static let sessionDescription = "Session description"

    @MainActor
    private struct Fixture {
        let store: GameEditorStore
        let root: CharacterRootModel
        let itemId: UUID
        let entryId: UUID

        var game: GameEditorHarness<ItemController> { GameEditorHarness(itemController: root.itemController) }

        func expectEdit(sourceLocation: SourceLocation = #_sourceLocation, _ isEdited: (ValueModel) -> Bool) async throws {
            try await game.expectEdit(
                itemId,
                libraryDescription: CharacterEditorWindowDuringGameTests.libraryDescription,
                sessionDescription: CharacterEditorWindowDuringGameTests.sessionDescription,
                sourceLocation: sourceLocation,
                isEdited
            )
        }

        func entry(of character: ValueModel) -> ValueEntryModel? {
            character.entries.first { $0.id == entryId }
        }

        /// The editor window's sheet editor, showing the character.
        func sheet() throws -> SheetRootModel {
            let sheet = try #require(root.editController.editorModel.sheetRootModel)
            sheet.reset(itemId: itemId)
            return sheet
        }
    }

    /// A character with one text value in the library and the database, a running game and,
    /// when `loaded`, the character in game memory with a change of its own.
    private func makeFixture(loaded: Bool = true) async throws -> Fixture {
        let diceRoot = DiceRootModel.testRoot()
        let pdfRoot = PdfRootModel.testRoot()
        let root = CharacterRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: PhotoRootModel.testRoot(), tableRoot: TableRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot))
        let store = try GameEditorStore(bundles: [CoreRPG.Resources.bundle, CharacterRPG.Resources.bundle])
        root.itemController.itemDataModel.dataController = DataController(context: store.context, token: NetworkModules.value.token)
        let itemId = await root.itemController.addNew(type: .item)
        root.editController.update(id: itemId, name: "Aria", description: Self.libraryDescription, category: nil, tags: ["hero"])
        let entry = ValueEntryModel(id: UUID(), name: "Notes", type: .text, value: "Brave")
        root.editController.add(entry: entry, itemId: itemId)

        let fixture = Fixture(store: store, root: root, itemId: itemId, entryId: entry.id)
        fixture.game.startGame()
        if loaded {
            fixture.game.loadIntoGame(itemId) { $0.description = Self.sessionDescription }
        }
        // Selecting the item in the editor starts its undo history.
        root.editController.editorModel.undoManaged.resetValue(root.editController.editModel(for: itemId))
        return fixture
    }

    @Test("The header editor's name, tags and category reach the database and the game copy")
    func headerEdit() async throws {
        let fixture = try await makeFixture()

        fixture.root.editController.update(id: fixture.itemId, name: "Aria the Bold", description: nil, category: .monster, tags: ["hero", "ranger"], forceSave: true)

        try await fixture.expectEdit { $0.name == "Aria the Bold" && $0.tags == ["hero", "ranger"] && $0.category == .monster }
    }

    @Test("The entry editor's name and value reach the database and the game copy")
    func entryEditorEdit() async throws {
        let fixture = try await makeFixture()

        fixture.root.editController.update(itemId: fixture.itemId, entryId: fixture.entryId, name: "Traits", content: "Curious", forceSave: true)

        try await fixture.expectEdit { fixture.entry(of: $0).map { $0.name == "Traits" && $0.value == "Curious" } ?? false }
    }

    @Test("The sheet editor adds, duplicates, moves and removes values in the database and the game copy")
    func sheetEditorEntryOperations() async throws {
        let fixture = try await makeFixture()
        let sheet = try fixture.sheet()

        let addedId = try #require(sheet.addNewEntry(in: sheet.sheetModel))
        try await fixture.expectEdit { $0.entries.map(\.id) == [fixture.entryId, addedId] }

        let original = try #require(sheet.sheetModel.entries.first { $0.source.entryId == fixture.entryId })
        sheet.duplicateEntry(entryModel: original, in: sheet.sheetModel)
        try await fixture.expectEdit { $0.entries.count == 3 && $0.entries.filter { $0.value == "Brave" }.count == 2 }

        let added = try #require(sheet.sheetModel.entries.first { $0.source.entryId == addedId })
        let positionBefore = try #require(fixture.game.game(fixture.itemId)?.entries.firstIndex { $0.id == addedId })
        sheet.moveEntry(entryModel: added, in: sheet.sheetModel, up: true)
        let order = try #require(fixture.game.game(fixture.itemId)).entries.map(\.id)
        #expect(order.firstIndex(of: addedId) == positionBefore - 1, "the added value moved one up")
        try await fixture.expectEdit { $0.entries.map(\.id) == order }

        let removed = try #require(sheet.sheetModel.entries.first { $0.source.entryId == fixture.entryId })
        sheet.removeEntry(entryModel: removed, from: sheet.sheetModel)
        try await fixture.expectEdit { $0.entries.count == 2 && !$0.entries.contains { $0.id == fixture.entryId } }
    }

    @Test("A value type changed in the sheet editor reaches the database and the game copy")
    func sheetEditorValueType() async throws {
        let fixture = try await makeFixture()
        let sheet = try fixture.sheet()
        let entry = try #require(sheet.sheetModel.entries.first { $0.source.entryId == fixture.entryId })

        sheet.updateEditType(.number, for: entry, parent: sheet.sheetModel)

        try await fixture.expectEdit { fixture.entry(of: $0)?.type == .number }
    }

    @Test("A dice linked in the sheet editor and removed again reaches the database and the game copy")
    func sheetEditorDiceLink() async throws {
        let fixture = try await makeFixture()
        let sheet = try fixture.sheet()
        let entry = try #require(sheet.sheetModel.entries.first { $0.source.entryId == fixture.entryId })
        let diceId = UUID()

        sheet.addLink(link: "d20", module: .dice, itemId: diceId, entryId: nil, to: entry, in: sheet.sheetModel)
        try await fixture.expectEdit { fixture.entry(of: $0).map { $0.diceId == diceId && $0.type == .number } ?? false }

        // The remove button next to the dice row of the sheet editor.
        fixture.root.editController.removeDice(itemId: fixture.itemId, entryId: fixture.entryId, forceSave: true)
        try await fixture.expectEdit { fixture.entry(of: $0)?.diceId == nil }
    }

    @Test("A value linked in the sheet editor reaches the database and the game copy")
    func sheetEditorValueLink() async throws {
        let fixture = try await makeFixture()
        let sheet = try fixture.sheet()
        let entry = try #require(sheet.sheetModel.entries.first { $0.source.entryId == fixture.entryId })

        sheet.addLink(link: "Strength", module: .value, itemId: UUID(), entryId: UUID(), to: entry, in: sheet.sheetModel)

        try await fixture.expectEdit { fixture.entry(of: $0)?.value.contains("Strength") ?? false }
    }

    @Test("A group added and a value converted to a group in the sheet editor reach the database")
    func sheetEditorGroups() async throws {
        let fixture = try await makeFixture()
        let sheet = try fixture.sheet()

        let groupEntryId = try #require(await sheet.addNewGroup(in: sheet.sheetModel))
        try await fixture.expectEdit { $0.entries.contains { $0.id == groupEntryId && $0.valueId != nil } }
        let addedGroupId = try #require(fixture.game.library(fixture.itemId)?.entries.first { $0.id == groupEntryId }?.valueId)
        #expect(try await fixture.game.stored(addedGroupId)?.groupId == fixture.itemId)

        _ = await sheet.convertEntryToGroup(source: ItemRowModel(itemId: fixture.itemId, entryId: fixture.entryId, typeId: .value), existingItemId: nil)
        try await fixture.expectEdit { fixture.entry(of: $0)?.valueId != nil }
        let convertedGroupId = try #require(fixture.game.library(fixture.itemId).flatMap { fixture.entry(of: $0)?.valueId })
        #expect(try await fixture.game.stored(convertedGroupId)?.groupId == fixture.itemId)
    }

    @Test("A character moved into another from the list reaches the database and the game copy")
    func listMoveIntoGroup() async throws {
        let fixture = try await makeFixture()
        let movedId = await fixture.root.itemController.addNew(type: .item)
        fixture.root.editController.reset(name: "Wolf", itemId: movedId, forceSave: true)

        let groupEntryId = try #require(fixture.root.editController.moveIntoGroup(itemId: movedId, into: fixture.itemId, forceSave: true))

        try await fixture.expectEdit { $0.entries.contains { $0.id == groupEntryId && $0.valueId == movedId } }
        try await fixture.game.expectLibraryEditWithoutGameCopy(movedId) { $0.groupId == fixture.itemId }
    }

    @Test("The quick entry editor's replaced values reach the database and the game copy")
    func quickEntryEditorMerge() async throws {
        let fixture = try await makeFixture()
        let entries = [
            ValueEntryModel(id: fixture.entryId, name: "Notes", type: .text, value: "Brave"),
            ValueEntryModel(id: UUID(), name: "Level", type: .number, value: "3")
        ]

        let blocked = fixture.root.editController.merge(itemId: fixture.itemId, entries: entries, recoverEntries: nil, forceSave: true)

        #expect(blocked.isEmpty)
        try await fixture.expectEdit { $0.entries.map(\.name) == ["Notes", "Level"] }
    }

    @Test("The selected photos and dice reach the database and the game copy")
    func photoAndDiceSelection() async throws {
        let fixture = try await makeFixture()
        let portraitId = UUID()
        let otherPhotoId = UUID()
        let diceId = UUID()

        fixture.root.editController.add(selection: [WindowItemSelection(itemId: portraitId), WindowItemSelection(itemId: otherPhotoId)], itemId: fixture.itemId, forceSave: true)
        fixture.root.editController.add(diceId: diceId, itemId: fixture.itemId, forceSave: true)

        try await fixture.expectEdit { $0.photoId == portraitId && $0.photos == [portraitId, otherPhotoId] && $0.diceId == diceId }
    }

    @Test("Undo and redo of an editor edit change the database and the game copy")
    func undoAndRedo() async throws {
        let fixture = try await makeFixture()
        fixture.root.editController.update(itemId: fixture.itemId, entryId: fixture.entryId, name: "Notes", content: "Curious", forceSave: true)

        fixture.root.editController.undo()
        try await fixture.expectEdit { fixture.entry(of: $0)?.value == "Brave" }

        fixture.root.editController.redo()
        try await fixture.expectEdit { fixture.entry(of: $0)?.value == "Curious" }
    }

    @Test("An edit of a character the game has not loaded reaches the database and makes no game copy")
    func editOfCharacterNotInGame() async throws {
        let fixture = try await makeFixture(loaded: false)
        let diceId = UUID()

        fixture.root.editController.update(id: fixture.itemId, name: "Aria the Bold", description: nil, category: nil, tags: nil, forceSave: true)
        fixture.root.editController.add(diceId: diceId, itemId: fixture.itemId, forceSave: true)

        try await fixture.game.expectLibraryEditWithoutGameCopy(fixture.itemId) { $0.name == "Aria the Bold" && $0.diceId == diceId }
    }

    @Test("Without the editor, an in-game edit stays in game memory")
    func inGameEditStaysInGameMemory() async throws {
        let fixture = try await makeFixture()

        fixture.root.editController.update(itemId: fixture.itemId, entryId: fixture.entryId, name: "Notes", content: "Scared", forceSave: false)
        fixture.root.editController.add(diceId: UUID(), itemId: fixture.itemId)

        try await fixture.game.expectGameOnly(fixture.itemId) { fixture.entry(of: $0)?.value == "Scared" }
        try await fixture.game.expectGameOnly(fixture.itemId) { $0.diceId != nil }
    }
}
#endif
