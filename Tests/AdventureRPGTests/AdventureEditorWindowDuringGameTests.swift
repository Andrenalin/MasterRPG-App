// @copyright André Trettin

#if canImport(Testing)
@testable import CoreRPG
import Foundation
import Testing

@testable import AdventureRPG

/// The editor window (macOS, iPad, visionOS) stays open while a game runs. Every edit it makes
/// reaches the database, and the game's in-memory copy of a loaded adventure shows it too, while
/// a change only the game copy has (here its description) stays out of the library.
@Suite("Adventure editor window during a game", .serialized)
@MainActor
struct AdventureEditorWindowDuringGameTests {
    private static let libraryDescription = "Library description"
    private static let sessionDescription = "Session description"

    @MainActor
    private struct Fixture {
        let store: GameEditorStore
        let root: AdventureRootModel
        let itemId: UUID
        let entryId: UUID

        var game: GameEditorHarness<ItemController> { GameEditorHarness(itemController: root.itemController) }

        func expectEdit(sourceLocation: SourceLocation = #_sourceLocation, _ isEdited: (AdventureModel) -> Bool) async throws {
            try await game.expectEdit(
                itemId,
                libraryDescription: AdventureEditorWindowDuringGameTests.libraryDescription,
                sessionDescription: AdventureEditorWindowDuringGameTests.sessionDescription,
                sourceLocation: sourceLocation,
                isEdited
            )
        }

        /// The editor window's sheet editor, showing the adventure.
        func sheet() throws -> SheetRootModel {
            let sheet = try #require(root.editController.editorModel.sheetRootModel)
            sheet.reset(itemId: itemId)
            return sheet
        }
    }

    /// An adventure with one scene in the library and the database, a running game and, when
    /// `loaded`, the adventure in game memory with a change of its own.
    private func makeFixture(loaded: Bool = true) async throws -> Fixture {
        let root = try await MockRoot.importTestData()
        await root.itemController.resetData()
        let store = try GameEditorStore(bundles: [CoreRPG.Resources.bundle, AdventureRPG.Resources.bundle])
        root.itemController.itemDataModel.dataController = DataController(context: store.context, token: NetworkModules.adventure.token)
        let itemId = await root.itemController.addNew(type: .adventure)
        root.editController.update(id: itemId, name: "Journey", description: Self.libraryDescription, category: nil, tags: ["campaign"])
        let entryId = root.editController.addNewEntry(itemId: itemId)
        root.editController.update(itemId: itemId, entryId: entryId, name: "Arrival", content: "Open the gate", forceSave: false)

        let fixture = Fixture(store: store, root: root, itemId: itemId, entryId: entryId)
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

        fixture.root.editController.update(id: fixture.itemId, name: "Odyssey", description: nil, category: .campaign, tags: ["campaign", "sea"], forceSave: true)

        try await fixture.expectEdit { $0.name == "Odyssey" && $0.tags == ["campaign", "sea"] && $0.category == .campaign }
    }

    @Test("The entry editor's name and content reach the database and the game copy")
    func entryEditorEdit() async throws {
        let fixture = try await makeFixture()

        fixture.root.editController.update(itemId: fixture.itemId, entryId: fixture.entryId, name: "Departure", content: "Close the gate", forceSave: true)

        try await fixture.expectEdit { adventure in
            adventure.entries.first { $0.id == fixture.entryId }.map { $0.name == "Departure" && $0.content == "Close the gate" } ?? false
        }
    }

    @Test("The sheet editor adds, duplicates, moves and removes scenes in the database and the game copy")
    func sheetEditorEntryOperations() async throws {
        let fixture = try await makeFixture()
        let sheet = try fixture.sheet()

        let addedId = try #require(sheet.addNewEntry(in: sheet.sheetModel))
        try await fixture.expectEdit { $0.entries.map(\.id) == [fixture.entryId, addedId] }

        let original = try #require(sheet.sheetModel.entries.first { $0.source.entryId == fixture.entryId })
        sheet.duplicateEntry(entryModel: original, in: sheet.sheetModel)
        try await fixture.expectEdit { $0.entries.count == 3 && $0.entries.filter { $0.content == "Open the gate" }.count == 2 }

        let added = try #require(sheet.sheetModel.entries.first { $0.source.entryId == addedId })
        let positionBefore = try #require(fixture.game.game(fixture.itemId)?.entries.firstIndex { $0.id == addedId })
        sheet.moveEntry(entryModel: added, in: sheet.sheetModel, up: true)
        let order = try #require(fixture.game.game(fixture.itemId)).entries.map(\.id)
        #expect(order.firstIndex(of: addedId) == positionBefore - 1, "the added scene moved one up")
        try await fixture.expectEdit { $0.entries.map(\.id) == order }

        let removed = try #require(sheet.sheetModel.entries.first { $0.source.entryId == fixture.entryId })
        sheet.removeEntry(entryModel: removed, from: sheet.sheetModel)
        try await fixture.expectEdit { $0.entries.count == 2 && !$0.entries.contains { $0.id == fixture.entryId } }
    }

