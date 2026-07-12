// @copyright André Trettin

#if canImport(Testing)
import Foundation
import RPGResourcesDebug
import Testing

import AdventureRPG
@testable import CoreRPG
@testable import DiceRPG
@testable import GameRPG
@testable import MapRPG
@testable import PhotoRPG
@testable import SpaceRPG

@Suite("Game message correctness regressions")
@MainActor
struct GameMessageCorrectnessRegressionTests {
    @Test("Player acknowledgement travels upstream but not back to proxy clients")
    func acknowledgementIsNotForwardedToProxyClients() async throws {
        // Given
        let environment = try await RoutingEnvironment.make()
        let command = environment.masterMessage(
            counter: 7,
            type: .reveal,
            subType: .show,
            data: NetworkCodableDataType(id: UUID(), type: .photo, version: 1)
        )

        // When
        await environment.player.receivedProcess(command)

        // Then
        #expect(environment.directPlayerSpy.calledRequest == 1)
        let response = try #require(environment.directPlayerSpy.requestData as? GameNetworkModel)
        #expect(!response.sender.isMaster)
        #expect(response.subType == .show)

        #expect(environment.proxyMasterSpy.calledSendResponseAll == 1)
        let relayed = try #require(environment.proxyMasterSpy.sendResponseData as? GameNetworkModel)
        #expect(relayed.sender.isMaster)
        #expect(relayed.counter == command.counter)
    }

    @Test("SharePlay routes a player message to one controller on the master device")
    func sharePlayPlayerMessageIsHandledOnceOnMasterDevice() async {
        // Given
        let masterSpy = MasterNetworkStoreDelegateMock()
        let playerSpy = PlayerNetworkStoreDelegateMock()
        let masterNetworkSpy = MasterNetworkControllableMock()
        let playerNetworkSpy = PlayerStoreAbstractionMock()
        let network = GameNetworkController(
            name: "SharePlay routing",
            proxy: false,
            masterBuilder: { _, _ in masterNetworkSpy },
            playerBuilder: { _, _ in playerNetworkSpy }
        )
        network.model.setMasterDelegate(masterSpy)
        network.model.setPlayerDelegate(playerSpy)
        network.setupLocal()

        let playerId = UUID()
        let playerMessage = GameNetworkModel(
            counter: 1,
            proxyCounter: 0,
            type: .update,
            subType: .generic,
            gameConfig: GameConfigModel(id: playerId, state: .started, master: .empty),
            gameRoster: GameRosterModel(players: [PlayerGameModel(id: playerId, type: .player, name: "Player")]),
            data: NetworkCodableDataType(id: UUID(), type: .setting, version: 0)
        )

        // When
        await network.routeSharePlayUpdate(playerMessage, id: UUID())
        await network.routeSharePlayFileUpdate(playerMessage)

        // Then
        #expect(masterSpy.calledReceived == 1)
        #expect(masterSpy.calledFileReceived == 1)
        #expect(playerSpy.calledReceived == 0)
        #expect(playerSpy.calledFileReceived == 0)
    }

    @Test("Older master snapshot cannot roll player state backward")
    func staleMasterStateIsIgnored() async throws {
        // Given
        let environment = try await RoutingEnvironment.make()
        let newPlayer = PlayerGameModel(id: UUID(), type: .player, name: "Current player")
        let stalePlayer = PlayerGameModel(id: UUID(), type: .player, name: "Stale player")
        let payload = NetworkCodableDataType(id: UUID(), type: .setting, version: 0)
        let current = environment.masterMessage(counter: 10, players: [newPlayer], data: payload)
        let stale = environment.masterMessage(counter: 9, players: [stalePlayer], data: payload)

        // When
        await environment.player.receivedProcess(current)
        await environment.player.receivedProcess(stale)

        // Then
        #expect(environment.root.gameModel.gameRoster.players.contains(where: { $0.id == newPlayer.id }))
        #expect(!environment.root.gameModel.gameRoster.players.contains(where: { $0.id == stalePlayer.id }))
    }

