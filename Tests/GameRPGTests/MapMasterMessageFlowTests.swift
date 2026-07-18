// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import CoreRPG
import Foundation
import Testing

@testable import AdventureRPG
@testable import CharacterRPG
@testable import GameRPG
@testable import MapRPG
@testable import PhotoRPG

@Suite("Map master message flow", .serialized)
@MainActor
struct MapMasterMessageFlowTests {
    @Test("A full Character bootstrap package preserves its portrait link")
    func characterPackagePreservesPortrait() async throws {
        let characterId = UUID()
        let photoId = UUID()
        let sender = try await MockRoot.createGameRoot()
        Self.insertCharacter(id: characterId, photoId: photoId, into: sender)

        let exportedIds = sender.characterRoot.exportControllable.exporting(
            itemIds: ItemModuleIds(ids: [characterId], module: .value)
        )
        #expect(exportedIds.ids[.photo]?.contains(photoId) == true)
        let package = try await sender.characterRoot.gameControllable.createGameData(for: characterId)

        let receiver = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: receiver.adventureRoot)
        try await MockRoot.resetGameController(for: receiver)
        try await MockRoot.importTestData(into: receiver.adventureRoot)
        receiver.adventureRoot.startGame()
        try await receiver.characterRoot.valueGameControllable.updatePlayer(data: package)

