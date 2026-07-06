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
struct LogGameControllerTests {

    @Test func logModelsPlayersAttachmentsAndScreenUpdatesReflectGameModelState() async throws {
        let root = try await MockRoot.createGameRoot()
        let sut = LogGameController(root: root, gameModel: root.gameModel)
        let playerA = UUID()
        let playerB = UUID()
        let screenData = Data([1, 2, 3, 4])

        root.gameModel.gameRoster.players = [
            PlayerGameModel(id: playerB, type: .player, name: "Zara"),
            PlayerGameModel(id: playerA, type: .player, name: "Arin")
        ]
        root.gameModel.metaDataAttachments = [
            .map: UUID(),
            .photo: UUID()
        ]

        sut.addMessage(counter: 7, type: .store, subType: .show, module: .photo, itemId: root.gameModel.metaDataAttachments[.photo]!)
        sut.updateMessage(counter: 7, player: playerA)
        sut.updateScreen(counter: 0, player: playerB, data: nil)
        sut.updateScreen(counter: 1, player: playerB, data: screenData)

        let log = try #require(sut.logModels.first)
        let players = sut.players
        let attachments = sut.attachments

        #expect(log.id == 7)
        #expect(log.players == [playerA])
        #expect(sut.maxPlayers == 2)
        #expect(players.map(\.name) == ["Arin", "Zara"])
        #expect(players.first?.data == nil)
        #expect(players.last?.data == screenData)
        #expect(Set(attachments.map(\.id)) == Set(["MAPS", "PHOTOS"]))
        #expect(attachments.count == 2)
        #expect(sut.playerNames(for: [playerA, UUID(), playerB]) == "Arin, Unknown Player, Zara")
    }

    @Test func nameResolvesKnownModuleItemsAndFallsBackForUnresolvedModules() async throws {
        let root = try await MockRoot.createGameRoot()
        let sut = LogGameController(root: root, gameModel: root.gameModel)

        let adventureId = await root.adventureRoot.itemController.addNew(type: .item)
        root.adventureRoot.editController.reset(name: "Adventure Name", itemId: adventureId)
        let audioId = await root.audioRoot.itemController.addNew(type: .item)
        root.audioRoot.editController.reset(name: "Audio Name", itemId: audioId)
        let diceId = await root.diceRoot.itemController.addNew(type: .item)
        root.diceRoot.editController.reset(name: "Dice Name", itemId: diceId)
        let mapId = await root.mapRoot.itemController.addNew(type: .item)
        root.mapRoot.editController.reset(name: "Map Name", itemId: mapId)
        let pdfId = await root.pdfRoot.itemController.addNew(type: .item)
        root.pdfRoot.editController.reset(name: "Pdf Name", itemId: pdfId)
        let photoId = await root.photoRoot.itemController.addNew(type: .item)
        root.photoRoot.editController.reset(name: "Photo Name", itemId: photoId)
        let spaceId = await root.spaceRoot.itemController.addNew(type: .item)
        root.spaceRoot.editController.reset(name: "Space Name", itemId: spaceId)
        let tableId = await root.tableRoot.itemController.addNew(type: .item)
        root.tableRoot.editController.reset(name: "Table Name", itemId: tableId)
        let weatherId = await root.weatherRoot.itemController.addNew(type: .scenario)
        root.weatherRoot.editController.reset(name: "Weather Name", itemId: weatherId)

        #expect(sut.name(for: .adventure, itemId: adventureId) == "Adventure Name")
        #expect(sut.name(for: .audio, itemId: audioId) == "Audio Name")
        #expect(sut.name(for: .dice, itemId: diceId) == "Dice Name")
        #expect(sut.name(for: .map, itemId: mapId) == "Map Name")
        #expect(sut.name(for: .pdf, itemId: pdfId) == "Pdf Name")
        #expect(sut.name(for: .photo, itemId: photoId) == "Photo Name")
        #expect(sut.name(for: .space, itemId: spaceId) == "Space Name")
        #expect(sut.name(for: .table, itemId: tableId) == "Table Name")
        #expect(sut.name(for: .weather, itemId: weatherId) == "Weather Name")

        let fallbackId = UUID()
        #expect(sut.name(for: .none, itemId: fallbackId) == fallbackId.uuidString)
        #expect(sut.name(for: .game, itemId: fallbackId) == fallbackId.uuidString)
        #expect(sut.name(for: .setting, itemId: fallbackId) == fallbackId.uuidString)
        #expect(sut.name(for: .editor, itemId: fallbackId) == fallbackId.uuidString)
        #expect(sut.name(for: .generator, itemId: fallbackId) == fallbackId.uuidString)
        #expect(sut.name(for: .search, itemId: fallbackId) == fallbackId.uuidString)
        let valueName = sut.name(for: .value, itemId: fallbackId)
        #expect(valueName.isEmpty || valueName == fallbackId.uuidString)
    }
}
#endif