    @Test("New player-originated messages use increasing nonzero counters")
    func playerMessagesUseMonotonicCounters() async throws {
        // Given
        let environment = try await RoutingEnvironment.make()
        let firstData = NetworkCodableDataType(id: UUID(), type: .setting, version: 0)
        let secondData = NetworkCodableDataType(id: UUID(), type: .setting, version: 0)

        // When
        await environment.player.game(message: firstData, actionType: .generic)
        await environment.player.game(message: secondData, actionType: .generic)

        // Then
        let messages = environment.directPlayerSpy.requestHistory.compactMap { $0 as? GameNetworkModel }
        #expect(messages.map(\.counter) == [1, 2])
    }

    @Test("Players with the same display name still receive each other's dice updates")
    func diceFilteringUsesPlayerId() async throws {
        // Given
        let environment = try await RoutingEnvironment.make()
        let otherPlayerId = UUID()
        let sameNameMessage = GameNetworkModel(
            counter: 1,
            proxyCounter: 0,
            type: .update,
            subType: .generic,
            gameConfig: GameConfigModel(id: otherPlayerId, state: .started, master: .empty),
            gameRoster: GameRosterModel(players: [
                PlayerGameModel(id: otherPlayerId, type: .player, name: "Local player")
            ]),
            data: NetworkCodableDataType(id: UUID(), type: .dice, version: 0)
        )

        // When
        let response = try await environment.player.handleDice(sameNameMessage)

        // Then
        #expect(response == nil)
    }

    @Test("Proxy dice forwarding preserves the originating player identity")
    func proxyDiceForwardingPreservesSender() async throws {
        // Given
        let environment = try await RoutingEnvironment.make()
        let proxyMaster = try #require(environment.player.proxyMasterController)
        let remoteId = UUID()
        let remoteMessage = GameNetworkModel(
            counter: 12,
            proxyCounter: 2,
            type: .update,
            subType: .generic,
            gameConfig: GameConfigModel(id: remoteId, state: .started, master: .empty),
            gameRoster: GameRosterModel(players: [
                PlayerGameModel(id: remoteId, type: .proxy, name: "Remote proxy")
            ]),
            data: NetworkCodableDataType(id: UUID(), type: .dice, version: 0)
        )

        // When
        await proxyMaster.receivedServerProxy(remoteMessage)

        // Then
        let forwarded = try #require(environment.directPlayerSpy.requestData as? GameNetworkModel)
        #expect(forwarded.sender.id == remoteId)
        #expect(forwarded.sender.name == "Remote proxy")
        #expect(forwarded.counter == remoteMessage.counter)
    }

    @Test("Failed receipts never update master player reports")
    func failedReceiptsAreNotReported() async throws {
        // Given
        let root = try await MockRoot.createGameRoot()
        try await MockRoot.resetGameController(for: root)
        let masterId = UUID()
        root.gameModel.reset(gameConfig: GameConfigModel(
            id: masterId,
            state: .started,
            master: MasterGameModel(id: masterId, type: .master, name: "Master")
        ))
        let master = MasterController(root: root, asProxy: false)
        let playerId = UUID()
        let playerConfig = GameConfigModel(id: playerId, state: .started, master: .empty)

        func failed(_ type: NetworkModules, id: UUID) -> GameNetworkModel {
            GameNetworkModel(
                counter: 1,
                proxyCounter: 0,
                type: .reveal,
                subType: .failed,
                gameConfig: playerConfig,
                gameRoster: GameRosterModel(players: [PlayerGameModel(id: playerId, type: .player, name: "Player")]),
                data: NetworkCodableDataType(id: id, type: type, version: 0)
            )
        }

        let mapId = UUID()
        let photoId = UUID()
        let spaceId = UUID()

        // When
        _ = try await master.handleMap(failed(.map, id: mapId))
        _ = try await master.handlePhoto(failed(.photo, id: photoId))
        _ = try await master.handleSpace(failed(.space, id: spaceId))

        // Then
        #expect(root.mapRoot.gameControllable.gameModel.playerReport(for: mapId).isEmpty)
        #expect(root.photoRoot.gameControllable.gameModel.playerReport(for: photoId).isEmpty)
        #expect(root.spaceRoot.gameControllable.gameModel.playerReport(for: spaceId).isEmpty)
    }

