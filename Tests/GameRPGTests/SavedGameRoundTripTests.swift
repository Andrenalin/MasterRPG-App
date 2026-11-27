// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import AdventureRPG
@testable import AudioRPG
@testable import CharacterRPG
@testable import DiceRPG
@testable import GameRPG
@testable import MapRPG
@testable import PdfRPG
@testable import PhotoRPG
@testable import SpaceRPG
@testable import TableRPG
@testable import WeatherRPG

@MainActor
struct SavedGameRoundTripTests {

    @Test
    func importingASavedGameLoadsMapPinsIntoGameMemoryWithoutRestoringTheDatabase() async throws {
        // Given: a map with pins, as if a game were currently running.
        let root = try await MockRoot.createGameRoot()

        let mapId = await root.mapRoot.itemController.addNew(type: .item)
        root.mapRoot.editController.reset(name: "Round Trip Map", itemId: mapId)

        root.adventureRoot.startGame()
        #expect(root.mapRoot.itemController.itemDataModel.isGameMode)

        let savedPins = [
            MapPinModel(id: UUID(), name: "Camp", location: CGPoint(x: 0.25, y: 0.4))
        ]
        root.mapRoot.itemController.itemOrEmpty(for: mapId).mapPins = savedPins

        // When: the game is saved to a file, exactly as MasterGameScreen's "Save and Quit" does.
        let itemIds = root.saveGame()
        let exportModel = ItemDataExportModel()
        let fileUrl = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).gms")
        defer { try? FileManager.default.removeItem(at: fileUrl) }

        let exportTask = root.adventureRoot.exportControllable.createExport(
            itemIds: itemIds,
            into: fileUrl,
            exportModel: exportModel
        )
        _ = try await exportTask.value

        // And: the game is stopped, and the local database is wiped entirely.
        try await MockRoot.resetGameController(for: root)
        #expect(!root.mapRoot.itemController.itemDataModel.isGameMode)
        #expect(root.mapRoot.gameController.gameModel.itemData.isEmpty)

        await root.adventureRoot.resetData()
        #expect(root.mapRoot.itemController.itemDataModel.items.isEmpty)
        #expect(root.mapRoot.itemController.itemDataModel.itemData.isEmpty)

        // When: the saved game is imported back — no game is running at this point,
        // and importing must not start one (gameMemoryOnly writes bypass isGameMode entirely).
        let importModel = ItemDataImportModel()
        let importTask = root.adventureRoot.importControllable.importUrl(
            from: fileUrl,
            importModel: importModel,
            gameMemoryOnly: true
        )
        _ = try await importTask.value

        // Then: no game was started by the import...
        #expect(!root.mapRoot.itemController.itemDataModel.isGameMode)

        // ...the permanent database is still empty...
        #expect(root.mapRoot.itemController.itemDataModel.items.isEmpty)
        #expect(root.mapRoot.itemController.itemDataModel.itemData.isEmpty)

        // ...the map is now the running game's active item...
        #expect(root.mapRoot.gameController.gameModel.items.contains(mapId))
        #expect(root.mapRoot.gameController.gameModel.currentItemId == mapId)

        // ...and the map's in-memory game item carries the saved pins.
        let restoredMap = root.mapRoot.gameController.gameItem(for: mapId)
        let restoredPin = try #require(restoredMap.mapPins.first)
        let savedPin = try #require(savedPins.first)
        #expect(restoredMap.mapPins.count == 1)
        #expect(restoredPin.id == savedPin.id)
        #expect(restoredPin.name == savedPin.name)
        #expect(restoredPin.location == savedPin.location)
    }
}
#endif