        #expect(receiver.photoRoot.itemController.itemDataModel.items.contains(photoId))
        #expect(receiver.characterRoot.itemController.itemSync(
            for: characterId,
            noGame: true
        )?.photoId == photoId)
    }

    @Test("Direct mapState recovery stays on its connection and does not establish the group cache")
    func directRecoveryIsRequesterOnly() async throws {
        // Given
        let fixture = try await MapMasterRoutingFixture.makeMaster()
        let mapId = fixture.currentMapId
        let reference = await fixture.root.mapRoot.mapGameControllable.shareMap(id: mapId)
        let connectionId = ConnectionController.ID()
        let request = fixture.playerMessage(
            counter: 41,
            type: .reveal,
            subType: .mapState,
            data: reference
        )

        // When
        await fixture.master.receivedProcess(request, connectionId: connectionId)

        // Then
        let responses = fixture.directMasterSpy.sendResponseHistory.compactMap { $0 as? GameNetworkModel }
        #expect(fixture.directMasterSpy.calledSendResponseId == 3)
        #expect(fixture.directMasterSpy.calledSendResponseAll == 0)
        #expect(responses.map(\.subType) == [.store, .generic, .mapState])
        #expect(responses.allSatisfy { $0.targetId == fixture.playerId })
        #expect(responses.allSatisfy { $0.data.id == mapId })
        #expect(responses.first?.data.data != nil)
        #expect(!fixture.master.gameModel.hasSentGameItem(
            type: .map,
            id: mapId,
            version: reference.effectiveAssetVersion
        ))

        // Map acknowledgements are presentation receipts, not availability.
        let acknowledgement = fixture.playerMessage(
            counter: 42,
            type: .reveal,
            subType: .ok,
            data: reference
        )
        _ = try await fixture.master.handleMap(acknowledgement)
        #expect(fixture.root.mapRoot.gameControllable.gameModel.playerReport(for: mapId).isEmpty)
    }

    @Test("An obsolete mapState repair is superseded by one coherent current Map generation")
    func obsoleteMapStateRepairPublishesCurrentGeneration() async throws {
        // Given
        let fixture = try await MapMasterRoutingFixture.makeMaster()
        let mapId = fixture.currentMapId
        let obsoleteReference = await fixture.root.mapRoot.mapGameControllable.shareMap(id: mapId)
        fixture.root.mapRoot.gameController.gameItem(for: mapId).name = "Structurally updated Map"
        let currentReference = await fixture.root.mapRoot.mapGameControllable.shareMap(id: mapId)
        #expect(currentReference.assetVersion == obsoleteReference.assetVersion)
        #expect(currentReference.contentVersion != obsoleteReference.contentVersion)
        let connectionId = ConnectionController.ID()
        let request = fixture.playerMessage(
            counter: 44,
            type: .reveal,
            subType: .mapState,
            data: obsoleteReference
        )

        // When
        await fixture.master.receivedProcess(request, connectionId: connectionId)

        // Then: this is a fresh presentation intent, not a targeted answer to
        // the impossible old repair. All three messages describe one capture.
        let responses = fixture.directMasterSpy.sendResponseHistory.compactMap { $0 as? GameNetworkModel }
        #expect(fixture.directMasterSpy.calledSendResponseId == 3)
        #expect(fixture.directMasterSpy.calledSendResponseAll == 0)
        #expect(responses.map(\.subType) == [.show, .generic, .mapState])
        #expect(responses.allSatisfy { $0.targetId == nil && $0.data.id == mapId })
        #expect(responses.first?.data.data != nil)
        #expect(responses.allSatisfy {
            $0.data.assetVersion == currentReference.assetVersion
                && $0.data.contentVersion == currentReference.contentVersion
        })
    }

    @Test("An obsolete structural repair is superseded instead of applying unrelated Map content")
    func obsoleteMapContentRepairPublishesCurrentGeneration() async throws {
        // Given
        let fixture = try await MapMasterRoutingFixture.makeMaster()
        let mapId = fixture.currentMapId
        let obsoleteReference = await fixture.root.mapRoot.mapGameControllable.shareMap(id: mapId)
        fixture.root.mapRoot.gameController.gameItem(for: mapId).name = "New structural generation"
        let currentReference = await fixture.root.mapRoot.mapGameControllable.shareMap(id: mapId)
        #expect(currentReference.contentVersion != obsoleteReference.contentVersion)
        let connectionId = ConnectionController.ID()
        let request = fixture.playerMessage(
            counter: 45,
            type: .update,
            subType: .generic,
            data: obsoleteReference
        )

        // When
        await fixture.master.receivedProcess(request, connectionId: connectionId)

        // Then
        let responses = fixture.directMasterSpy.sendResponseHistory.compactMap { $0 as? GameNetworkModel }
        #expect(fixture.directMasterSpy.calledSendResponseId == 3)
        #expect(fixture.directMasterSpy.calledSendResponseAll == 0)
        #expect(responses.map(\.subType) == [.show, .generic, .mapState])
        #expect(responses.allSatisfy { $0.targetId == nil && $0.data.id == mapId })
        #expect(responses.allSatisfy {
            $0.data.assetVersion == currentReference.assetVersion
                && $0.data.contentVersion == currentReference.contentVersion
        })
    }

    @Test("A failed Map response is ignored by the master")
    func failedMapResponseIsIgnored() async throws {
        // Given
        let fixture = try await MapMasterRoutingFixture.makeMaster()
        let mapId = fixture.currentMapId
        let reference = await fixture.root.mapRoot.mapGameControllable.shareMap(id: mapId)
        let failed = fixture.playerMessage(
            counter: 43,
            type: .reveal,
            subType: .failed,
            data: reference
        )

        // When
        let response = try await fixture.master.handleMap(failed)

        // Then
        #expect(response == nil)
        #expect(fixture.directMasterSpy.sendResponseHistory.isEmpty)
        #expect(fixture.root.mapRoot.gameControllable.gameModel.playerReport(for: mapId).isEmpty)
        #expect(
            !fixture.master.gameModel.hasSentGameItem(
                type: .map,
                id: mapId,
                version: reference.effectiveAssetVersion
            )
        )
    }

    @Test("Map pin commands require the current Map and its exact generations")
    func mapPinIsCurrentAndGenerationFenced() async throws {
        // Given
        let fixture = try await MapMasterRoutingFixture.makeMaster()
        let mapIds = fixture.root.mapRoot.itemController.itemDataModel.items
        let currentMapId = fixture.currentMapId
        let otherMapId = try #require(mapIds.first { $0 != currentMapId })
        let currentMap = fixture.root.mapRoot.gameController.gameItem(for: currentMapId)
        let otherMap = fixture.root.mapRoot.gameController.gameItem(for: otherMapId)
        let currentPin = MapPinModel(
            id: fixture.playerId,
            name: "Player pin",
            location: .zero,
            isPlayer: true,
            players: [fixture.playerId],
            timeInterval: 1
        )
        currentMap.mapPins.append(currentPin)
        fixture.root.mapRoot.gameController.mapGameModel.playerPins.append(currentPin)

        _ = await fixture.root.mapRoot.gameController.setCurrent(itemId: otherMapId)
        var otherPin = currentPin
        otherPin.location = CGPoint(x: 3, y: 4)
        otherMap.mapPins.append(otherPin)
        _ = await fixture.root.mapRoot.gameController.setCurrent(itemId: currentMapId)

        let reference = await fixture.root.mapRoot.mapGameControllable.shareMap(id: currentMapId)
        let otherReference = await fixture.root.mapRoot.mapGameControllable.shareMap(id: otherMapId)
        let contentVersion = try #require(reference.contentVersion)
        let assetVersion = try #require(reference.assetVersion)
        let otherContentVersion = try #require(otherReference.contentVersion)
        let otherAssetVersion = try #require(otherReference.assetVersion)
        var incomingPin = currentPin
        incomingPin.location = CGPoint(x: 10, y: 12)
        incomingPin.timeInterval = 2

        func command(
            id: UUID = currentMapId,
            contentVersion: Int?,
            assetVersion: Int?
        ) -> GameNetworkModel {
            fixture.playerMessage(
                counter: 50,
                type: .update,
                subType: .mapPin,
                data: NetworkCodableDataType(
                    id: id,
                    type: .map,
                    version: currentMap.version,
                    data: incomingPin.encodeData(),
                    assetVersion: assetVersion,
                    contentVersion: contentVersion
                )
            )
        }

        // When: missing, structurally stale, asset-stale, and non-current
        // commands arrive before the one matching command.
        _ = try await fixture.master.handleMap(command(contentVersion: nil, assetVersion: assetVersion))
        _ = try await fixture.master.handleMap(command(contentVersion: contentVersion, assetVersion: nil))
        _ = try await fixture.master.handleMap(command(
            contentVersion: differentVersion(from: contentVersion),
            assetVersion: assetVersion
        ))
        _ = try await fixture.master.handleMap(command(
            contentVersion: contentVersion,
            assetVersion: differentVersion(from: assetVersion)
        ))
        _ = try await fixture.master.handleMap(command(
            id: otherMapId,
            contentVersion: otherContentVersion,
            assetVersion: otherAssetVersion
        ))

        // Then: no stale command changed either Map.
        #expect(currentMap.mapPins.first { $0.id == fixture.playerId }?.location == .zero)
        #expect(otherMap.mapPins.first { $0.id == fixture.playerId }?.location == otherPin.location)

        // When
        _ = try await fixture.master.handleMap(command(
            contentVersion: contentVersion,
            assetVersion: assetVersion
        ))

        // Then
        #expect(currentMap.mapPins.first { $0.id == fixture.playerId }?.location == incomingPin.location)
        let broadcasts = fixture.directMasterSpy.sendResponseHistory.compactMap {
            $0 as? GameNetworkModel
        }
        #expect(broadcasts.count == 1)
        let broadcast = try #require(broadcasts.first)
        #expect(broadcast.type == .update)
        #expect(broadcast.subType == .mapState)
        #expect(broadcast.targetId == nil)
        let expectedBroadcast = fixture.root.mapRoot.gameController.networkMapUpdate(
            for: currentMapId
        )
        #expect(broadcast.data.id == expectedBroadcast.id)
        #expect(broadcast.data.type == expectedBroadcast.type)
        #expect(broadcast.data.version == expectedBroadcast.version)
        #expect(broadcast.data.assetVersion == expectedBroadcast.assetVersion)
        #expect(broadcast.data.contentVersion == expectedBroadcast.contentVersion)

        // `Color` may use a different, but semantically equivalent, JSON
        // representation each time mapState is encoded. Decode the live-state
        // payload instead of comparing its bytes so this verifies the pin the
        // master actually authorized and rebroadcast.
        let broadcastText = try #require(
            broadcast.data.data.flatMap { String(data: $0, encoding: .utf8) }
        )
        let pinArrayStart = try #require(broadcastText.firstIndex(of: "["))
        let broadcastPins = try JSONDecoder().decode(
            [MapPinModel].self,
            from: Data(broadcastText[pinArrayStart...].utf8)
        )
        let broadcastPin = try #require(
            broadcastPins.dropFirst().first { $0.id == fixture.playerId }
        )
        #expect(broadcastPin.id == incomingPin.id)
        #expect(broadcastPin.location == incomingPin.location)
        #expect(broadcastPin.timeInterval == incomingPin.timeInterval)
        #expect(broadcastPin.isPlayer == incomingPin.isPlayer)
        #expect(broadcastPin.players == incomingPin.players)
    }

    @Test("A player reuses the accepted Map generation for pin updates")
    func playerPinUsesAuthoritativeImportedGeneration() async throws {
        // Given: the master exports one complete generation containing the
        // player's authoritative session pin.
        let fixture = try await MapMasterRoutingFixture.makeMaster()
        let mapId = fixture.currentMapId
        let masterMap = fixture.root.mapRoot.gameController.gameItem(for: mapId)
        let initialPin = MapPinModel(
            id: fixture.playerId,
            name: fixture.playerName,
            location: CGPoint(x: 4, y: 6),
            isShown: true,
            isPlayer: true,
            players: [fixture.playerId],
            timeInterval: 1
        )
        masterMap.mapPins.removeAll { $0.id == fixture.playerId }
        masterMap.mapPins.append(initialPin)
        let fullMap = try await fixture.root.mapRoot.mapGameControllable.createMapGameData(
            for: mapId
        )

        // And: a separate player root imports that package through the real
        // PlayerController path, which records the sender-computed generation.
        let playerRoot = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: playerRoot.adventureRoot)
        try await MockRoot.resetGameController(for: playerRoot)
        playerRoot.gameModel.reset(
            gameConfig: GameConfigModel(
                id: fixture.playerId,
                state: .started,
                master: MasterGameModel(
                    id: fixture.masterId,
                    type: .master,
                    name: "Map master"
                )
            ),
            gameRoster: GameRosterModel(players: [
                PlayerGameModel(
                    id: fixture.playerId,
                    type: .player,
                    name: fixture.playerName
                ),
            ])
        )
        let player = PlayerController(root: playerRoot, asGameMaster: false)
        let show = GameNetworkModel(
            counter: 80,
            proxyCounter: 0,
            type: .reveal,
            subType: .show,
            masterId: fixture.masterId,
            sender: GameSenderModel(
                id: fixture.masterId,
                role: .master,
                name: "Map master",
                characterId: nil
            ),
            data: fullMap
        )
        _ = try await player.handleMap(show)

        let playerMap = playerRoot.mapRoot.gameController.gameItem(for: mapId)
        // Simulate a cross-platform Codable normalization difference. The
        // locally recomputed content digest is deliberately not authoritative.
        playerMap.pinScale += 0.125
        #expect(
            playerRoot.mapRoot.gameController.mapContentVersion(for: mapId)
                != fullMap.contentVersion
        )

        // When: the player moves its pin and builds the ordinary UI payload.
        let movedLocation = CGPoint(x: 31, y: 47)
        #expect(playerRoot.mapRoot.gameController.movePin(
            itemId: mapId,
            pinId: fixture.playerId,
            location: movedLocation
        ))
        let playerUpdate = try #require(
            playerRoot.mapRoot.gameController.networkPin(
                itemId: mapId,
                pinId: fixture.playerId
            )
        )

        // Then: the payload retains the accepted master's generation instead
        // of the player's divergent local digest, so the master authorizes it.
        #expect(playerUpdate.version == fullMap.version)
        #expect(playerUpdate.assetVersion == fullMap.assetVersion)
        #expect(playerUpdate.contentVersion == fullMap.contentVersion)
        let proxyReplay = playerRoot.mapRoot.gameController.networkMapUpdate(for: mapId)
        #expect(proxyReplay.version == fullMap.version)
        #expect(proxyReplay.assetVersion == fullMap.assetVersion)
        #expect(proxyReplay.contentVersion == fullMap.contentVersion)

        // A proxy host validates its private client against that same cached
        // master token, rather than its divergent local Map representation.
        var proxyPin = try #require(MapPinModel.decodeData(of: playerUpdate.data))
        proxyPin.isHighlighted.toggle()
        proxyPin.timeInterval = proxyPin.timeInterval.nextUp
        let proxyUpdate = NetworkCodableDataType(
            id: mapId,
            type: .map,
            version: fullMap.version,
            data: proxyPin.encodeData(),
            assetVersion: fullMap.assetVersion,
            contentVersion: fullMap.contentVersion
        )
        #expect(playerRoot.mapRoot.gameController.updatePinIfCurrentGeneration(
            itemId: mapId,
            data: proxyUpdate,
            playerId: fixture.playerId
        ))

        let command = fixture.playerMessage(
            counter: 81,
            type: .update,
            subType: .mapPin,
            data: playerUpdate
        )
        _ = try await fixture.master.handleMap(command)
        #expect(
            masterMap.mapPins.first { $0.id == fixture.playerId }?.location
                == movedLocation
        )

        let highlightedUpdate = try #require(
            playerRoot.mapRoot.gameController.networkPin(
                itemId: mapId,
                pinId: fixture.playerId
            )
        )
        _ = try await fixture.master.handleMap(fixture.playerMessage(
            counter: 82,
            type: .update,
            subType: .mapPin,
            data: highlightedUpdate
        ))
        #expect(
            masterMap.mapPins.first { $0.id == fixture.playerId }?.isHighlighted
                == true
        )
        #expect(
            fixture.directMasterSpy.sendResponseHistory
                .compactMap { $0 as? GameNetworkModel }
                .contains { $0.type == .update && $0.subType == .mapState }
        )
    }

    @Test("Proxy serves only a complete Map matching the requested asset and content generations")
    func proxyMapRepairChecksVersions() async throws {
        // Given
        let fixture = try await MapMasterRoutingFixture.makeProxyHost()
        let mapId = fixture.currentMapId
        let reference = await fixture.root.mapRoot.mapGameControllable.shareMap(id: mapId)
        let assetVersion = try #require(reference.assetVersion)
        let contentVersion = try #require(reference.contentVersion)

        func request(counter: Int, assetVersion: Int, contentVersion: Int) -> GameNetworkModel {
            fixture.proxyMessage(
                counter: counter,
                type: .reveal,
                subType: .show,
                data: NetworkCodableDataType(
                    id: mapId,
                    type: .map,
                    version: reference.version,
                    assetVersion: assetVersion,
                    contentVersion: contentVersion
                )
            )
        }

        // When: either requested generation differs from the host copy.
        await fixture.master.receivedServerProxy(request(
            counter: 61,
            assetVersion: differentVersion(from: assetVersion),
            contentVersion: contentVersion
        ))
        await fixture.master.receivedServerProxy(request(
            counter: 62,
            assetVersion: assetVersion,
            contentVersion: differentVersion(from: contentVersion)
        ))

        // Then: both requests go to the real master and no stale package is
        // served to the proxy client.
        #expect(fixture.directPlayerSpy.calledRequest == 2)
        #expect(fixture.proxyMasterSpy.calledSendResponseAll == 0)
        let forwarded = fixture.directPlayerSpy.requestHistory.compactMap { $0 as? GameNetworkModel }
        #expect(forwarded.count == 2)
        #expect(forwarded.first?.data.assetVersion == differentVersion(from: assetVersion))
        #expect(forwarded.first?.data.contentVersion == contentVersion)
        #expect(forwarded.last?.data.assetVersion == assetVersion)
        #expect(forwarded.last?.data.contentVersion == differentVersion(from: contentVersion))

        // When: the exact local generations are requested.
        await fixture.master.receivedServerProxy(request(
            counter: 63,
            assetVersion: assetVersion,
            contentVersion: contentVersion
        ))

        // Then
        #expect(fixture.directPlayerSpy.calledRequest == 2)
        #expect(fixture.proxyMasterSpy.calledSendResponseAll == 1)
        let localResponse = try #require(fixture.proxyMasterSpy.sendResponseData as? GameNetworkModel)
        #expect(localResponse.sender.isMaster)
        #expect(localResponse.targetId == fixture.proxyPlayerId)
        #expect(localResponse.data.id == mapId)
        #expect(localResponse.data.assetVersion == assetVersion)
        #expect(localResponse.data.contentVersion == contentVersion)
        #expect(localResponse.data.data != nil)
    }

    @Test("Proxy remaps an exact Map request when its background bytes are unavailable")
    func proxyMapRepairRejectsMissingBackgroundData() async throws {
        // Given
        let fixture = try await MapMasterRoutingFixture.makeProxyHost()
        let mapId = fixture.currentMapId
        let reference = await fixture.root.mapRoot.mapGameControllable.shareMap(id: mapId)
        let backgroundId = try #require(
            fixture.root.mapRoot.gameController.gameItem(for: mapId).photoId
        )
        let background = fixture.root.photoRoot.gameController.gameItem(for: backgroundId)
        let originalFile = try #require(background.fileUrl)
        let contentHash = try #require(originalFile.contentHash)
        background.fileUrl = unavailableFileUrl(
            preserving: originalFile,
            contentHash: contentHash,
            path: "/missing/proxy-map-background.png"
        )
        let localReference = await fixture.root.mapRoot.mapGameControllable.shareMap(id: mapId)
        #expect(localReference.assetVersion == reference.assetVersion)
        #expect(localReference.contentVersion == reference.contentVersion)
        #expect(
            await !fixture.root.mapRoot.mapGameControllable.hasBackgroundImage(itemId: mapId)
        )
        let request = fixture.proxyMessage(
            counter: 64,
            type: .reveal,
            subType: .show,
            data: reference
        )

        // When
        await fixture.master.receivedServerProxy(request)

        // Then
        #expect(fixture.proxyMasterSpy.calledSendResponseAll == 0)
        #expect(fixture.directPlayerSpy.calledRequest == 1)
        let forwarded = try #require(fixture.directPlayerSpy.requestData as? GameNetworkModel)
        #expect(forwarded.data.assetVersion == reference.assetVersion)
        #expect(forwarded.data.contentVersion == reference.contentVersion)
    }

    @Test("Proxy remaps an exact Map request when a pin Photo has no local bytes")
    func proxyMapRepairRejectsMissingPinPhotoData() async throws {
        // Given
        let fixture = try await MapMasterRoutingFixture.makeProxyHost()
        let mapId = fixture.currentMapId
        let map = fixture.root.mapRoot.gameController.gameItem(for: mapId)
        let backgroundId = try #require(map.photoId)
        _ = await fixture.root.photoRoot.gameControllable.share(id: backgroundId)
        let backgroundFile = try #require(
            fixture.root.photoRoot.gameController.gameItem(for: backgroundId).fileUrl
        )
        let contentHash = try #require(backgroundFile.contentHash)
        let pinPhotoId = UUID()
        let pinPhoto = PhotoModel(
            id: pinPhotoId,
            name: "Proxy pin Photo",
            fileUrl: backgroundFile
        )
        fixture.root.photoRoot.itemController.replace(
            model: pinPhoto,
            isInsert: true
        )
        map.mapPins.append(
            MapPinModel(
                id: UUID(),
                name: "Photo pin",
                photoId: pinPhotoId,
                location: .zero
            )
        )
        let reference = await fixture.root.mapRoot.mapGameControllable.shareMap(id: mapId)
        pinPhoto.fileUrl = unavailableFileUrl(
            preserving: backgroundFile,
            contentHash: contentHash,
            path: "/missing/proxy-map-pin-photo.png"
        )
        let localReference = await fixture.root.mapRoot.mapGameControllable.shareMap(id: mapId)
        #expect(localReference.assetVersion == reference.assetVersion)
        #expect(localReference.contentVersion == reference.contentVersion)
        #expect(await fixture.root.mapRoot.mapGameControllable.hasBackgroundImage(itemId: mapId))
        #expect(
            await fixture.root.mapRoot.mapGameControllable.missingMapImages(itemId: mapId).contains {
                $0.id == pinPhotoId
            }
        )
        let request = fixture.proxyMessage(
            counter: 65,
            type: .reveal,
            subType: .show,
            data: reference
        )

        // When
        await fixture.master.receivedServerProxy(request)

        // Then
        #expect(fixture.proxyMasterSpy.calledSendResponseAll == 0)
        #expect(fixture.directPlayerSpy.calledRequest == 1)
        let forwarded = try #require(fixture.directPlayerSpy.requestData as? GameNetworkModel)
        #expect(forwarded.data.assetVersion == reference.assetVersion)
        #expect(forwarded.data.contentVersion == reference.contentVersion)
    }

    @Test("A matching Character reference republishes refreshed player-pin metadata")
    func characterReferenceRefreshesMapPin() async throws {
        try await assertCharacterCompletionRefreshesMapPin(includesPackage: false)
    }

    @Test("A full Character package republishes refreshed player-pin metadata")
    func characterPackageRefreshesMapPin() async throws {
        try await assertCharacterCompletionRefreshesMapPin(includesPackage: true)
    }

    private func assertCharacterCompletionRefreshesMapPin(includesPackage: Bool) async throws {
        // Given
        let characterId = UUID()
        let photoId = UUID()
        let playerPackage: NetworkCodableDataType?
        if includesPackage {
            // Build the upload on a separate player root. The master must not
            // already own this Character: this is the normal mismatched/missing
            // bootstrap path that the full package is meant to complete.
            let playerRoot = try await MockRoot.createGameRoot()
            Self.insertCharacter(
                id: characterId,
                photoId: photoId,
                into: playerRoot
            )
            #expect(playerRoot.photoRoot.itemController.itemDataModel.items.contains(photoId))
            #expect(playerRoot.characterRoot.itemController.itemSync(
                for: characterId,
                noGame: true
            )?.photoId == photoId)
            let exportedIds = playerRoot.characterRoot.exportControllable.exporting(
                itemIds: ItemModuleIds(ids: [characterId], module: .value)
            )
            #expect(exportedIds.ids[.photo]?.contains(photoId) == true)
            playerPackage = try await playerRoot.characterRoot.gameControllable.createGameData(
                for: characterId
            )
        } else {
            playerPackage = nil
        }

        let fixture = try await MapMasterRoutingFixture.makeMaster()
        if !includesPackage {
            Self.insertCharacter(
                id: characterId,
                photoId: photoId,
                into: fixture.root
            )
        }
        let mapId = fixture.currentMapId
        let stalePin = MapPinModel(
            id: fixture.playerId,
            name: "Bootstrap pin",
            photoId: nil,
            characterId: nil,
            isPlayer: true,
            players: [fixture.playerId]
        )
        fixture.root.mapRoot.gameController.gameItem(for: mapId).mapPins.append(stalePin)
        fixture.root.mapRoot.gameController.mapGameModel.playerPins.append(stalePin)
        let package = if let playerPackage {
            playerPackage
        } else {
            try await fixture.root.characterRoot.gameControllable.createGameData(for: characterId)
        }
        let data = if includesPackage {
            package
        } else {
            NetworkCodableDataType(
                id: package.id,
                type: package.type,
                version: package.version
            )
        }
        let message = fixture.playerMessage(
            counter: includesPackage ? 72 : 71,
            type: .update,
            subType: .store,
            characterId: characterId,
            data: data
        )
        #expect(message.senderType == .player)
        #expect(message.sender.characterId == characterId)
        #expect(message.data.id == characterId)
        #expect((message.data.data != nil) == includesPackage)

        // When
        let response = try await fixture.master.handleValue(message)

        // Then
        #expect(response == nil)
        if includesPackage {
            #expect(fixture.root.photoRoot.itemController.itemDataModel.items.contains(photoId))
            #expect(fixture.root.characterRoot.itemController.itemSync(
                for: characterId,
                noGame: true
            )?.photoId == photoId)
        }
        let refreshedPin = try #require(
            fixture.root.mapRoot.gameController.gameItem(for: mapId).mapPins.first {
                $0.id == fixture.playerId
            }
        )
        #expect(refreshedPin.name == fixture.playerName)
        #expect(refreshedPin.characterId == characterId)
        #expect(refreshedPin.photoId == photoId)

        let broadcasts = fixture.directMasterSpy.sendResponseHistory.compactMap { $0 as? GameNetworkModel }
        #expect(broadcasts.map(\.subType) == [.generic, .mapState])
        #expect(broadcasts.allSatisfy { $0.type == .update && $0.data.id == mapId })
        #expect(broadcasts.first?.data.contentVersion == broadcasts.last?.data.contentVersion)
    }

    private static func insertCharacter(id: UUID, photoId: UUID, into root: GameRoot) {
        root.photoRoot.itemController.replace(
            model: PhotoModel(id: photoId, name: "Player portrait"),
            isInsert: true,
            forceSave: true
        )
        root.characterRoot.itemController.replace(
            model: ValueModel(
                id: id,
                name: "Player Character",
                category: .character,
                photoId: photoId,
                photos: [photoId]
            ),
            isInsert: true,
            forceSave: true
        )
    }
}