    @Test("A link added in the sheet editor reaches the database and the game copy")
    func sheetEditorLink() async throws {
        let fixture = try await makeFixture()
        let sheet = try fixture.sheet()
        let entry = try #require(sheet.sheetModel.entries.first { $0.source.entryId == fixture.entryId })

        sheet.addLink(link: "Harbor", module: .map, itemId: UUID(), entryId: nil, to: entry, in: sheet.sheetModel)

        try await fixture.expectEdit { adventure in
            adventure.entries.first { $0.id == fixture.entryId }?.content.contains("Harbor") ?? false
        }
    }

    @Test("A group added and an entry converted to a group in the sheet editor reach the database")
    func sheetEditorGroups() async throws {
        let fixture = try await makeFixture()
        let sheet = try fixture.sheet()

        let groupEntryId = try #require(await sheet.addNewGroup(in: sheet.sheetModel))
        try await fixture.expectEdit { adventure in
            adventure.entries.contains { $0.id == groupEntryId && $0.adventureId != nil }
        }
        let addedGroupId = try #require(fixture.game.library(fixture.itemId)?.entries.first { $0.id == groupEntryId }?.adventureId)
        #expect(try await fixture.game.stored(addedGroupId)?.groupId == fixture.itemId)

        _ = await sheet.convertEntryToGroup(source: ItemRowModel(itemId: fixture.itemId, entryId: fixture.entryId, typeId: .adventure), existingItemId: nil)
        try await fixture.expectEdit { adventure in
            adventure.entries.contains { $0.id == fixture.entryId && $0.adventureId != nil }
        }
        let convertedGroupId = try #require(fixture.game.library(fixture.itemId)?.entries.first { $0.id == fixture.entryId }?.adventureId)
        let convertedGroup = try #require(try await fixture.game.stored(convertedGroupId))
        #expect(convertedGroup.groupId == fixture.itemId)
        #expect(convertedGroup.name == "Arrival")
    }

    @Test("The quick entry editor's replaced scenes reach the database and the game copy")
    func quickEntryEditorMerge() async throws {
        let fixture = try await makeFixture()
        let entries = [
            AdventureEntryModel(id: fixture.entryId, name: "Arrival", content: "Open the gate"),
            AdventureEntryModel(id: UUID(), name: "Twist", content: "The key is gone")
        ]

        let blocked = fixture.root.editController.merge(itemId: fixture.itemId, entries: entries, recoverEntries: nil, forceSave: true)

        #expect(blocked.isEmpty)
        try await fixture.expectEdit { $0.entries.map(\.name) == ["Arrival", "Twist"] }
    }

    @Test("The selected dice and photo reach the database and the game copy")
    func diceAndPhotoSelection() async throws {
        let fixture = try await makeFixture()
        let diceId = UUID()
        let photoId = UUID()

        fixture.root.editController.add(diceId: diceId, itemId: fixture.itemId, forceSave: true)
        fixture.root.editController.add(photoId: photoId, itemId: fixture.itemId, forceSave: true)

        try await fixture.expectEdit { $0.diceId == diceId && $0.photoId == photoId }
    }

    @Test("Undo and redo of an editor edit change the database and the game copy")
    func undoAndRedo() async throws {
        let fixture = try await makeFixture()
        let photoId = UUID()
        fixture.root.editController.add(photoId: photoId, itemId: fixture.itemId, forceSave: true)

        fixture.root.editController.undo()
        try await fixture.expectEdit { $0.photoId == nil }

        fixture.root.editController.redo()
        try await fixture.expectEdit { $0.photoId == photoId }
    }

    @Test("An edit of an adventure the game has not loaded reaches the database and makes no game copy")
    func editOfAdventureNotInGame() async throws {
        let fixture = try await makeFixture(loaded: false)
        let diceId = UUID()

        fixture.root.editController.update(id: fixture.itemId, name: "Odyssey", description: nil, category: nil, tags: nil, forceSave: true)
        fixture.root.editController.add(diceId: diceId, itemId: fixture.itemId, forceSave: true)

        try await fixture.game.expectLibraryEditWithoutGameCopy(fixture.itemId) { $0.name == "Odyssey" && $0.diceId == diceId }
    }

    @Test("Without the editor, an in-game edit stays in game memory")
    func inGameEditStaysInGameMemory() async throws {
        let fixture = try await makeFixture()

        fixture.root.editController.update(id: fixture.itemId, name: "Session name", description: nil, category: nil, tags: nil)
        fixture.root.editController.add(photoId: UUID(), itemId: fixture.itemId)

        try await fixture.game.expectGameOnly(fixture.itemId) { $0.name == "Session name" }
        try await fixture.game.expectGameOnly(fixture.itemId) { $0.photoId != nil }
    }
}
#endif
