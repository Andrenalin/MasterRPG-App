// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Network
import RPGResourcesDebug
import Testing

@testable import CoreRPG
@testable import GameRPG
@testable import AudioRPG
@testable import CharacterRPG
@testable import PhotoRPG
@testable import PdfRPG
@testable import SpaceRPG
import AdventureRPG
@testable import WeatherRPG

/// Test environment for PlayerController tests.
@MainActor
struct PlayerControllerTestEnvironment {
    let playerController: PlayerController
    let root: GameRoot
    let gameConfig: GameConfigModel
    let masterDelegateSpy: MasterNetworkStoreDelegateMock
    let playerDelegateSpy: PlayerNetworkStoreDelegateMock
    let masterNetworkSpy: MasterNetworkControllableMock
    let playerNetworkSpy: PlayerStoreAbstractionMock
    let networkController: GameNetworkController

    /// Creates a PlayerController with test dependencies
    static func create() async throws -> PlayerControllerTestEnvironment {
        let masterDelegateSpy = MasterNetworkStoreDelegateMock()
        let playerDelegateSpy = PlayerNetworkStoreDelegateMock()
        let masterNetworkSpy = MasterNetworkControllableMock()
        let playerNetworkSpy = PlayerStoreAbstractionMock()

        let networkController = GameNetworkController(
            name: "Hello Test",
            proxy: false,
            masterBuilder: { _, _ in masterNetworkSpy },
            playerBuilder: { _, _ in playerNetworkSpy }
        )
        networkController.model.setMasterDelegate(masterDelegateSpy)
        networkController.model.setPlayerDelegate(playerDelegateSpy)

        let root = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: root.adventureRoot)
        try await MockRoot.resetGameController(for: root)

        await MainActor.run {
            root.networkStore = networkController
        }
        let playerId = UUID()
        let gameConfig = GameConfigModel(id: playerId, state: .started, master: .empty)
        let gameRoster = GameRosterModel(players: [PlayerGameModel(id: playerId, type: .player, name: "AndrenalinPlayer")])
        root.gameModel.reset(gameConfig: gameConfig, gameRoster: gameRoster)

        let playerController = PlayerController(root: root, asGameMaster: false)

        return PlayerControllerTestEnvironment(
            playerController: playerController,
            root: root,
            gameConfig: gameConfig,
            masterDelegateSpy: masterDelegateSpy,
            playerDelegateSpy: playerDelegateSpy,
            masterNetworkSpy: masterNetworkSpy,
            playerNetworkSpy: playerNetworkSpy,
            networkController: networkController
        )
    }
}

@Suite("Player controller tests")
@MainActor
struct PlayerControllerTests {

    @Test("Handle photo reveal with data and ID")
    func handlePhoto() async throws {
        // Arrange
        let env = try await PlayerControllerTestEnvironment.create()
        try await MockRoot.importTestData(into: env.root.adventureRoot)
        env.root.adventureRoot.startGame()

        #expect(env.root.photoRoot.itemControllable.itemDataModel.items.count == 27)
        let itemId = env.root.photoRoot.itemControllable.itemDataModel.items[0]
        let netData = try await env.root.photoRoot.gameControllable.createGameData(for: itemId)
        let netId = await env.root.photoRoot.gameControllable.share(id: itemId)
        let masterConfig = Self.masterConfig()

        // Act & Assert - Handle photo with full data
        var gameNetworkModel = GameNetworkModel(
            version: 1,
            counter: 1,
            proxyCounter: 0,
            type: .reveal,
            subType: .show,
            gameConfig: masterConfig,
            data: netData
        )

        var result = try await env.playerController.handle(gameNetworkModel)
        #expect(result?.subType == .ok)
        #expect(result?.data.effectiveAssetVersion == netData.effectiveAssetVersion)
        #expect(await env.root.photoRoot.gameControllable.currentId == itemId)

        // Act & Assert - Reset and handle with ID only
        await env.root.photoRoot.gameControllable.reset()
        #expect(await env.root.photoRoot.gameControllable.currentId != itemId)
        let item = await env.root.photoRoot.itemControllable.item(for: itemId)
        env.root.photoRoot.itemControllable.itemDataModel.resetModel(id: itemId)

        gameNetworkModel = GameNetworkModel(
            version: 1,
            counter: 1,
            proxyCounter: 0,
            type: .reveal,
            subType: .show,
            gameConfig: masterConfig,
            data: netId
        )
        result = try await env.playerController.handle(gameNetworkModel)
        #expect(result?.subType == .show)
        #expect(await env.root.photoRoot.gameControllable.currentId != itemId)

        // Act & Assert - Handle with data again
        gameNetworkModel = GameNetworkModel(
            version: 1,
            counter: 1,
            proxyCounter: 0,
            type: .reveal,
            subType: .show,
            gameConfig: masterConfig,
            data: netData
        )
        result = try await env.playerController.handle(gameNetworkModel)
        #expect(result?.subType == .ok)
        #expect(result?.data.effectiveAssetVersion == netData.effectiveAssetVersion)
        #expect(await env.root.photoRoot.gameControllable.currentId == itemId)
        let restoredItem = await env.root.photoRoot.itemControllable.item(for: itemId)
        #expect(restoredItem != nil)
        #expect(restoredItem?.name == item?.name)
    }