@MainActor
private struct MapMasterRoutingFixture {
    let root: GameRoot
    let master: MasterController
    let directMasterSpy: MasterNetworkControllableMock
    let directPlayerSpy: PlayerStoreAbstractionMock
    let proxyMasterSpy: MasterNetworkControllableMock
    let playerId: UUID
    let proxyPlayerId: UUID
    let playerName: String
    let currentMapId: UUID
    let masterId: UUID

    static func makeMaster() async throws -> Self {
        let base = try await makeBase()
        let masterConfig = GameConfigModel(
            id: base.masterId,
            state: .started,
            master: MasterGameModel(
                id: base.masterId,
                type: .master,
                name: "Map master"
            )
        )
        base.root.gameModel.reset(
            gameConfig: masterConfig,
            gameRoster: GameRosterModel(players: [
                PlayerGameModel(
                    id: base.playerId,
                    type: .player,
                    name: base.playerName
                ),
            ])
        )
        let master = MasterController(root: base.root, asProxy: false)
        let currentMapId = try await prepareMap(in: base.root)
        return Self(
            root: base.root,
            master: master,
            directMasterSpy: base.directMasterSpy,
            directPlayerSpy: base.directPlayerSpy,
            proxyMasterSpy: base.proxyMasterSpy,
            playerId: base.playerId,
            proxyPlayerId: base.proxyPlayerId,
            playerName: base.playerName,
            currentMapId: currentMapId,
            masterId: base.masterId
        )
    }

