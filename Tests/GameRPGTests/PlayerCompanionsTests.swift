// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import CharacterRPG
@testable import GameRPG
@testable import MapRPG

@Suite("Player companions in a running game")
@MainActor
struct PlayerCompanionsTests {
    @Test("A companion's pin is moved by its player until the game master decides otherwise")
    func companionPins() async throws {
        let env = try await PlayerMasterControllerTestEnvironment.create()
        let root = env.masterRoot
        root.gameModel.masterController = env.master
        let wolfId = UUID()
        root.characterRoot.itemController.replace(model: ValueModel(id: wolfId, name: "Wolf"), isInsert: true)
        let annaId = UUID()
        let wolf = TablePlayerModel(characterId: wolfId)
        let anna = PlayerGameModel(id: annaId, type: .player, name: "Anna", characterId: UUID(), companions: [wolf])
        let control = SharingControlModel(id: annaId, name: "Anna", show: true)

        #expect(root.gameModel.add(playerId: annaId, playerModel: anna, sharingModel: control))
        await env.master.resetPlayers()

        func wolfPin() -> MapPinModel? {
            root.mapRoot.gameController.mapGameModel.playerPins.first { $0.id == wolf.id }
        }
        #expect(root.mapRoot.gameController.mapGameModel.playerPins.map(\.id) == [annaId, wolf.id])
        #expect(wolfPin()?.characterId == wolfId)
        #expect(wolfPin()?.players == [wolf.id, annaId])
        #expect(wolfPin()?.isControlled(by: annaId) == true)

        // The game master takes it away from its player; the empty choice sticks.
        root.setPinController(annaId, for: wolf.id, isEnabled: false)
        await env.master.resetPlayers()
        #expect(wolfPin()?.players == [wolf.id])
        #expect(root.gameModel.pinControllers[wolf.id] == [])

        // The same list again needs no reset; switching the companion off does.
        #expect(!root.gameModel.add(playerId: annaId, playerModel: anna, sharingModel: control))
        var sleeping = anna
        sleeping.companions[0].isEnabled = false
        #expect(root.gameModel.add(playerId: annaId, playerModel: sleeping, sharingModel: control))
        await env.master.resetPlayers()
        #expect(root.mapRoot.gameController.mapGameModel.playerPins.map(\.id) == [annaId])
    }

    @Test("Only a player brings companions, never its own Character")
    func rosterCompanionsAreSanitized() {
        let model = GameRootModel()
        let heroId = UUID()
        let playerId = UUID()
        let observerId = UUID()
        let wolf = TablePlayerModel(characterId: UUID())
        let player = PlayerGameModel(
            id: playerId, type: .player, name: "Anna", characterId: heroId,
            companions: [TablePlayerModel(characterId: heroId), wolf, TablePlayerModel(id: playerId, characterId: UUID())]
        )
        let observer = PlayerGameModel(id: observerId, type: .observer, name: "Eye", companions: [wolf])

        _ = model.add(playerId: playerId, playerModel: player, sharingModel: SharingControlModel(id: playerId, name: "Anna", show: true))
        _ = model.add(playerId: observerId, playerModel: observer, sharingModel: SharingControlModel(id: observerId, name: "Eye", show: true))

        #expect(model.gameRoster.players.first { $0.id == playerId }?.companions == [wolf])
        #expect(model.gameRoster.players.first { $0.id == observerId }?.companions == [])
    }

    @Test("A master broadcast does not undo the player's newer companion list")
    func localCompanionsSurviveMasterBroadcast() {
        let model = GameRootModel()
        let localId = UUID()
        let wolf = TablePlayerModel(characterId: UUID())
        model.gameConfig.id = localId
        model.gameRoster.players = [PlayerGameModel(id: localId, type: .player, name: "Anna", companions: [wolf])]

        model.applyMasterBroadcast(
            masterId: UUID(),
            masterName: "GM",
            state: GameMasterStateModel(state: .started, players: [PlayerGameModel(id: localId, type: .player, name: "Anna")])
        )

        #expect(model.gamePlayer.companions == [wolf])
    }

