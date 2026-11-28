// @copyright André Trettin

#if canImport(Testing)
@testable import CoreRPG
import Foundation
import GeneratorRPG
import Testing

@testable import PhotoRPG

/// The editor window (macOS, iPad, visionOS) stays open while a game runs. Every edit it makes
/// reaches the database, and the game's in-memory copy of a loaded photo shows it too, while a
/// change only the game copy has (here its description) stays out of the library.
@Suite("Photo editor window during a game")
@MainActor
struct PhotoEditorWindowDuringGameTests {
    private static let libraryDescription = "Library description"
    private static let sessionDescription = "Session description"

    @MainActor
    private struct Fixture {
        let store: GameEditorStore
        let root: PhotoRootModel
        let itemId: UUID

        var game: GameEditorHarness<ItemController> { GameEditorHarness(itemController: root.itemController) }
        var editController: EditController { root.editController }

        func expectEdit(sourceLocation: SourceLocation = #_sourceLocation, _ isEdited: (PhotoModel) -> Bool) async throws {
            try await game.expectEdit(
                itemId,
                libraryDescription: PhotoEditorWindowDuringGameTests.libraryDescription,
                sessionDescription: PhotoEditorWindowDuringGameTests.sessionDescription,
                sourceLocation: sourceLocation,
                isEdited
            )
        }

        func fileUrl(_ name: String) -> FileUrl {
            FileUrl(fileId: itemId, url: URL(filePath: "/Photo/\(name)"), location: .newCloud, module: "photo", relativeUrl: nil)
        }
    }

    /// A photo in the library and the database, a running game and, when `loaded`, the
    /// photo in game memory with a change of its own.
    private func makeFixture(loaded: Bool = true) async throws -> Fixture {
        let store = try GameEditorStore(bundles: [CoreRPG.Resources.bundle, PhotoRPG.Resources.bundle])
        let root = PhotoRootModel.testRoot()
        root.itemController.itemDataModel.dataController = DataController(context: store.context, token: NetworkModules.photo.token)
        let itemId = await root.itemController.addNew(type: .item)
        root.editController.update(id: itemId, name: "Harbor", description: Self.libraryDescription, category: nil, tags: ["town"], forceSave: false)

        let fixture = Fixture(store: store, root: root, itemId: itemId)
        fixture.game.startGame()
        if loaded {
            fixture.game.loadIntoGame(itemId) { $0.description = Self.sessionDescription }
        }
        // Selecting the item in the editor starts its undo history.
        root.editController.editorModel.undoManaged.removeAll()
        return fixture
    }

    @Test("The header editor's name and tags reach the database and the game copy")
    func headerEdit() async throws {
        let fixture = try await makeFixture()

        fixture.editController.update(id: fixture.itemId, name: "Harbor at Night", description: nil, category: nil, tags: ["town", "zz"], forceSave: true)

        try await fixture.expectEdit { $0.name == "Harbor at Night" && $0.tags == ["town", "zz"] }
    }

    @Test("A file replaced in the editor reaches the database and the game copy")
    func replaceFile() async throws {
        let fixture = try await makeFixture()
        let fileUrl = fixture.fileUrl("Harbor.jpg")

        fixture.editController.reset(fileUrl: fileUrl, itemId: fixture.itemId, forceSave: true)

        try await fixture.expectEdit { $0.fileUrl == fileUrl }
    }

    @Test("Extracted title and tags applied in the editor reach the database and the game copy")
    func applyAnalysis() async throws {
        let fixture = try await makeFixture()
        let analysis = PhotoSummaryAnalysis(title: "Old Harbor", summary: "Not applied", tags: ["harbor", "town"])

        fixture.editController.applyAnalysis(analysis, to: fixture.itemId, selection: PhotoPropertySelection(applyDescription: false), forceSave: true)

        try await fixture.expectEdit { $0.name == "Old Harbor" && $0.tags == ["harbor", "town"] }
    }

    @Test("Undo and redo of an editor edit change the database and the game copy")
    func undoAndRedo() async throws {
        let fixture = try await makeFixture()
        fixture.editController.update(id: fixture.itemId, name: "Harbor at Night", description: nil, category: nil, tags: nil, forceSave: true)

        fixture.editController.undo()
        try await fixture.expectEdit { $0.name == "Harbor" }

        fixture.editController.redo()
        try await fixture.expectEdit { $0.name == "Harbor at Night" }
    }

    @Test("An edit of a photo the game has not loaded reaches the database and makes no game copy")
    func editOfItemNotInGame() async throws {
        let fixture = try await makeFixture(loaded: false)
        let fileUrl = fixture.fileUrl("Harbor.jpg")

        fixture.editController.update(id: fixture.itemId, name: "Harbor at Night", description: nil, category: nil, tags: nil, forceSave: true)
        fixture.editController.reset(fileUrl: fileUrl, itemId: fixture.itemId, forceSave: true)

        try await fixture.game.expectLibraryEditWithoutGameCopy(fixture.itemId) { $0.name == "Harbor at Night" && $0.fileUrl == fileUrl }
    }

    @Test("Without the editor, an in-game edit stays in game memory")
    func inGameEditStaysInGameMemory() async throws {
        let fixture = try await makeFixture()

        fixture.editController.update(id: fixture.itemId, name: "Session name", description: nil, category: nil, tags: nil, forceSave: false)

        try await fixture.game.expectGameOnly(fixture.itemId) { $0.name == "Session name" }
    }
}
#endif