    static func makeProxyHost() async throws -> Self {
        let base = try await makeBase()
        let masterModel = MasterGameModel(
            id: base.masterId,
            type: .master,
            name: "Map master"
        )
        base.root.gameModel.reset(
            gameConfig: GameConfigModel(
                id: base.playerId,
                state: .started,
                master: masterModel
            ),
            gameRoster: GameRosterModel(players: [
                PlayerGameModel(
                    id: base.playerId,
                    type: .player,
                    name: base.playerName
                ),
            ])
        )
        let player = PlayerController(root: base.root, asGameMaster: false)
        base.root.gameModel.playerController = player
        let master = try #require(player.proxyMasterController)
        let currentMapId = try await prepareMap(in: base.root)
        return Self(
            root: base.root,
            master: master,
            directMasterSpy: base.directMasterSpy,
            directPlayerSpy: base.directPlayerSpy,
            proxyMasterSpy: base.proxyMasterSpy,
            playerId: base.playerId,
            proxyPlayerId: base.proxyPlayerId,
            playerName: base.playerName,
            currentMapId: currentMapId,
            masterId: base.masterId
        )
    }

    func playerMessage(
        counter: Int,
        type: RPGMessageType,
        subType: RPGMessageActionType,
        characterId: UUID? = nil,
        data: NetworkCodableDataType
    ) -> GameNetworkModel {
        GameNetworkModel(
            counter: counter,
            proxyCounter: 0,
            type: type,
            subType: subType,
            masterId: masterId,
            sender: GameSenderModel(
                id: playerId,
                role: .player,
                name: playerName,
                characterId: characterId
            ),
            data: data
        )
    }

