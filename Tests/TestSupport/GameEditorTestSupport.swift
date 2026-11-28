// @copyright André Trettin

import CoreData
import CoreRPG
import Foundation
import Testing

/// Shared by the "editor window during a game" suites of every module: the editor window (macOS,
/// iPad, visionOS) stays open while a game runs, and its edits must reach the database and the
/// game's in-memory copy of the item. Shared through the `Tests/TestSupport` folder.

/// An in-memory Core Data store a module root writes to, so a test reads back what reached the
/// database instead of only the in-memory library.
struct GameEditorStore {
    let container: NSPersistentContainer
    let context: NSManagedObjectContext

    @MainActor
    init(bundles: [Bundle]) throws {
        guard let model = NSManagedObjectModel.mergedModel(from: bundles) else {
            throw CocoaError(.coderReadCorrupt)
        }
        container = NSPersistentContainer(name: "GameEditorStore-\(UUID().uuidString)", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: (any Error)?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw loadError
        }
        context = container.newBackgroundContext()
    }
}

/// Drives one module's library and game memory like a running game does, and reads the three
/// places an editor-window edit must land: the library, the game copy and the database.
@MainActor
struct GameEditorHarness<Controller: ItemControllable> {
    let itemController: Controller

    /// What `AdventureRootModel.startGame()` does for every module.
    func startGame() {
        itemController.itemDataModel.isGameMode = true
    }

    /// Ends the game without the module's own reset (its game controller clears more).
    func endGame() {
        itemController.itemDataModel.gameItemData = [:]
        itemController.itemDataModel.resetGame()
    }

    /// Puts a session copy of `itemId` into game memory, as showing the item to the players does,
    /// and returns it. `sessionChange` changes only that copy: session state the library must
    /// not receive from an editor save.
    @discardableResult
    func loadIntoGame(_ itemId: UUID, sessionChange: (Controller.Model) -> Void = { _ in }) -> Controller.Model? {
        guard let library = itemController.itemSync(for: itemId, noGame: true) else { return nil }
        let copy = library.copy()
        sessionChange(copy)
        itemController.itemDataModel.gameItemData[itemId] = copy
        return copy
    }

    /// The library's (and so the list's and every new editor's) value.
    func library(_ itemId: UUID) -> Controller.Model? {
        itemController.itemSync(for: itemId, noGame: true)
    }

    /// The game's in-memory copy, `nil` when the item is not loaded into the game.
    func game(_ itemId: UUID) -> Controller.Model? {
        itemController.itemDataModel.gameItemData[itemId] as? Controller.Model
    }

    /// What the database holds for `itemId` once the pending writes are flushed and saved.
    func stored(_ itemId: UUID) async throws -> Controller.Model? {
        guard let dataControllable = itemController.dataControllable else { return nil }
        try await dataControllable.flushPendingOperations()
        try await dataControllable.save()
        return try await dataControllable.fetch(id: itemId) as? Controller.Model
    }

    /// An editor-window edit: the library, the database and the game copy all hold it, and the
    /// game copy keeps its own change (its description, see `loadIntoGame(_:sessionChange:)`)
    /// while the library and the database keep `libraryDescription`.
    func expectEdit(
        _ itemId: UUID,
        libraryDescription: String,
        sessionDescription: String,
        sourceLocation: SourceLocation = #_sourceLocation,
        _ isEdited: (Controller.Model) -> Bool
    ) async throws {
        let libraryValue = try #require(self.library(itemId), "library", sourceLocation: sourceLocation)
        let storedValue = try #require(try await self.stored(itemId), "database", sourceLocation: sourceLocation)
        let gameValue = try #require(self.game(itemId), "game copy", sourceLocation: sourceLocation)
        #expect(isEdited(libraryValue), "library", sourceLocation: sourceLocation)
        #expect(isEdited(storedValue), "database", sourceLocation: sourceLocation)
        #expect(isEdited(gameValue), "game copy", sourceLocation: sourceLocation)
        #expect(libraryValue.description == libraryDescription, "the game copy's own change stays out of the library", sourceLocation: sourceLocation)
        #expect(storedValue.description == libraryDescription, "the game copy's own change stays out of the database", sourceLocation: sourceLocation)
        #expect(gameValue.description == sessionDescription, "the game copy keeps its own change", sourceLocation: sourceLocation)
    }

    /// A session-only edit: the game copy holds it, the library and the database do not.
    func expectGameOnly(
        _ itemId: UUID,
        sourceLocation: SourceLocation = #_sourceLocation,
        _ isEdited: (Controller.Model) -> Bool
    ) async throws {
        let libraryValue = try #require(self.library(itemId), "library", sourceLocation: sourceLocation)
        let storedValue = try #require(try await self.stored(itemId), "database", sourceLocation: sourceLocation)
        let gameValue = try #require(self.game(itemId), "game copy", sourceLocation: sourceLocation)
        #expect(isEdited(gameValue), "game copy", sourceLocation: sourceLocation)
        #expect(!isEdited(libraryValue), "library", sourceLocation: sourceLocation)
        #expect(!isEdited(storedValue), "database", sourceLocation: sourceLocation)
    }

    /// An edit of an item the game has not loaded: the library and the database hold it, and no
    /// game copy is made for it.
    func expectLibraryEditWithoutGameCopy(
        _ itemId: UUID,
        sourceLocation: SourceLocation = #_sourceLocation,
        _ isEdited: (Controller.Model) -> Bool
    ) async throws {
        let libraryValue = try #require(self.library(itemId), "library", sourceLocation: sourceLocation)
        let storedValue = try #require(try await self.stored(itemId), "database", sourceLocation: sourceLocation)
        #expect(isEdited(libraryValue), "library", sourceLocation: sourceLocation)
        #expect(isEdited(storedValue), "database", sourceLocation: sourceLocation)
        #expect(self.game(itemId) == nil, "no game copy", sourceLocation: sourceLocation)
    }
}
