// @copyright André Trettin

#if canImport(Testing)
@testable import CoreRPG
import Foundation
import Testing

@testable import AudioRPG

/// The editor window (macOS, iPad, visionOS) stays open while a game runs. Every edit it makes
/// reaches the database, and the game's in-memory copy of a loaded track shows it too, while a
/// change only the game copy has (here its description) stays out of the library.
@Suite("Audio editor window during a game")
@MainActor
struct AudioEditorWindowDuringGameTests {
    private static let libraryDescription = "Library description"
    private static let sessionDescription = "Session description"

    @MainActor
    private struct Fixture {
        let store: GameEditorStore
        let root: AudioRootModel
        let itemId: UUID

        var game: GameEditorHarness<ItemController> { GameEditorHarness(itemController: root.itemController) }
        var editController: EditController { root.editController }

        func expectEdit(sourceLocation: SourceLocation = #_sourceLocation, _ isEdited: (AudioModel) -> Bool) async throws {
            try await game.expectEdit(
                itemId,
                libraryDescription: AudioEditorWindowDuringGameTests.libraryDescription,
                sessionDescription: AudioEditorWindowDuringGameTests.sessionDescription,
                sourceLocation: sourceLocation,
                isEdited
            )
        }

        func fileUrl(_ name: String) -> FileUrl {
            FileUrl(fileId: itemId, url: URL(filePath: "/Audio/\(name)"), location: .newCloud, module: "audio", relativeUrl: nil)
        }
    }

    /// A track in the library and the database, a running game and, when `loaded`, the
    /// track in game memory with a change of its own.
    private func makeFixture(loaded: Bool = true) async throws -> Fixture {
        let store = try GameEditorStore(bundles: [CoreRPG.Resources.bundle, AudioRPG.Resources.bundle])
        let root = AudioRootModel.testRoot()
        root.itemController.itemDataModel.dataController = DataController(context: store.context, token: NetworkModules.audio.token)
        let itemId = await root.itemController.addNew(type: .item)
        root.editController.update(id: itemId, name: "Tavern", description: Self.libraryDescription, category: nil, tags: ["music"])

        let fixture = Fixture(store: store, root: root, itemId: itemId)
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

        fixture.editController.update(id: fixture.itemId, name: "Tavern Brawl", description: nil, category: nil, tags: ["music", "zz"], forceSave: true)

        try await fixture.expectEdit { $0.name == "Tavern Brawl" && $0.tags == ["music", "zz"] }
    }

    @Test("A file replaced in the editor reaches the database and the game copy")
    func replaceFile() async throws {
        let fixture = try await makeFixture()
        let fileUrl = fixture.fileUrl("Tavern.m4a")

        fixture.editController.reset(fileUrl: fileUrl, itemId: fixture.itemId, forceSave: true)

        try await fixture.expectEdit { $0.fileUrl == fileUrl }
    }

    @Test("Undo and redo of an editor edit change the database and the game copy")
    func undoAndRedo() async throws {
        let fixture = try await makeFixture()
        fixture.editController.update(id: fixture.itemId, name: "Tavern Brawl", description: nil, category: nil, tags: nil, forceSave: true)

        fixture.editController.undo()
        try await fixture.expectEdit { $0.name == "Tavern" }

        fixture.editController.redo()
        try await fixture.expectEdit { $0.name == "Tavern Brawl" }
    }

    @Test("An edit of a track the game has not loaded reaches the database and makes no game copy")
    func editOfItemNotInGame() async throws {
        let fixture = try await makeFixture(loaded: false)
        let fileUrl = fixture.fileUrl("Tavern.m4a")

        fixture.editController.update(id: fixture.itemId, name: "Tavern Brawl", description: nil, category: nil, tags: nil, forceSave: true)
        fixture.editController.reset(fileUrl: fileUrl, itemId: fixture.itemId, forceSave: true)

        try await fixture.game.expectLibraryEditWithoutGameCopy(fixture.itemId) { $0.name == "Tavern Brawl" && $0.fileUrl == fileUrl }
    }

    @Test("Without the editor, an in-game edit stays in game memory")
    func inGameEditStaysInGameMemory() async throws {
        let fixture = try await makeFixture()

        fixture.editController.update(id: fixture.itemId, name: "Session name", description: nil, category: nil, tags: nil)

        try await fixture.game.expectGameOnly(fixture.itemId) { $0.name == "Session name" }
    }
}
#endif
