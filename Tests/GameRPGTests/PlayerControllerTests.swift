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

    @Test("Table-generated outcome pushed by the master is nested under the player's Character and persisted")
    func handlesAddItem() async throws {
        let env = try await PlayerControllerTestEnvironment.create()
        let characterId = UUID()
        env.root.characterRoot.itemController.replace(
            model: ValueModel(id: characterId, name: "Aria", entries: []),
            isInsert: true
        )
        env.root.gameModel.gameRoster.players[0].characterId = characterId

        let payload = SheetItemTransfer(
            name: "Weapon",
            description: "Found in the chest",
            entries: [SheetItemTransfer.Entry(name: "Damage", content: "1d8")]
        )
        let data = NetworkCodableDataType(
            id: payload.id,
            type: .value,
            version: 1,
            data: payload.encodeData()
        )
        let model = Self.networkModel(
            type: .update,
            subType: .addItem,
            data: data,
            gameConfig: Self.masterConfig()
        )

        let response = try await env.playerController.handle(model)

        #expect(response == nil)
        // `noGame: true` reads straight from the persisted store, proving
        // `handleAddItem` forced the save through rather than leaving it in
        // game-only memory (see `ItemControllable.replace(model:isInsert:forceSave:)`).
        let character = try #require(env.root.characterRoot.itemController.itemSync(for: characterId, noGame: true))
        let groupEntry = try #require(character.entries.first)
        let newValueId = try #require(groupEntry.valueId)
        let added = try #require(env.root.characterRoot.itemController.itemSync(for: newValueId, noGame: true))
        #expect(added.name == "Weapon")
        #expect(added.description == "Found in the chest")
        #expect(added.entries.map(\.name) == ["Damage"])
        // Grouped under the character, not a disconnected top-level value —
        // `groupId`/`isGroupHiddenToggle` is the nested-group marker
        // `addItemAsGroup` sets, mirroring `addNewGroup(itemId:)`.
        #expect(added.groupId == characterId)
        #expect(added.isGroupHiddenToggle == true)
    }

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

    @Test("Only a show-photo event presents a photo; a stored photo is cached without being presented")
    func storedPhotoIsNotPresented() async throws {
        let env = try await PlayerControllerTestEnvironment.create()
        try await MockRoot.importTestData(into: env.root.adventureRoot)
        env.root.adventureRoot.startGame()

        let itemId = env.root.photoRoot.itemControllable.itemDataModel.items[0]
        let netData = try await env.root.photoRoot.gameControllable.createGameData(for: itemId)
        let masterConfig = Self.masterConfig()

        // A map's pin photo arrives as a store. It is the first cached photo of the game, so
        // it becomes the module's current item — but nobody asked to show it.
        _ = try await env.playerController.handle(GameNetworkModel(
            counter: 1,
            proxyCounter: 0,
            type: .store,
            subType: .store,
            gameConfig: masterConfig,
            data: netData
        ))
        #expect(await env.root.photoRoot.gameControllable.currentId == itemId)
        #expect(env.root.photoRoot.photoGameControllable.presentedPhotoId == nil)
        #expect(env.playerController.gameModel.gameUpdateType != .photo)

        let result = try await env.playerController.handle(GameNetworkModel(
            counter: 2,
            proxyCounter: 0,
            type: .reveal,
            subType: .show,
            gameConfig: masterConfig,
            data: netData
        ))
        #expect(result?.subType == .ok)
        #expect(env.root.photoRoot.photoGameControllable.presentedPhotoId == itemId)
        #expect(env.playerController.gameModel.gameUpdateType == .photo)

        await env.root.photoRoot.gameControllable.reset()
        #expect(env.root.photoRoot.photoGameControllable.presentedPhotoId == nil)
    }

    @Test("An audio file that did not load through SharePlay is reported to the game master as failed")
    func audioLoadFailureIsReported() async throws {
        // Given: the game master's store of an audio track, which this device holds only as a reference.
        let env = try await PlayerControllerTestEnvironment.create()
        let masterConfig = Self.masterConfig()
        env.root.gameModel.reset(
            gameConfig: GameConfigModel(id: env.gameConfig.id, state: .started, master: masterConfig.master),
            gameRoster: env.root.gameModel.gameRoster
        )
        let trackId = UUID()
        let reference = Self.networkModel(
            counter: 39,
            type: .store,
            data: NetworkCodableDataType(id: trackId, type: .audio, version: 7),
            gameConfig: masterConfig
        )

        // When: the Journal could not deliver the bytes (the reference itself was handled before).
        await env.playerController.sharePlayFileLoadFailed(reference)

        // Then: the master is told, so it sends the file again or goes on without this player.
        let failure = try #require(env.playerNetworkSpy.requestData as? GameNetworkModel)
        #expect(failure.counter == 39)
        #expect(failure.subType == .failed)
        #expect(failure.data.id == trackId)
        #expect(failure.data.version == 7)
        #expect(failure.data.data == nil)
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
        #expect(sut.gameModel.hasSentPlayer)

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

    @Test("Event timestamp admission accepts bounded wall clocks only")
    func eventTimestampAdmissionBoundsFutureClockSkew() {
        let now: TimeInterval = 10_000

        #expect(!GameNetworkModel.acceptsEventTimestamp(0, now: now))
        #expect(GameNetworkModel.acceptsEventTimestamp(now, now: now))
        #expect(GameNetworkModel.acceptsEventTimestamp(
            now + GameNetworkModel.maximumFutureEventTimestampSkew,
            now: now
        ))
        #expect(!GameNetworkModel.acceptsEventTimestamp(
            now + GameNetworkModel.maximumFutureEventTimestampSkew + 1,
            now: now
        ))
        #expect(!GameNetworkModel.acceptsEventTimestamp(-1, now: now))
        #expect(!GameNetworkModel.acceptsEventTimestamp(.nan, now: now))
        #expect(!GameNetworkModel.acceptsEventTimestamp(.infinity, now: now))
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
        #expect(sut.gameModel.hasSentPlayer == false)

        await sut.ready()
        #expect(sut.gameModel.lostMaster == false)
        #expect(env.playerNetworkSpy.calledRequest == 8)
        let reconnectReports = env.playerNetworkSpy.requestHistory.suffix(4).compactMap { $0 as? GameNetworkModel }
        #expect(reconnectReports.map(\.subType) == [.audioList, .photoList, .pdfList, .spaceList])
        await sut.lostConnection()
        #expect(sut.gameModel.lostMaster)
        #expect(sut.gameModel.sendCharacterTask == nil)

        await sut.received(Self.networkModel(counter: 21, type: .update, data: data, gameConfig: masterConfig))

        await sut.receivedProxy(Self.networkModel(counter: 22, type: .update, data: data, gameConfig: masterConfig))

        await sut.receivedFile(Self.networkModel(counter: 23, type: .update, data: data, gameConfig: masterConfig))

        await sut.receivedFile(Self.networkModel(counter: 24, type: .update, data: data, gameConfig: env.gameConfig))
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