    @Test("Metadata-only photo with a missing file requests bytes instead of acknowledging")
    func missingPhotoBytesAreRequested() async throws {
        // Given
        let environment = try await RoutingEnvironment.make()
        try await MockRoot.importTestData(into: environment.root.adventureRoot)
        environment.root.adventureRoot.startGame()

        let photoId = try #require(environment.root.photoRoot.itemController.itemDataModel.items.first {
            environment.root.photoRoot.itemController.itemOrEmpty(for: $0).fileUrl != nil
        })
        let source = environment.root.photoRoot.itemController.itemOrEmpty(for: photoId)
        let sourceFile = try #require(source.fileUrl)
        let missingFile = FileUrl(
            fileId: UUID(),
            url: URL.temporaryDirectory.appending(path: "missing-\(UUID().uuidString).jpg"),
            location: .local,
            module: NetworkModules.photo.token,
            relativeUrl: nil,
            contentHash: sourceFile.contentHash
        )
        let metadataOnlyPhoto = PhotoModel(
            id: source.id,
            name: source.name,
            description: source.description,
            tags: source.tags,
            category: source.category,
            displayState: source.displayState,
            degrees: source.degrees,
            fileUrl: missingFile,
            entries: source.entries,
            parentId: source.parentId
        )
        environment.root.photoRoot.itemController.replace(model: metadataOnlyPhoto, isInsert: true)
        let reference = await environment.root.photoRoot.gameController.share(id: photoId)
        let reveal = environment.masterMessage(counter: 3, type: .reveal, subType: .show, data: reference)

        // When
        let response = try #require(try await environment.player.handlePhoto(reveal))

        // Then
        #expect(await !environment.root.photoRoot.gameControllable.hasLocalFileData(for: photoId))
        #expect(response.subType == .show)
        #expect(response.subType != .ok)
    }

    @Test("Ready connection receives the current presentation immediately")
    func readyConnectionReplaysCurrentPresentation() async throws {
        // Given
        let root = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: root.adventureRoot)
        try await MockRoot.resetGameController(for: root)
        let directMasterSpy = MasterNetworkControllableMock()
        let directPlayerSpy = PlayerStoreAbstractionMock()
        let proxyMasterSpy = MasterNetworkControllableMock()
        let proxyPlayerSpy = PlayerStoreAbstractionMock()
        root.networkStore = GameNetworkController(
            name: "Direct reconnect",
            proxy: false,
            masterBuilder: { _, _ in directMasterSpy },
            playerBuilder: { _, _ in directPlayerSpy }
        )
        root.networkProxyStore = GameNetworkController(
            name: "Proxy reconnect",
            proxy: true,
            masterBuilder: { _, _ in proxyMasterSpy },
            playerBuilder: { _, _ in proxyPlayerSpy }
        )

        let masterId = UUID()
        root.gameModel.reset(gameConfig: GameConfigModel(
            id: masterId,
            state: .started,
            master: MasterGameModel(id: masterId, type: .master, name: "Master")
        ))
        try await MockRoot.importTestData(into: root.adventureRoot)
        root.adventureRoot.startGame()
        let photoId = try #require(root.photoRoot.itemController.itemDataModel.items.first)
        _ = await root.photoRoot.gameControllable.setCurrent(itemId: photoId)

        let localPlayer = PlayerController(root: root, asGameMaster: true)
        localPlayer.gameModel.gameUpdateType = .photo
        root.gameModel.playerController = localPlayer
        let master = MasterController(root: root, asProxy: false)

        // When
        let connectionId = UUID()
        await master.ready(for: connectionId)

        // Then
        #expect(directMasterSpy.calledSendResponseId == 1)
        let replay = try #require(directMasterSpy.sendResponseData as? GameNetworkModel)
        #expect(replay.sender.isMaster)
        #expect(replay.type == .reveal)
        #expect(replay.subType == .show)
        #expect(replay.data.type == .photo)
        #expect(replay.data.id == photoId)
    }

    @Test("Failed processing releases the deduplication key for retry")
    func failedProcessingCanBeRetried() async throws {
        // Given
        let pipeline = GameMessagePipeline()
        let senderId = UUID()
        let message = GameNetworkModel(
            counter: 4,
            proxyCounter: 0,
            type: .reveal,
            subType: .show,
            gameConfig: GameConfigModel(id: senderId, state: .started, master: .empty),
            gameRoster: GameRosterModel(players: [PlayerGameModel(id: senderId, type: .player, name: "Player")]),
            data: NetworkCodableDataType(id: UUID(), type: .photo, version: 1)
        )
        let event = GameMessageEvent(model: message, origin: .direct(UUID()))

        // When
        #expect(await pipeline.enqueue(event))
        _ = try #require(await pipeline.next())
        await pipeline.processed(success: false)
        let retryAccepted = await pipeline.enqueue(event)
        _ = try #require(await pipeline.next())
        await pipeline.processed(success: true)
        let completedDuplicateAccepted = await pipeline.enqueue(event)

        // Then
        #expect(retryAccepted)
        #expect(!completedDuplicateAccepted)
    }
}