    @Test("The master asks for a companion it lacks, never for another player's Character")
    func companionHandshake() async throws {
        let env = try await PlayerMasterControllerTestEnvironment.create()
        let root = env.masterRoot
        let annaId = UUID()
        let bobsHeroId = UUID()
        let wolf = TablePlayerModel(characterId: UUID())
        let stolen = TablePlayerModel(characterId: bobsHeroId)
        let anna = PlayerGameModel(id: annaId, type: .player, name: "Anna", characterId: UUID(), companions: [wolf, stolen])
        root.gameModel.gameRoster.players = [
            anna,
            PlayerGameModel(id: UUID(), type: .player, name: "Bob", characterId: bobsHeroId)
        ]
        func reference(to characterId: UUID) -> GameNetworkModel {
            GameNetworkModel(
                counter: 1,
                proxyCounter: 0,
                type: .update,
                subType: .store,
                masterId: env.masterGameConfig.master.id,
                sender: GameSenderModel(id: annaId, role: .player, name: "Anna", characterId: anna.characterId, companions: anna.companions),
                data: NetworkCodableDataType(id: characterId, type: .value, version: 42, data: nil)
            )
        }

        let request = try await env.master.handleValue(reference(to: wolf.characterId))
        #expect(request?.id == wolf.characterId)
        #expect(try await env.master.handleValue(reference(to: bobsHeroId)) == nil)
        #expect(try await env.master.handleValue(reference(to: UUID())) == nil)
    }

    @Test("A companion package from the player lands in the master's library and gets its pin")
    func companionPackageImport() async throws {
        let env = try await PlayerMasterControllerTestEnvironment.create()
        let root = env.masterRoot
        root.gameModel.masterController = env.master
        let wolfId = UUID()
        env.playerRoot.characterRoot.itemController.replace(model: ValueModel(id: wolfId, name: "Wolf"), isInsert: true)
        let package = try await env.playerRoot.characterRoot.gameControllable.createGameData(for: wolfId)
        #expect(root.characterRoot.valueGameControllable.playerPinName(for: wolfId) == nil)

        let annaId = UUID()
        let wolf = TablePlayerModel(characterId: wolfId)
        let anna = PlayerGameModel(id: annaId, type: .player, name: "Anna", characterId: UUID(), companions: [wolf])
        root.gameModel.gameRoster.players = [anna]
        let message = GameNetworkModel(
            counter: 2,
            proxyCounter: 0,
            type: .update,
            subType: .store,
            masterId: env.masterGameConfig.master.id,
            sender: GameSenderModel(id: annaId, role: .player, name: "Anna", characterId: anna.characterId, companions: [wolf]),
            data: package
        )

        #expect(try await env.master.handleValue(message) == nil)

        #expect(root.characterRoot.valueGameControllable.playerPinName(for: wolfId) == "Wolf")
        let pin = try #require(root.mapRoot.gameController.mapGameModel.playerPins.first { $0.id == wolf.id })
        #expect(pin.characterId == wolfId)
        #expect(pin.players == [wolf.id, annaId])
    }

    @Test("The sender carries at most the allowed companions, and nothing when there are none")
    func senderCoding() throws {
        let companions = (0..<12).map { _ in TablePlayerModel(characterId: UUID()) }
        let sender = GameSenderModel(id: UUID(), role: .player, name: "Anna", characterId: nil, companions: companions)

        let decoded = try JSONDecoder().decode(GameSenderModel.self, from: JSONEncoder().encode(sender))
        #expect(decoded.companions == Array(companions.prefix(PlayerGameModel.maximumCompanions)))

        let plain = GameSenderModel(id: UUID(), role: .player, name: "Bob", characterId: nil)
        let json = try #require(String(data: JSONEncoder().encode(plain), encoding: .utf8))
        #expect(!json.contains("companions"))
    }

    @Test("The companion panel skips the player's own Character and stops at the limit")
    func companionPanel() {
        let store = CompanionsStore()
        let ownId = UUID()
        let sut = TablePlayersModel {
            store.companions
        } update: { companions in
            store.companions = companions
        } excludedCharacterIds: {
            [ownId]
        }
        sut.maximumCount = 2

        sut.startPicking()
        for itemId in [ownId, UUID(), UUID(), UUID()] {
            sut.selectionModel.toggleSelection(itemId: itemId, entryId: nil, isCollection: false)
        }
        sut.addPicked()

        #expect(store.companions.count == 2)
        #expect(!store.companions.contains { $0.characterId == ownId })
    }
}

@MainActor
private final class CompanionsStore {
    var companions: [TablePlayerModel] = []
}
#endif
