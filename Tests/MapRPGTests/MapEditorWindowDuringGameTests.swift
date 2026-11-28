// @copyright André Trettin

#if canImport(Testing)
@testable import CoreRPG
import Foundation
import SwiftUI
import Testing

@testable import MapRPG

/// The editor window (macOS, iPad, visionOS) stays open while a game runs. A map's metadata
/// (name, description, category, tags) edited there reaches the database and the game copy. Its
/// content (rooms, links, pins, border, cover, tiles, photo) is what the players see: it changes
/// the game copy only and stays out of the library until the game ends.
@Suite("Map editor window during a game", .serialized)
@MainActor
struct MapEditorWindowDuringGameTests {
    private static let libraryDescription = "Library description"
    private static let sessionDescription = "Session description"

    @MainActor
    private struct Fixture {
        let store: GameEditorStore
        let root: MapRootModel
        let itemId: UUID
        let roomId: UUID

        var game: GameEditorHarness<ItemController> { GameEditorHarness(itemController: root.itemController) }

        func expectEdit(sourceLocation: SourceLocation = #_sourceLocation, _ isEdited: (MapModel) -> Bool) async throws {
            try await game.expectEdit(
                itemId,
                libraryDescription: MapEditorWindowDuringGameTests.libraryDescription,
                sessionDescription: MapEditorWindowDuringGameTests.sessionDescription,
                sourceLocation: sourceLocation,
                isEdited
            )
        }

        func room(of map: MapModel) -> MapEntryModel? {
            map.entries.first { $0.id == roomId }
        }
    }

    /// A map with one room in the library and the database, a running game and, when `loaded`,
    /// the map in game memory with a change of its own.
    private func makeFixture(loaded: Bool = true) async throws -> Fixture {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let store = try GameEditorStore(bundles: [CoreRPG.Resources.bundle, MapRPG.Resources.bundle])
        root.itemController.itemDataModel.dataController = DataController(context: store.context, token: NetworkModules.map.token)
        let itemId = await root.itemController.addNew(type: .item)
        root.editController.update(id: itemId, name: "Cellar", description: Self.libraryDescription, category: nil, tags: ["dungeon"])
        let roomId = UUID()
        _ = root.editController.merge(itemId: itemId, entries: [MapEntryModel(id: roomId, name: "Vault", content: "Dusty", coordinates: [])], recoverEntries: nil, forceSave: false)

        let fixture = Fixture(store: store, root: root, itemId: itemId, roomId: roomId)
        fixture.game.startGame()
        if loaded {
            fixture.game.loadIntoGame(itemId) { $0.description = Self.sessionDescription }
        }
        // Selecting the item in the editor starts its undo history.
        root.editController.editorModel.undoManaged.resetValue(root.editController.editModel(for: itemId))
        return fixture
    }

    // MARK: Metadata persists

    @Test("The header editor's name, tags and category reach the database and the game copy")
    func headerEdit() async throws {
        let fixture = try await makeFixture()

        fixture.root.editController.update(id: fixture.itemId, name: "Wine Cellar", description: nil, category: .dungeon, tags: ["dungeon", "wine"], forceSave: true)

        try await fixture.expectEdit { $0.name == "Wine Cellar" && $0.tags == ["dungeon", "wine"] && $0.category == .dungeon }
    }

    @Test("Undo and redo of a header edit change the database and the game copy")
    func undoAndRedo() async throws {
        let fixture = try await makeFixture()
        fixture.root.editController.update(id: fixture.itemId, name: "Wine Cellar", description: nil, category: nil, tags: nil, forceSave: true)

        fixture.root.editController.undo()
        try await fixture.expectEdit { $0.name == "Cellar" }

        fixture.root.editController.redo()
        try await fixture.expectEdit { $0.name == "Wine Cellar" }
    }

    @Test("A header edit of a map the game has not loaded reaches the database and makes no game copy")
    func headerEditOfMapNotInGame() async throws {
        let fixture = try await makeFixture(loaded: false)

        fixture.root.editController.update(id: fixture.itemId, name: "Wine Cellar", description: nil, category: nil, tags: nil, forceSave: true)

        try await fixture.game.expectLibraryEditWithoutGameCopy(fixture.itemId) { $0.name == "Wine Cellar" }
    }

    @Test("A header edit keeps the game copy's content edits")
    func headerEditKeepsGameContent() async throws {
        let fixture = try await makeFixture()
        fixture.root.editController.reset(hasBorder: true, itemId: fixture.itemId)

        fixture.root.editController.update(id: fixture.itemId, name: "Wine Cellar", description: nil, category: nil, tags: nil, forceSave: true)

        try await fixture.expectEdit { $0.name == "Wine Cellar" }
        try await fixture.game.expectGameOnly(fixture.itemId) { $0.displayConfig.hasBorder }
    }

    // MARK: Content stays in game memory

    @Test("Rooms replaced in the quick entry editor change only the game copy")
    func roomMergeStaysInGame() async throws {
        let fixture = try await makeFixture()
        let rooms = [
            MapEntryModel(id: fixture.roomId, name: "Vault", content: "Looted", coordinates: []),
            MapEntryModel(id: UUID(), name: "Crypt", content: "", coordinates: [])
        ]

        _ = fixture.root.editController.merge(itemId: fixture.itemId, entries: rooms, recoverEntries: nil, forceSave: true)

        try await fixture.game.expectGameOnly(fixture.itemId) { $0.entries.map(\.name) == ["Vault", "Crypt"] }
        try await fixture.game.expectGameOnly(fixture.itemId) { fixture.room(of: $0)?.content == "Looted" }
    }

    @Test("A link dropped on a room changes only the game copy")
    func roomLinkStaysInGame() async throws {
        let fixture = try await makeFixture()

        fixture.root.editController.add(link: "Rats", module: .table, itemId: UUID(), entryId: nil, destinationItemId: fixture.itemId, destinationEntryId: fixture.roomId, forceSave: true)

        try await fixture.game.expectGameOnly(fixture.itemId) { fixture.room(of: $0)?.content.contains("Rats") ?? false }
    }

    @Test("A pin added in the editor changes only the game copy")
    func pinStaysInGame() async throws {
        let fixture = try await makeFixture()
        let map = try #require(fixture.root.editController.editModel(for: fixture.itemId))
        let pinId = UUID()

        fixture.root.editController.add(pin: MapPinModel(id: pinId, name: "Chest"), to: map)

        try await fixture.game.expectGameOnly(fixture.itemId) { $0.mapPins.contains { $0.id == pinId } }
    }

    @Test("Border, cover, tiles and photo set in the editor change only the game copy")
    func displayConfigStaysInGame() async throws {
        let fixture = try await makeFixture()
        let tiles = [CGPoint(x: 1, y: 2)]
        let photoId = UUID()

        fixture.root.editController.reset(hasBorder: true, itemId: fixture.itemId)
        fixture.root.editController.reset(borderThickness: 7, itemId: fixture.itemId)
        fixture.root.editController.reset(tileCoordinates: tiles, itemId: fixture.itemId)
        fixture.root.editController.add(photoId: photoId, itemId: fixture.itemId)

        try await fixture.game.expectGameOnly(fixture.itemId) { $0.displayConfig.hasBorder }
        try await fixture.game.expectGameOnly(fixture.itemId) { $0.displayConfig.borderThickness == 7 }
        try await fixture.game.expectGameOnly(fixture.itemId) { $0.displayConfig.tileCoordinates == tiles }
        try await fixture.game.expectGameOnly(fixture.itemId) { $0.photoId == photoId }
    }
}
#endif