    func proxyMessage(
        counter: Int,
        type: RPGMessageType,
        subType: RPGMessageActionType,
        data: NetworkCodableDataType
    ) -> GameNetworkModel {
        GameNetworkModel(
            counter: counter,
            proxyCounter: 1,
            type: type,
            subType: subType,
            masterId: masterId,
            sender: GameSenderModel(
                id: proxyPlayerId,
                role: .proxy,
                name: "Proxy mirror",
                characterId: nil
            ),
            data: data
        )
    }

    private static func prepareMap(in root: GameRoot) async throws -> UUID {
        try await MockRoot.importTestData(into: root.adventureRoot)
        root.adventureRoot.startGame()
        let mapId = try #require(root.mapRoot.itemController.itemDataModel.items.first)
        _ = await root.mapRoot.gameController.setCurrent(itemId: mapId)
        return mapId
    }

    private static func makeBase() async throws -> (
        root: GameRoot,
        directMasterSpy: MasterNetworkControllableMock,
        directPlayerSpy: PlayerStoreAbstractionMock,
        proxyMasterSpy: MasterNetworkControllableMock,
        playerId: UUID,
        proxyPlayerId: UUID,
        playerName: String,
        masterId: UUID
    ) {
        let root = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: root.adventureRoot)
        try await MockRoot.resetGameController(for: root)