@MainActor
private struct RoutingEnvironment {
    let root: GameRoot
    let player: PlayerController
    let playerId: UUID
    let masterId: UUID
    let directPlayerSpy: PlayerStoreAbstractionMock
    let proxyMasterSpy: MasterNetworkControllableMock

    static func make() async throws -> RoutingEnvironment {
        let root = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: root.adventureRoot)
        try await MockRoot.resetGameController(for: root)

        let directMasterSpy = MasterNetworkControllableMock()
        let directPlayerSpy = PlayerStoreAbstractionMock()
        let proxyMasterSpy = MasterNetworkControllableMock()
        let proxyPlayerSpy = PlayerStoreAbstractionMock()
        root.networkStore = GameNetworkController(
            name: "Direct",
            proxy: false,
            masterBuilder: { _, _ in directMasterSpy },
            playerBuilder: { _, _ in directPlayerSpy }
        )
        root.networkProxyStore = GameNetworkController(
            name: "Proxy",
            proxy: true,
            masterBuilder: { _, _ in proxyMasterSpy },
            playerBuilder: { _, _ in proxyPlayerSpy }
        )

        let playerId = UUID()
        let masterId = UUID()
        root.gameModel.reset(
            gameConfig: GameConfigModel(id: playerId, state: .started, master: .empty),
            gameRoster: GameRosterModel(players: [PlayerGameModel(id: playerId, type: .player, name: "Local player")])
        )
        let player = PlayerController(root: root, asGameMaster: false)
        return RoutingEnvironment(
            root: root,
            player: player,
            playerId: playerId,
            masterId: masterId,
            directPlayerSpy: directPlayerSpy,
            proxyMasterSpy: proxyMasterSpy
        )
    }

    func masterMessage(
        counter: Int,
        players: [PlayerGameModel]? = nil,
        type: RPGMessageType = .update,
        subType: RPGMessageActionType = .generic,
        data: NetworkCodableDataType
    ) -> GameNetworkModel {
        GameNetworkModel(
            counter: counter,
            proxyCounter: 0,
            type: type,
            subType: subType,
            masterId: masterId,
            sender: GameSenderModel(id: masterId, role: .master, name: "Master", characterId: nil),
            masterState: GameMasterStateModel(
                state: .started,
                adventureId: nil,
                adventureTitle: nil,
                players: players ?? [PlayerGameModel(id: playerId, type: .player, name: "Local player")],
                controls: [],
                features: GameFeatureModel()
            ),
            data: data
        )
    }
}
#endif
