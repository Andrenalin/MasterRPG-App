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

    @Test("A companion id that is already a pin id, a player, a table player or repeated is refused (§6.3)")
    func companionIdCollisionsAreRefused() {
        let model = GameRootModel()
        let tableId = UUID()
        model.tablePlayers = [TablePlayerModel(id: tableId, characterId: UUID())]
        let annaId = UUID()
        let bobId = UUID()
        let annasWolf = TablePlayerModel(characterId: UUID())
        let anna = PlayerGameModel(id: annaId, type: .player, name: "Anna", characterId: UUID(), companions: [annasWolf])
        _ = model.add(playerId: annaId, playerModel: anna, sharingModel: SharingControlModel(id: annaId, name: "Anna", show: true))

        let fine = TablePlayerModel(characterId: UUID())
        let bob = PlayerGameModel(
            id: bobId, type: .player, name: "Bob", characterId: UUID(),
            companions: [
                TablePlayerModel(id: tableId, characterId: UUID()),
                TablePlayerModel(id: annaId, characterId: UUID()),
                TablePlayerModel(id: annasWolf.id, characterId: UUID()),
                fine,
                TablePlayerModel(id: fine.id, characterId: UUID())
            ]
        )
        _ = model.add(playerId: bobId, playerModel: bob, sharingModel: SharingControlModel(id: bobId, name: "Bob", show: true))

        #expect(model.gameRoster.players.first { $0.id == bobId }?.companions == [fine])
        #expect(model.gameRoster.players.first { $0.id == annaId }?.companions == [annasWolf], "the first owner keeps its companion")
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

    // MARK: - CODE_AUDIT_24 §5.5

    @Test("A player without a Character of its own still announces and delivers its companions")
    func playerWithoutCharacterDeliversCompanions() async throws {
        let env = try await PlayerMasterControllerTestEnvironment.create()
        let wolfId = UUID()
        env.playerRoot.characterRoot.itemController.replace(model: ValueModel(id: wolfId, name: "Wolf"), isInsert: true)
        let playerId = env.playerGameConfig.id
        let wolf = TablePlayerModel(characterId: wolfId)
        env.playerRoot.gameModel.gameRoster.players = [PlayerGameModel(id: playerId, type: .player, name: "Anna", companions: [wolf])]
        env.player.gameModel.reset(lostMaster: false)

        await env.player.sendCharacter()

        let announced = try #require(env.playerNetworkSpy.requestHistory.compactMap { $0 as? GameNetworkModel }.last)
        #expect(announced.data.id == wolfId)
        #expect(announced.data.data == nil)
        #expect(announced.sender.companions == [wolf])
        #expect(env.player.gameModel.hasSentPlayer)

        // The master asks for the package; the player answers although it has no Character.
        let request = env.playerRoot.gameModel.outgoingMessage(
            counter: 5, type: .update, subType: .store, asMaster: true,
            data: NetworkCodableDataType(id: wolfId, type: .value, version: 1, data: nil)
        )
        let before = env.playerNetworkSpy.requestHistory.count
        #expect(try await env.player.handleValue(request) == nil)
        #expect(env.playerNetworkSpy.requestHistory.count == before + 1)
        let package = try #require(env.playerNetworkSpy.requestData as? GameNetworkModel)
        #expect(package.data.id == wolfId)
        #expect(package.data.data != nil)
    }

    @Test("A companion list that changes while a send runs is announced again")
    func companionsEditedDuringSendAreAnnouncedAgain() async throws {
        let env = try await PlayerMasterControllerTestEnvironment.create()
        let wolfId = UUID()
        let bearId = UUID()
        for (id, name) in [(wolfId, "Wolf"), (bearId, "Bear")] {
            env.playerRoot.characterRoot.itemController.replace(model: ValueModel(id: id, name: name), isInsert: true)
        }
        let playerId = env.playerGameConfig.id
        let wolf = TablePlayerModel(characterId: wolfId)
        let bear = TablePlayerModel(characterId: bearId)
        env.playerRoot.gameModel.gameRoster.players = [PlayerGameModel(id: playerId, type: .player, name: "Anna", companions: [wolf])]
        env.player.gameModel.reset(lostMaster: false)

        // The player adds a bear while the first announcement is on its way: right after the
        // first message went out, the edit `announceCompanions` starts with happens.
        nonisolated(unsafe) var didEdit = false
        let player = env.player
        let playerRoot = env.playerRoot
        env.playerNetworkSpy.onRequest = {
            guard !didEdit else { return }
            didEdit = true
            MainActor.assumeIsolated {
                playerRoot.gameModel.gameRoster.players[0].companions = [wolf, bear]
                player.gameModel.noteCompanionsChanged()
                player.gameModel.reset(sendPlayer: false)
            }
        }

        await env.player.scheduleSendCharacter()
        await env.player.gameModel.sendCharacterTask?.value
        env.playerNetworkSpy.onRequest = nil

        let announced = env.playerNetworkSpy.requestHistory.compactMap { ($0 as? GameNetworkModel)?.data.id }
        #expect(announced == [wolfId, wolfId, bearId], "the first, stale announcement and the complete second one")
        #expect(env.player.gameModel.hasSentPlayer, "and the final send is the one that latches")
    }

    @Test("The master tells the player when a companion package cannot be imported, and the player retries")
    func failedCompanionImportIsReported() async throws {
        let env = try await PlayerMasterControllerTestEnvironment.create()
        let root = env.masterRoot
        let annaId = UUID()
        let wolf = TablePlayerModel(characterId: UUID())
        let anna = PlayerGameModel(id: annaId, type: .player, name: "Anna", companions: [wolf])
        root.gameModel.gameRoster.players = [anna]
        let broken = GameNetworkModel(
            counter: 2,
            proxyCounter: 0,
            type: .update,
            subType: .store,
            masterId: env.masterGameConfig.master.id,
            sender: GameSenderModel(id: annaId, role: .player, name: "Anna", characterId: nil, companions: [wolf]),
            data: NetworkCodableDataType(id: wolf.characterId, type: .value, version: 3, data: Data([1, 2, 3]))
        )

        // The player has a connection: the failure is addressed to it (CODE_AUDIT_Game_Shareplay §5.28).
        env.master.bind(connectionId: UUID(), playerId: annaId)
        #expect(try await env.master.handleValue(broken) == nil)

        let failure = try #require(env.masterNetworkSpy.sendResponseData as? GameNetworkModel)
        #expect(failure.subType == .failed)
        #expect(failure.data.id == wolf.characterId)

        // The player takes the failure like one for its Character: the send is opened again.
        env.playerRoot.gameModel.gameRoster.players = [PlayerGameModel(id: env.playerGameConfig.id, type: .player, name: "Anna", companions: [wolf])]
        env.player.gameModel.reset(sendPlayer: true)
        let answer = env.playerRoot.gameModel.outgoingMessage(
            counter: 6, type: .update, subType: .failed, asMaster: true,
            data: NetworkCodableDataType(id: wolf.characterId, type: .value, version: 3, data: nil)
        )
        #expect(try await env.player.handleValue(answer) == nil)
        #expect(!env.player.gameModel.hasSentPlayer)
    }

    @Test("A companion package merges into a Character the master already has, it does not replace it (§6.4)")
    func companionPackageMergesIntoExistingCharacter() async throws {
        let env = try await PlayerMasterControllerTestEnvironment.create()
        let root = env.masterRoot
        root.gameModel.masterController = env.master
        let wolfId = UUID()
        let masterEntry = ValueEntryModel(id: UUID(), name: "Fur", type: .text, value: "Grey")
        // Both devices start from the same Character; each then changes a different field.
        let base = ValueModel(id: wolfId, name: "Wolf")
        let masterWolf = base.copy()
        let playerWolf = base.copy()
        playerWolf.name = "Alpha"
        try await Task.sleep(for: .milliseconds(20))
        masterWolf.entries = [masterEntry]
        root.characterRoot.itemController.replace(model: masterWolf, isInsert: true)
        env.playerRoot.characterRoot.itemController.replace(model: playerWolf, isInsert: true)
        let package = try await env.playerRoot.characterRoot.gameControllable.createGameData(for: wolfId)

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

        let merged = try #require(root.characterRoot.itemController.itemSync(for: wolfId, noGame: true))
        #expect(merged.entries.map(\.id) == [masterEntry.id], "the master's newer change is not replaced by the player's older copy")
        #expect(merged.name == "Alpha", "what the player changed comes along")
    }

    @Test("Only the game master and players are offered the Players panel (§9.13)")
    func playersPanelIsOfferedByRole() async throws {
        let env = try await PlayerMasterControllerTestEnvironment.create()
        let root = env.playerRoot
        let id = env.playerGameConfig.id

        #expect(root.offersTablePlayers(isMaster: true))
        #expect(root.offersTablePlayers(isMaster: false), "the roster entry is a player")
        root.gameModel.gameRoster.players = [PlayerGameModel(id: id, type: .observer, name: "Eye")]
        #expect(!root.offersTablePlayers(isMaster: false))
        root.gameModel.gameRoster.players = [PlayerGameModel(id: id, type: .proxy, name: "Mirror")]
        #expect(!root.offersTablePlayers(isMaster: false))
    }

    @Test("The sender carries the allowed companions, and nothing when there are none")
    func senderCoding() throws {
        let companions = (0..<PlayerGameModel.maximumCompanions).map { _ in TablePlayerModel(characterId: UUID()) }
        let sender = GameSenderModel(id: UUID(), role: .player, name: "Anna", characterId: nil, companions: companions)

        let decoded = try JSONDecoder().decode(GameSenderModel.self, from: JSONEncoder().encode(sender))
        #expect(decoded.companions == companions)

        let plain = GameSenderModel(id: UUID(), role: .player, name: "Bob", characterId: nil)
        let json = try #require(String(data: JSONEncoder().encode(plain), encoding: .utf8))
        #expect(!json.contains("companions"))
    }

    @Test("A companion list over the limit is refused before it is decoded, in a sender and in a roster entry (§6.6)")
    func oversizedCompanionListIsRefused() throws {
        let tooMany = (0...PlayerGameModel.maximumCompanions).map { _ in TablePlayerModel(characterId: UUID()) }
        let sender = GameSenderModel(id: UUID(), role: .player, name: "Anna", characterId: nil, companions: tooMany)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(GameSenderModel.self, from: JSONEncoder().encode(sender))
        }

        // The roster entry: built by hand, because its initializer already caps the list.
        let entry = PlayerGameModel(id: UUID(), type: .player, name: "Anna")
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        json["companions"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(tooMany))
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(PlayerGameModel.self, from: data) }

        // The limit itself is fine, and garbage elements do not hide behind it.
        json["companions"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Array(tooMany.prefix(PlayerGameModel.maximumCompanions))))
        let fine = try JSONDecoder().decode(PlayerGameModel.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(fine.companions.count == PlayerGameModel.maximumCompanions)
    }

    @Test("An observer's pin move has the size cap and clock check of a player's group event (§6.6)")
    func observerPinMoveIsBounded() async throws {
        let env = try await PlayerMasterControllerTestEnvironment.create()
        func move(payloadBytes: Int, timestamp: TimeInterval = Date.now.timeIntervalSince1970) -> GameNetworkModel {
            GameNetworkModel(
                timestamp: timestamp,
                counter: 1,
                proxyCounter: 0,
                type: .update,
                subType: .mapPin,
                masterId: env.masterGameConfig.master.id,
                sender: GameSenderModel(id: UUID(), role: .observer, name: "Eye", characterId: nil),
                data: NetworkCodableDataType(id: UUID(), type: .map, version: 1, data: Data(count: payloadBytes))
            )
        }

        #expect(env.master.normalizedObserverMessage(move(payloadBytes: 100)) != nil)
        #expect(env.master.normalizedObserverMessage(move(payloadBytes: GameLimits.maximumGroupEventPayloadBytes + 1)) == nil)
        #expect(env.master.normalizedObserverMessage(move(payloadBytes: 100, timestamp: Date.now.timeIntervalSince1970 + 10 * 365 * 24 * 3600)) == nil)
        #expect(env.master.normalizedObserverMessage(move(payloadBytes: 100, timestamp: .infinity)) == nil)
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