        let directMasterSpy = MasterNetworkControllableMock()
        let directPlayerSpy = PlayerStoreAbstractionMock()
        let proxyMasterSpy = MasterNetworkControllableMock()
        root.networkStore = GameNetworkController(
            name: "Map direct routing",
            proxy: false,
            masterBuilder: { _, _ in directMasterSpy },
            playerBuilder: { _, _ in directPlayerSpy }
        )
        root.networkProxyStore = GameNetworkController(
            name: "Map proxy routing",
            proxy: true,
            masterBuilder: { _, _ in proxyMasterSpy },
            playerBuilder: { _, _ in PlayerStoreAbstractionMock() }
        )
        return (
            root: root,
            directMasterSpy: directMasterSpy,
            directPlayerSpy: directPlayerSpy,
            proxyMasterSpy: proxyMasterSpy,
            playerId: UUID(),
            proxyPlayerId: UUID(),
            playerName: "Map player",
            masterId: UUID()
        )
    }
}

private func differentVersion(from version: Int) -> Int {
    version == .max ? version - 1 : version + 1
}

private func unavailableFileUrl(
    preserving fileUrl: FileUrl,
    contentHash: String,
    path: String
) -> FileUrl {
    FileUrl(
        fileId: fileUrl.fileId,
        url: URL(filePath: path),
        location: fileUrl.location,
        module: fileUrl.module,
        relativeUrl: nil,
        contentHash: contentHash
    )
}
#endif