    @Test("Player photo share chooses baseline request, full data, then reference from availability")
    func playerPhotoShareUsesAvailability() async throws {
        let env = try await PlayerControllerTestEnvironment.create()
        try await MockRoot.importTestData(
            into: env.root.adventureRoot,
            name: ResourcesDebug.photoTestData,
            itemCounter: 0
        )
        env.root.adventureRoot.startGame()

        let photoId = try #require(env.root.photoRoot.itemController.itemDataModel.items.first {
            env.root.photoRoot.itemController.itemSync(for: $0)?.fileUrl != nil
        })
        let photoData = try await env.root.photoRoot.gameControllable.createGameData(for: photoId)
        let playerId = env.gameConfig.id
        let masterId = UUID()
        let missingPlayerId = UUID()
        let baseline = photoData.effectiveAssetVersion

        env.root.gameModel.reset(
            gameConfig: GameConfigModel(
                id: playerId,
                state: .started,
                master: MasterGameModel(id: masterId, type: .master, name: "Game Master")
            ),
            gameRoster: GameRosterModel(players: [
                PlayerGameModel(id: playerId, type: .player, name: "AndrenalinPlayer")
            ])
        )

        // An absent/mismatched player report is only a request for the
        // master's canonical baseline; player bytes must not be uploaded.
        let newerMasterBaseline = baseline + 1
        await env.root.photoRoot.photoGameControllable.setMasterVersion(
            itemId: photoId,
            version: newerMasterBaseline,
            masterId: masterId
        )
        await env.playerController.game(message: photoData, actionType: .generic)

        var sent = try #require(env.playerNetworkSpy.requestData as? GameNetworkModel)
        #expect(sent.type == .reveal)
        #expect(sent.subType == .show)
        #expect(sent.data.id == photoId)
        #expect(sent.data.effectiveAssetVersion == newerMasterBaseline)
        #expect(sent.data.data == nil)
        #expect(sent.usesFileJournal == false)

        // Once the sender has the exact master version, include bytes while
        // any reported participant is still missing the photo.
        await env.root.photoRoot.photoGameControllable.setMasterVersion(
            itemId: photoId,
            version: baseline,
            masterId: masterId
        )
        await env.root.photoRoot.photoGameControllable.markPhotoAvailable(
            itemId: photoId,
            version: baseline,
            for: [masterId, playerId],
            masterId: masterId
        )
        env.root.photoRoot.gameControllable.gameModel.currentPlayers = [masterId, playerId, missingPlayerId]
        await env.playerController.game(message: photoData, actionType: .generic)

        sent = try #require(env.playerNetworkSpy.requestData as? GameNetworkModel)
        #expect(sent.type == .reveal)
        #expect(sent.subType == .show)
        #expect(sent.data.effectiveAssetVersion == baseline)
        #expect(sent.data.data == photoData.data)
        #expect(sent.usesFileJournal)
        #expect(await env.root.photoRoot.photoGameControllable.isPhotoAvailable(
            itemId: photoId,
            for: missingPlayerId,
            masterId: masterId
        ))

        // The full Journal reveal marks the current roster available, so the
        // next reveal carries only the canonical reference.
        await env.playerController.game(message: photoData, actionType: .generic)

        sent = try #require(env.playerNetworkSpy.requestData as? GameNetworkModel)
        #expect(sent.type == .reveal)
        #expect(sent.subType == .show)
        #expect(sent.data.effectiveAssetVersion == baseline)
        #expect(sent.data.data == nil)
        #expect(sent.usesFileJournal == false)
    }

    @Test("Player defers photo reveal without authoritative availability")
    func playerDefersPhotoRevealWithoutAuthoritativeAvailability() async throws {
        // Arrange
        let env = try await PlayerControllerTestEnvironment.create()
        try await MockRoot.importTestData(into: env.root.adventureRoot)
        env.root.adventureRoot.startGame()

        let photoId = try #require(env.root.photoRoot.itemControllable.itemDataModel.items.first)
        let photoData = try await env.root.photoRoot.gameControllable.createGameData(for: photoId)
        let masterId = UUID()
        env.playerController.gameModel.gameUpdateType = .map
        #expect(env.root.photoRoot.gameControllable.gameModel.currentItemId == nil)

        let playerMessage = Self.networkModel(
            type: .reveal,
            data: photoData,
            gameConfig: Self.playerConfig(masterId: masterId)
        )

        // Act
        let response = try await env.playerController.handle(playerMessage)

        // Assert
        #expect(response == nil)
        #expect(env.playerController.gameModel.deferredPhotoReveals(from: masterId).count == 1)
        #expect(env.playerController.gameModel.gameUpdateType == .map)
        #expect(env.root.photoRoot.gameControllable.gameModel.currentItemId == nil)
    }

    @Test("SharePlay audio store completes a pending reveal and can play")
    func sharePlayAudioStoreCompletesPendingRevealAndCanPlay() async throws {
        // Arrange
        let env = try await PlayerControllerTestEnvironment.create()
        try await MockRoot.importTestData(into: env.root.adventureRoot)
        try await MockRoot.importTestData(
            into: env.root.adventureRoot,
            name: ResourcesDebug.audioTestData,
            itemCounter: 3
        )
        env.root.adventureRoot.startGame()

        let audioId = try #require(env.root.audioRoot.itemController.itemDataModel.items.last)
        let audioData = try await env.root.audioRoot.gameControllable.createGameData(for: audioId)
        let audioReference = await env.root.audioRoot.gameControllable.share(id: audioId)
        await env.root.audioRoot.gameControllable.reset()
        env.root.audioRoot.itemController.itemDataModel.resetModel(id: audioId)
        let masterConfig = Self.masterConfig()

        let reveal = Self.networkModel(type: .reveal, data: audioReference, gameConfig: masterConfig)
        let store = Self.networkModel(type: .store, subType: .show, data: audioData, gameConfig: masterConfig)

        // Act
        let request = try await env.playerController.handle(reveal)
        let acknowledgment = try await env.playerController.handle(store)

        let playData = env.root.audioRoot.gameController.requestPlay(id: audioId)
        let play = Self.networkModel(type: .update, subType: .playAudio, data: playData, gameConfig: masterConfig)
        _ = try await env.playerController.handle(play)

        // Assert
        #expect(request?.subType == .show)
        #expect(acknowledgment?.subType == .ok)
        #expect(env.playerController.gameModel.pendingAudioRequests.isEmpty)
        #expect(await env.root.audioRoot.gameControllable.currentId == audioId)
        #expect(await env.root.audioRoot.gameControllable.hasLocalFileData(for: audioId))
        #expect(env.root.audioRoot.audioController.model.playList.map(\.id) == [audioId])
        #expect(env.root.audioRoot.audioController.model.currentId == audioId)
    }

    @Test("Character join advertises metadata and sends the full package only when requested")
    func characterJoinHandshake() async throws {
        // Given
        let env = try await PlayerControllerTestEnvironment.create()
        let root = env.root
        let sut = env.playerController
        let characterId = await root.characterRoot.itemController.addNew(type: .character)
        root.characterRoot.editController.reset(name: "Mira", itemId: characterId)
        root.gameModel.reset(
            gameConfig: env.gameConfig,
            gameRoster: GameRosterModel(players: [
                PlayerGameModel(id: env.gameConfig.id, type: .player, name: "AndrenalinPlayer", characterId: characterId)
            ])
        )
        sut.gameModel.lostMaster = false

        // When: the player joins.
        await sut.sendCharacter()

        // Then: only ID and recursive package version are sent.
        let reference = try #require(env.playerNetworkSpy.requestData as? GameNetworkModel)
        let expectedVersion = await root.characterRoot.gameControllable.networkVersion(for: characterId)
        #expect(reference.type == .update)
        #expect(reference.subType == .store)
        #expect(reference.data.id == characterId)
        #expect(reference.data.version == expectedVersion)
        #expect(reference.data.data == nil)
        #expect(!PlayerController.usesFileJournal(for: reference))
        #expect(sut.gameModel.hasSendPlayer)

        // When: the master requests the mismatched package.
        let request = Self.networkModel(
            type: .update,
            subType: .store,
            data: reference.data,
            gameConfig: Self.masterConfig()
        )
        let response = try await sut.handle(request)

        // Then: the second message carries the full package without Journal.
        #expect(response == nil)
        let messages = env.playerNetworkSpy.requestHistory.compactMap { $0 as? GameNetworkModel }
        #expect(messages.count == 2)
        let package = try #require(messages.last)
        #expect(package.type == .update)
        #expect(package.subType == .store)
        #expect(package.data.id == characterId)
        #expect(package.data.version == reference.data.version)
        #expect(package.data.data != nil)
        #expect(!PlayerController.usesFileJournal(for: package))

        // Legacy master presentation and generic-update flows are ignored.
        let legacyReveal = Self.networkModel(
            type: .reveal,
            data: package.data,
            gameConfig: Self.masterConfig()
        )
        let legacyGeneric = Self.networkModel(
            type: .update,
            subType: .generic,
            data: package.data,
            gameConfig: Self.masterConfig()
        )
        let legacyRevealResponse = try await sut.handle(legacyReveal)
        let legacyGenericResponse = try await sut.handle(legacyGeneric)
        #expect(legacyRevealResponse == nil)
        #expect(legacyGenericResponse == nil)
        #expect(env.playerNetworkSpy.calledRequest == 2)
        #expect(sut.gameModel.gameUpdateType != .value)
    }

    @Test(
        "SharePlay peers ignore another player's Character synchronization",
        arguments: [false, true]
    )
    func sharePlayPeerIgnoresPlayerCharacter(includesPackage: Bool) async throws {
        // Given
        let env = try await PlayerControllerTestEnvironment.create()
        let remotePlayerId = UUID()
        let remoteCharacterId = UUID()
        let message = GameNetworkModel(
            counter: 8,
            proxyCounter: 0,
            type: .update,
            subType: .store,
            masterId: UUID(),
            sender: GameSenderModel(
                id: remotePlayerId,
                role: .player,
                name: "Remote Player",
                characterId: remoteCharacterId
            ),
            data: NetworkCodableDataType(
                id: remoteCharacterId,
                type: .value,
                version: 42,
                data: includesPackage ? Data("Character package".utf8) : nil
            )
        )

        // When
        await env.playerController.receivedSharePlay(message, participantId: remotePlayerId)

        // Then
        #expect(env.playerNetworkSpy.calledRequest == 0)
        #expect(await env.root.characterRoot.itemController.item(for: remoteCharacterId) == nil)
    }

    @Test("Handle proxy value update focuses the forwarded character")
    func handleProxyValueUpdateFocusesCharacter() async throws {
        let env = try await PlayerControllerTestEnvironment.create()
        let root = env.root
        let sut = env.playerController

        let characterId = await root.characterRoot.itemController.addNew(type: .character)
        root.characterRoot.editController.reset(name: "Proxy Mira", itemId: characterId)
        root.gameModel.reset(
            gameConfig: env.gameConfig,
            gameRoster: GameRosterModel(players: [
                PlayerGameModel(id: env.gameConfig.id, type: .proxy, name: "Proxy Player", characterId: characterId)
            ])
        )

        let characterData = try await root.characterRoot.gameControllable.createGameData(for: characterId)
        let characterReference = await root.characterRoot.gameControllable.share(id: characterId)
        let metadataResponse = try await sut.handle(
            Self.networkModel(
                type: .update,
                subType: .store,
                data: characterReference,
                gameConfig: Self.masterConfig()
            )
        )
        let legacyRevealResponse = try await sut.handle(
            Self.networkModel(type: .reveal, data: characterData, gameConfig: Self.masterConfig())
        )
        #expect(metadataResponse == nil)
        #expect(legacyRevealResponse == nil)
        #expect(sut.gameModel.proxyFocusTask == nil)

        let response = try await sut.handle(Self.networkModel(type: .update, subType: .store, data: characterData, gameConfig: Self.masterConfig()))
        #expect(response == nil)
        #expect(characterData.data != nil)
        #expect(characterData.version != 0)
        let focusTask = try #require(sut.gameModel.proxyFocusTask)

        await focusTask.value
        #expect(root.gameModel.selectedCharacter == characterId)
        #expect(sut.gameModel.proxyFocusTask == nil)
    }

    @Test("Handle weather reveal, store and update messages")
    func handleWeather() async throws {
        let env = try await PlayerControllerTestEnvironment.create()
        let root = env.root
        let sut = env.playerController
        let masterConfig = Self.masterConfig()

        let weatherId = await root.weatherRoot.itemController.addNew(type: .scenario)
        root.weatherRoot.editController.reset(name: "Storm Front", itemId: weatherId)
        let weatherData = try await root.weatherRoot.gameControllable.createGameData(for: weatherId)

        var response = try await sut.handle(Self.networkModel(type: .reveal, data: weatherData, gameConfig: masterConfig))
        #expect(response?.subType == .ok)
        #expect(await root.weatherRoot.gameControllable.currentId == weatherId)
        #expect(sut.gameModel.gameUpdateType == .weather)

        let missingId = UUID()
        let missingData = NetworkCodableDataType(id: missingId, type: .weather, version: 1)
        response = try await sut.handle(Self.networkModel(type: .reveal, data: missingData, gameConfig: masterConfig))
        #expect(response?.subType == .show)
        #expect(response?.data.id == missingId)

        response = try await sut.handle(Self.networkModel(type: .store, subType: .store, data: weatherData, gameConfig: masterConfig))
        #expect(response?.subType == .ok)

        await root.weatherRoot.gameControllable.reset()
        sut.gameModel.gameUpdateType = .none
        response = try await sut.handle(Self.networkModel(type: .update, subType: .show, data: weatherData, gameConfig: masterConfig))
        #expect(response == nil)
        #expect(await root.weatherRoot.gameControllable.currentId != weatherId)
        #expect(sut.gameModel.gameUpdateType == .none)
    }

    @Test("Player connection delegates update state and process master messages")
    func connectionDelegatesUpdateStateAndProcessMessages() async throws {
        let env = try await PlayerControllerTestEnvironment.create()
        let sut = env.playerController
        let masterConfig = Self.masterConfig()
        let data = NetworkCodableDataType(id: UUID(), type: .none, version: 0)

        await sut.readyProxy()
        #expect(sut.gameModel.lostMaster == false)
        #expect(env.playerNetworkSpy.calledRequest == 4)
        let initialReports = env.playerNetworkSpy.requestHistory.compactMap { $0 as? GameNetworkModel }
        let initialAudioReport = try #require(initialReports.first { $0.subType == .audioList })
        #expect(initialAudioReport.type == .update)
        #expect(initialAudioReport.subType == .audioList)
        #expect(initialAudioReport.sender.id == env.gameConfig.id)
        let initialAudioList = try #require(AudioListRequest.decodeData(of: initialAudioReport.data.data))
        #expect(initialAudioList.list.isEmpty)
        let initialPhotoReport = try #require(initialReports.first { $0.subType == .photoList })
        #expect(initialPhotoReport.type == .update)
        #expect(initialPhotoReport.subType == .photoList)
        #expect(initialPhotoReport.sender.id == env.gameConfig.id)
        let initialPhotoList = try #require(PhotoListRequest.decodeData(of: initialPhotoReport.data.data))
        #expect(initialPhotoList.list.isEmpty)
        #expect(initialPhotoList.players.isEmpty)
        let initialPdfReport = try #require(initialReports.first { $0.subType == .pdfList })
        #expect(initialPdfReport.type == .update)
        #expect(initialPdfReport.sender.id == env.gameConfig.id)
        let initialPdfList = try #require(PdfListRequest.decodeData(of: initialPdfReport.data.data))
        #expect(initialPdfList.list.isEmpty)
        #expect(initialPdfList.players.isEmpty)
        let initialSpaceReport = try #require(initialReports.first { $0.subType == .spaceList })
        #expect(initialSpaceReport.type == .update)
        #expect(initialSpaceReport.sender.id == env.gameConfig.id)
        let initialSpaceList = try #require(SpaceListRequest.decodeData(of: initialSpaceReport.data.data))
        #expect(initialSpaceList.list.isEmpty)
        #expect(initialSpaceList.players.isEmpty)

        await sut.lostProxyConnection()
        #expect(sut.gameModel.lostMaster)
        #expect(sut.gameModel.hasSendPlayer == false)

        await sut.ready()
        #expect(sut.gameModel.lostMaster == false)
        #expect(env.playerNetworkSpy.calledRequest == 8)
        let reconnectReports = env.playerNetworkSpy.requestHistory.suffix(4).compactMap { $0 as? GameNetworkModel }
        #expect(reconnectReports.map(\.subType) == [.audioList, .photoList, .pdfList, .spaceList])
        await sut.lostConnection()
        #expect(sut.gameModel.lostMaster)
        #expect(sut.gameModel.sendCharacterTask == nil)

        await sut.received(Self.networkModel(counter: 21, type: .update, data: data, gameConfig: masterConfig))
        #expect(sut.gameModel.messageCounter == 1)

        await sut.receivedProxy(Self.networkModel(counter: 22, type: .update, data: data, gameConfig: masterConfig))
        #expect(sut.gameModel.messageCounter == 2)

        await sut.receivedFile(Self.networkModel(counter: 23, type: .update, data: data, gameConfig: masterConfig))
        #expect(sut.gameModel.messageCounter == 3)

        await sut.receivedFile(Self.networkModel(counter: 24, type: .update, data: data, gameConfig: env.gameConfig))
        #expect(sut.gameModel.messageCounter == 3)
    }
}

private extension PlayerControllerTests {
    static func masterConfig(id: UUID = UUID(), name: String = "Game Master") -> GameConfigModel {
        GameConfigModel(id: id, state: .started, master: MasterGameModel(id: id, type: .master, name: name))
    }

    static func playerConfig(masterId: UUID) -> GameConfigModel {
        GameConfigModel(id: UUID(), state: .started, master: MasterGameModel(id: masterId, type: .master, name: "Game Master"))
    }

    static func networkModel(
        counter: Int = 1,
        type: RPGMessageType,
        subType: RPGMessageActionType = .show,
        data: NetworkCodableDataType,
        gameConfig: GameConfigModel
    ) -> GameNetworkModel {
        GameNetworkModel(
            version: 1,
            counter: counter,
            proxyCounter: 0,
            type: type,
            subType: subType,
            gameConfig: gameConfig,
            data: data
        )
    }
}
#endif
