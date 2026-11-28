// @copyright André Trettin

#if canImport(Testing)
@testable import CoreRPG
import Foundation
import PhotoRPG
import Testing

@testable import WeatherRPG

/// The editor window (macOS, iPad, visionOS) stays open while a game runs. Every edit it makes
/// reaches the database, and the game's in-memory copy of a loaded weather shows it too, while a
/// change only the game copy has (here its description) stays out of the library.
@Suite("Weather editor window during a game")
@MainActor
struct WeatherEditorWindowDuringGameTests {
    private static let libraryDescription = "Library description"
    private static let sessionDescription = "Session description"

    @MainActor
    private struct Fixture {
        let store: GameEditorStore
        let root: WeatherRootModel
        let itemId: UUID

        var game: GameEditorHarness<ItemController> { GameEditorHarness(itemController: root.itemController) }
        var editController: EditController { root.editController }

        func expectEdit(sourceLocation: SourceLocation = #_sourceLocation, _ isEdited: (WeatherModel) -> Bool) async throws {
            try await game.expectEdit(
                itemId,
                libraryDescription: WeatherEditorWindowDuringGameTests.libraryDescription,
                sessionDescription: WeatherEditorWindowDuringGameTests.sessionDescription,
                sourceLocation: sourceLocation,
                isEdited
            )
        }
    }

    /// A weather in the library and the database, a running game and, when `loaded`, the weather
    /// in game memory with a change of its own.
    private func makeFixture(loaded: Bool = true) async throws -> Fixture {
        let store = try GameEditorStore(bundles: [CoreRPG.Resources.bundle, WeatherRPG.Resources.bundle])
        let root = WeatherRootModel.testRoot(photoRoot: PhotoRootModel.testRoot())
        root.itemController.itemDataModel.dataController = DataController(context: store.context, token: NetworkModules.weather.token)
        let itemId = await root.itemController.addNew(type: .item)
        root.editController.update(id: itemId, name: "Autumn", description: Self.libraryDescription, category: nil, tags: ["season"])

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

        fixture.editController.update(id: fixture.itemId, name: "Late Autumn", description: nil, category: nil, tags: ["cold", "season"], forceSave: true)

        try await fixture.expectEdit { $0.name == "Late Autumn" && $0.tags == ["cold", "season"] }
    }

    @Test("Clouds and time set in the condition editor reach the database and the game copy")
    func conditionEditor() async throws {
        let fixture = try await makeFixture()

        fixture.editController.reset(cloudThickness: .thick, itemId: fixture.itemId, forceSave: true)
        fixture.editController.reset(time: 0.75, itemId: fixture.itemId, forceSave: true)

        try await fixture.expectEdit { $0.cloudThickness == .thick && $0.time == 0.75 }
    }

    @Test("Storm type, rain intensity and rain angle set in the storm editor reach the database and the game copy")
    func stormEditor() async throws {
        let fixture = try await makeFixture()

        fixture.editController.reset(stormType: .snow, itemId: fixture.itemId, forceSave: true)
        fixture.editController.reset(rainIntensity: 0.5, itemId: fixture.itemId, forceSave: true)
        fixture.editController.reset(rainAngle: 30, itemId: fixture.itemId, forceSave: true)

        try await fixture.expectEdit { $0.stormType == .snow && $0.rainIntensity == 0.5 && $0.rainAngle == 30 }
    }

    @Test("Lightning set in the thunder editor reaches the database and the game copy")
    func thunderEditor() async throws {
        let fixture = try await makeFixture()

        fixture.editController.reset(lightningFrequency: 0.5, itemId: fixture.itemId, forceSave: true)
        fixture.editController.reset(lightningMaxBolts: 3, itemId: fixture.itemId, forceSave: true)
        fixture.editController.reset(lightningForkProbability: 0.25, itemId: fixture.itemId, forceSave: true)

        try await fixture.expectEdit { $0.lightningFrequency == 0.5 && $0.lightningMaxBolts == 3 && $0.lightningForkProbability == 0.25 }
    }

    @Test("The photo selected in the photo editor reaches the database and the game copy")
    func photoEditor() async throws {
        let fixture = try await makeFixture()
        let photoId = UUID()

        fixture.editController.add(photoId: photoId, itemId: fixture.itemId, forceSave: true)

        try await fixture.expectEdit { $0.photoId == photoId }
    }

    @Test("Undo and redo of an editor edit change the database and the game copy")
    func undoAndRedo() async throws {
        let fixture = try await makeFixture()
        let original = try #require(fixture.game.library(fixture.itemId)?.stormType)
        let changed: Storm.Contents = original == .snow ? .rain : .snow
        fixture.editController.reset(stormType: changed, itemId: fixture.itemId, forceSave: true)

        fixture.editController.undo()
        try await fixture.expectEdit { $0.stormType == original }

        fixture.editController.redo()
        try await fixture.expectEdit { $0.stormType == changed }
    }

    @Test("An edit of a weather the game has not loaded reaches the database and makes no game copy")
    func editOfWeatherNotInGame() async throws {
        let fixture = try await makeFixture(loaded: false)

        fixture.editController.reset(cloudThickness: .ultra, itemId: fixture.itemId, forceSave: true)

        try await fixture.game.expectLibraryEditWithoutGameCopy(fixture.itemId) { $0.cloudThickness == .ultra }
    }

    @Test("Without the editor, an in-game edit stays in game memory")
    func inGameEditStaysInGameMemory() async throws {
        let fixture = try await makeFixture()

        fixture.editController.reset(cloudThickness: .ultra, itemId: fixture.itemId)

        try await fixture.game.expectGameOnly(fixture.itemId) { $0.cloudThickness == .ultra }
    }
}
#endif
