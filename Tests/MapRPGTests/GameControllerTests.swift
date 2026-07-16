// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import MapRPG
@testable import PhotoRPG

@MainActor
struct GameControllerTests {
    @Test func mapStatePinsDemoAndSave() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let mapId = UUID()
        let oldPlayerId = UUID()
        let playerId = UUID()
        let characterId = UUID()
        let photoId = UUID()
        let roomEntry = MapEntryModel.fixture(name: "Room", content: "One")
        let hiddenEntry = MapEntryModel.fixture(name: "Hidden", content: "Two")
        let stalePin = MapPinModel(id: oldPlayerId, name: "Old Player", isPlayer: true, players: [oldPlayerId], timeInterval: 1)
        let map = MapModel(id: mapId, name: "Dungeon", entries: [roomEntry, hiddenEntry], mapPins: [stalePin])

        root.itemController.replace(model: map, isInsert: true)
        sut.setGame(item: map.copy(), itemId: mapId)

        #expect(sut.currentItem().id == mapId)
        #expect(sut.gameItem(for: mapId).entries.count == 2)

        sut.mapGameModel.playerPins = [stalePin]
        sut.setPlayerPin(for: playerId, name: "Hero", characterId: characterId)
        #expect(sut.mapGameModel.playerPins.map(\.id).contains(playerId))

        sut.resetPlayerPins(for: [PlayerGameModel(id: playerId, type: .player, name: "Hero", characterId: characterId)])
        #expect(!sut.mapGameModel.playerPins.map(\.id).contains(oldPlayerId))
        #expect(sut.gameItem(for: mapId).mapPins.map(\.id).contains(playerId))

        let updatedPin = MapPinModel(
            id: playerId,
            name: "Hero",
            location: CGPoint(x: 12, y: 34),
            isPlayer: true,
            players: [playerId],
            timeInterval: 10
        )
        #expect(sut.updatePin(itemId: mapId, data: updatedPin.encodeData(), playerId: playerId))
        #expect(sut.gameItem(for: mapId)[MapPinId.id, playerId].location == CGPoint(x: 12, y: 34))

        let staleUpdate = MapPinModel(
            id: playerId,
            name: "Hero",
            location: CGPoint(x: 90, y: 90),
            isPlayer: true,
            players: [playerId],
            timeInterval: 2
        )
        #expect(!sut.updatePin(itemId: mapId, data: staleUpdate.encodeData(), playerId: playerId))
        #expect(sut.gameItem(for: mapId)[MapPinId.id, playerId].location == CGPoint(x: 12, y: 34))

        let demoUpdate = try #require(sut.demoNextMap(itemId: mapId, restart: false))
        #expect(demoUpdate.type == .map)
        #expect(sut.gameItem(for: mapId)[roomEntry.id].isShown)

        let snapshot = sut.networkMapUpdate(for: mapId)
        #expect(snapshot.version == sut.gameItem(for: mapId).version)
        sut.gameItem(for: mapId).entries[0].isShown = false
        sut.updateMap(for: mapId, with: snapshot)
        #expect(sut.gameItem(for: mapId)[roomEntry.id].isShown)

        // The first pin photo exists only in the persistent photo controller
        // and intentionally has no local file. SharePlay must not request it;
        // the second photo is absent from both photo controllers.
        let unavailableFile = FileUrl(
            fileId: UUID(),
            url: URL.temporaryDirectory.appending(path: "missing-\(UUID().uuidString).jpg"),
            location: .local,
            module: NetworkModules.photo.token,
            relativeUrl: nil
        )
        root.photoRoot.itemController.replace(
            model: PhotoModel(
                id: photoId,
                name: "Existing metadata-only photo",
                fileUrl: unavailableFile
            ),
            isInsert: true
        )
        #expect(root.photoRoot.gameController.gameModel.itemData[photoId] == nil)
        #expect(root.photoRoot.itemController.itemSync(for: photoId, noGame: true) != nil)
        #expect(await !root.photoRoot.gameController.hasLocalFileData(for: photoId))

        let monsterPhotoId = UUID()
        sut.gameItem(for: mapId).mapPins = [
            MapPinModel(id: playerId, name: "Hero", photoId: photoId, isPlayer: true, players: [playerId]),
            MapPinModel(id: UUID(), name: "Monster", photoId: monsterPhotoId)
        ]
        let missingBackgroundPhotoId = UUID()
        sut.gameItem(for: mapId).photoId = missingBackgroundPhotoId
        let missingImages = await sut.missingMapImages(itemId: mapId)
        #expect(missingImages.map(\.id) == [monsterPhotoId])
        #expect(!missingImages.map(\.id).contains(missingBackgroundPhotoId))
        #expect(root.photoRoot.gameController.gameModel.itemData[photoId] != nil)

        // Background availability is checked separately and never turns into a
        // pin-photo repair. Both an unknown background and missing local bytes
        // make the full map incomplete.
        #expect(await !sut.hasBackgroundImage(itemId: mapId))
        sut.gameItem(for: mapId).photoId = photoId
        #expect(await !sut.hasBackgroundImage(itemId: mapId))
        sut.gameItem(for: mapId).photoId = nil
        #expect(await sut.hasBackgroundImage(itemId: mapId))

        _ = sut.demoNextMap(itemId: mapId, restart: true)
        _ = sut.saveAll()
        #expect(sut.gameItem(for: mapId).mapPins.allSatisfy { !$0.isPlayer })

        sut.resetGameState()
        #expect(sut.mapGameModel.playerPins.isEmpty)
    }

    @Test func mapContentVersionTracksStructureButIgnoresVolatileGameState() async throws {
        // Given
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let mapId = UUID()
        let entry = MapEntryModel.fixture(
            name: "Room",
            coordinates: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 10, y: 0),
                CGPoint(x: 10, y: 10)
            ]
        )
        let pin = MapPinModel(
            id: UUID(),
            name: "Hero",
            location: CGPoint(x: 2, y: 3),
            isPlayer: true,
            timeInterval: 10
        )
        let map = MapModel(id: mapId, name: "Dungeon", entries: [entry], mapPins: [pin])
        root.itemController.replace(model: map, isInsert: true)
        sut.setGame(item: map.copy(), itemId: mapId)
        let gameMap = sut.gameItem(for: mapId)
        let initialVersion = try #require(
            await sut.networkMapContentUpdate(for: mapId).contentVersion
        )

        // When: only live game state changes.
        gameMap.entries[0].isShown.toggle()
        gameMap.entries[0].focused.toggle()
        gameMap.pointer = MapPinModel(
            id: UUID(),
            name: "Pointer",
            location: CGPoint(x: 7, y: 8),
            isShown: true,
            timeInterval: 20
        )
        gameMap.mapPins[0].location = CGPoint(x: 30, y: 40)
        gameMap.mapPins[0].isShown.toggle()
        gameMap.mapPins[0].isZoom.toggle()
        gameMap.mapPins[0].isHighlighted.toggle()
        gameMap.mapPins[0].timeInterval = 30
        let volatileStateVersion = try #require(
            await sut.networkMapContentUpdate(for: mapId).contentVersion
        )

        // Then
        #expect(volatileStateVersion == initialVersion)

        // When: persistent death state and other structural fields change.
        gameMap.mapPins[0].isDead.toggle()
        let deadStateVersion = try #require(
            await sut.networkMapContentUpdate(for: mapId).contentVersion
        )
        gameMap.pinScale += 0.5
        gameMap.hexMapScale += 0.25
        let scaleVersion = try #require(
            await sut.networkMapContentUpdate(for: mapId).contentVersion
        )
        gameMap.entries[0].coordinates.append(CGPoint(x: 0, y: 10))
        let geometryVersion = try #require(
            await sut.networkMapContentUpdate(for: mapId).contentVersion
        )
        gameMap.mapPins.append(MapPinModel(id: UUID(), name: "Monster"))
        let pinIdentityVersion = try #require(
            await sut.networkMapContentUpdate(for: mapId).contentVersion
        )

        // Then
        #expect(deadStateVersion != volatileStateVersion)
        #expect(scaleVersion != deadStateVersion)
        #expect(geometryVersion != scaleVersion)
        #expect(pinIdentityVersion != geometryVersion)
    }

    @Test func applyingMapContentUpdatePreservesPointerAndNewerLocalPlayerPin() async throws {
        // Given
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let mapId = UUID()
        let pinId = UUID()
        let authoritativePhotoId = UUID()
        let authoritativePin = MapPinModel(
            id: pinId,
            name: "Authoritative Hero",
            photoId: authoritativePhotoId,
            location: CGPoint(x: 10, y: 20),
            size: .large,
            isPlayer: true,
            players: [pinId],
            timeInterval: 10
        )
        let map = MapModel(
            id: mapId,
            name: "Dungeon",
            mapPins: [authoritativePin],
            pinScale: 2,
            hexMapScale: 0.5
        )
        root.itemController.replace(model: map, isInsert: true)
        sut.setGame(item: map.copy(), itemId: mapId)
        let contentUpdate = await sut.networkMapContentUpdate(for: mapId)

        let playerMap = sut.gameItem(for: mapId)
        let retainedIdentity = playerMap
        let localPointer = MapPinModel(
            id: UUID(),
            name: "Pointer",
            location: CGPoint(x: 50, y: 60),
            isShown: true,
            timeInterval: 100
        )
        let newerLocalPin = MapPinModel(
            id: pinId,
            name: "Stale local Hero",
            photoId: UUID(),
            location: CGPoint(x: 70, y: 80),
            size: .tiny,
            isShown: false,
            isPlayer: true,
            timeInterval: 100,
            isZoom: true,
            isDead: true,
            isHighlighted: true
        )
        playerMap.pointer = localPointer
        playerMap.mapPins[0] = newerLocalPin
        playerMap.pinScale = 1
        playerMap.hexMapScale = 0

        // When
        let applied = sut.applyMapContentUpdate(for: mapId, with: contentUpdate)

        // Then
        #expect(applied)
        #expect(sut.gameItem(for: mapId) === retainedIdentity)
        #expect(playerMap.pinScale == 2)
        #expect(playerMap.hexMapScale == 0.5)
        #expect(playerMap.pointer == localPointer)
        let appliedPin = try #require(playerMap.mapPins.first { $0.id == pinId })
        #expect(appliedPin.name == authoritativePin.name)
        #expect(appliedPin.photoId == authoritativePhotoId)
        #expect(appliedPin.size == newerLocalPin.size)
        #expect(appliedPin.players == [pinId])
        #expect(appliedPin.location == newerLocalPin.location)
        #expect(appliedPin.isShown == newerLocalPin.isShown)
        #expect(appliedPin.isZoom == newerLocalPin.isZoom)
        #expect(appliedPin.isDead == newerLocalPin.isDead)
        #expect(appliedPin.isHighlighted == newerLocalPin.isHighlighted)
        #expect(appliedPin.timeInterval == newerLocalPin.timeInterval)
    }

    @Test func playerPinUpdatesMergeOnlyAuthorizedFields() async throws {
        // Given
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let mapId = UUID()
        let ownerId = UUID()
        let foreignPlayerId = UUID()
        let monsterId = UUID()
        let hiddenMonsterId = UUID()
        let ownerPhotoId = UUID()
        let owner = MapPinModel(
            id: ownerId,
            name: "Owner",
            photoId: ownerPhotoId,
            location: CGPoint(x: 1, y: 2),
            size: .large,
            isShown: false,
            isPlayer: true,
            players: [ownerId],
            timeInterval: 10,
            isDead: true
        )
        let foreignPlayer = MapPinModel(
            id: foreignPlayerId,
            name: "Other Player",
            location: CGPoint(x: 3, y: 4),
            size: .small,
            isPlayer: true,
            players: [foreignPlayerId],
            timeInterval: 10
        )
        let monster = MapPinModel(
            id: monsterId,
            name: "Ogre",
            location: CGPoint(x: 5, y: 6),
            timeInterval: 10
        )
        let hiddenMonster = MapPinModel(
            id: hiddenMonsterId,
            name: "Hidden Dragon",
            location: CGPoint(x: 7, y: 8),
            isShown: false,
            timeInterval: 10
        )
        let map = MapModel(
            id: mapId,
            name: "Dungeon",
            mapPins: [owner, foreignPlayer, monster, hiddenMonster]
        )
        root.itemController.replace(model: map, isInsert: true)
        sut.setGame(item: map.copy(), itemId: mapId)
        sut.mapGameModel.playerPins = [owner, foreignPlayer]

        // When: the owner sends permitted changes alongside spoofed metadata.
        let ownerRequest = MapPinModel(
            id: ownerId,
            name: "Spoofed Owner",
            photoId: UUID(),
            location: CGPoint(x: 20, y: 21),
            size: .tiny,
            isShown: true,
            isPlayer: false,
            players: [],
            timeInterval: 20,
            isZoom: true,
            isDead: false,
            isHighlighted: true
        )
        #expect(sut.updatePin(itemId: mapId, data: ownerRequest.encodeData(), playerId: ownerId))

        // Then: only owned location plus shared zoom/highlight are accepted.
        let updatedOwner = try #require(sut.gameItem(for: mapId).mapPins.first { $0.id == ownerId })
        #expect(updatedOwner.name == owner.name)
        #expect(updatedOwner.photoId == ownerPhotoId)
        #expect(updatedOwner.location == ownerRequest.location)
        #expect(updatedOwner.size == owner.size)
        #expect(updatedOwner.isShown == owner.isShown)
        #expect(updatedOwner.isPlayer)
        #expect(updatedOwner.players == owner.players)
        #expect(updatedOwner.isDead == owner.isDead)
        #expect(updatedOwner.isZoom)
        #expect(updatedOwner.isHighlighted)
        #expect(updatedOwner.timeInterval == ownerRequest.timeInterval)
        #expect(sut.mapGameModel.playerPins.first { $0.id == ownerId } == updatedOwner)

        var staleOwnerRequest = ownerRequest
        staleOwnerRequest.location = CGPoint(x: 90, y: 90)
        staleOwnerRequest.timeInterval = 19
        #expect(!sut.updatePin(itemId: mapId, data: staleOwnerRequest.encodeData(), playerId: ownerId))

        var extremeFutureRequest = updatedOwner
        extremeFutureRequest.isHighlighted.toggle()
        extremeFutureRequest.timeInterval = .greatestFiniteMagnitude
        #expect(!sut.updatePin(itemId: mapId, data: extremeFutureRequest.encodeData(), playerId: ownerId))

        var unauthorizedOnlyRequest = updatedOwner
        unauthorizedOnlyRequest.isDead.toggle()
        unauthorizedOnlyRequest.size = .colossal
        unauthorizedOnlyRequest.timeInterval = 21
        #expect(!sut.updatePin(itemId: mapId, data: unauthorizedOnlyRequest.encodeData(), playerId: ownerId))
        #expect(sut.gameItem(for: mapId)[MapPinId.id, ownerId] == updatedOwner)

        // When: a visible foreign player and monster are targeted.
        var foreignRequest = foreignPlayer
        foreignRequest.location = CGPoint(x: 100, y: 101)
        foreignRequest.size = .colossal
        foreignRequest.isShown = false
        foreignRequest.isZoom = true
        foreignRequest.isDead = true
        foreignRequest.isHighlighted = true
        foreignRequest.timeInterval = 20
        #expect(sut.updatePin(itemId: mapId, data: foreignRequest.encodeData(), playerId: ownerId))

        var monsterRequest = monster
        monsterRequest.location = CGPoint(x: 200, y: 201)
        monsterRequest.size = .colossal
        monsterRequest.isShown = false
        monsterRequest.isZoom = true
        monsterRequest.isDead = true
        monsterRequest.isHighlighted = true
        monsterRequest.timeInterval = 20
        #expect(sut.updatePin(itemId: mapId, data: monsterRequest.encodeData(), playerId: ownerId))

        // Then
        let updatedForeign = try #require(sut.gameItem(for: mapId).mapPins.first { $0.id == foreignPlayerId })
        #expect(updatedForeign.location == foreignPlayer.location)
        #expect(updatedForeign.size == foreignPlayer.size)
        #expect(updatedForeign.isShown)
        #expect(!updatedForeign.isDead)
        #expect(updatedForeign.isZoom)
        #expect(updatedForeign.isHighlighted)
        #expect(sut.mapGameModel.playerPins.first { $0.id == foreignPlayerId } == updatedForeign)

        let updatedMonster = try #require(sut.gameItem(for: mapId).mapPins.first { $0.id == monsterId })
        #expect(updatedMonster.location == monster.location)
        #expect(updatedMonster.size == monster.size)
        #expect(updatedMonster.isShown)
        #expect(!updatedMonster.isDead)
        #expect(updatedMonster.isZoom)
        #expect(updatedMonster.isHighlighted)
        #expect(!sut.mapGameModel.playerPins.map(\.id).contains(monsterId))

        // Hidden foreign and unknown pins are rejected and never inserted.
        var hiddenRequest = hiddenMonster
        hiddenRequest.isZoom = true
        hiddenRequest.isHighlighted = true
        hiddenRequest.timeInterval = 20
        #expect(!sut.updatePin(itemId: mapId, data: hiddenRequest.encodeData(), playerId: ownerId))
        let unknownRequest = MapPinModel(
            id: UUID(),
            name: "Unknown",
            isPlayer: true,
            timeInterval: 20,
            isZoom: true,
            isHighlighted: true
        )
        #expect(!sut.updatePin(itemId: mapId, data: unknownRequest.encodeData(), playerId: ownerId))
        #expect(!sut.updatePin(itemId: mapId, data: nil, playerId: ownerId))
        #expect(sut.gameItem(for: mapId).mapPins.count == 4)
        #expect(Set(sut.mapGameModel.playerPins.map(\.id)) == Set([ownerId, foreignPlayerId]))
    }

    @Test func playerPinUpdateRejectsPersistentMapOutsideActiveGame() async throws {
        // Given
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let mapId = UUID()
        let playerId = UUID()
        let pin = MapPinModel(
            id: playerId,
            name: "Persistent Player",
            isPlayer: true,
            players: [playerId],
            timeInterval: 1
        )
        let map = MapModel(id: mapId, name: "Not Shared", mapPins: [pin])
        root.itemController.replace(model: map, isInsert: true)

        var request = pin
        request.location = CGPoint(x: 40, y: 50)
        request.isZoom = true
        request.isHighlighted = true
        request.timeInterval = 2

        // When / Then
        #expect(!sut.updatePin(itemId: mapId, data: request.encodeData(), playerId: playerId))
        let persistentPin = try #require(
            root.itemController.itemSync(for: mapId)?.mapPins.first
        )
        #expect(persistentPin == pin)
        #expect(sut.gameModel.itemData[mapId] == nil)
    }

    @Test func staleMapStatePreservesOnlyOptimisticPlayerFields() async throws {
        // Given
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let mapId = UUID()
        let playerId = UUID()
        let monsterId = UUID()
        let authoritativePlayer = MapPinModel(
            id: playerId,
            name: "Authoritative Player",
            photoId: UUID(),
            location: CGPoint(x: 1, y: 2),
            size: .large,
            isShown: false,
            isPlayer: true,
            players: [playerId],
            timeInterval: 10,
            isDead: true
        )
        let authoritativeMonster = MapPinModel(
            id: monsterId,
            name: "Authoritative Monster",
            location: CGPoint(x: 3, y: 4),
            size: .huge,
            timeInterval: 10,
            isDead: true
        )
        let map = MapModel(
            id: mapId,
            name: "Dungeon",
            mapPins: [authoritativePlayer, authoritativeMonster]
        )
        root.itemController.replace(model: map, isInsert: true)
        sut.setGame(item: map.copy(), itemId: mapId)
        let staleAuthoritativeState = sut.networkMapUpdate(for: mapId)

        var optimisticPlayer = authoritativePlayer
        optimisticPlayer.name = "Spoofed Local Player"
        optimisticPlayer.photoId = UUID()
        optimisticPlayer.location = CGPoint(x: 50, y: 60)
        optimisticPlayer.size = .tiny
        optimisticPlayer.isShown = true
        optimisticPlayer.isZoom = true
        optimisticPlayer.isDead = false
        optimisticPlayer.isHighlighted = true
        optimisticPlayer.timeInterval = 100

        var optimisticMonster = authoritativeMonster
        optimisticMonster.name = "Spoofed Local Monster"
        optimisticMonster.location = CGPoint(x: 70, y: 80)
        optimisticMonster.size = .tiny
        optimisticMonster.isShown = false
        optimisticMonster.isZoom = true
        optimisticMonster.isDead = false
        optimisticMonster.isHighlighted = true
        optimisticMonster.timeInterval = 100
        sut.gameItem(for: mapId).mapPins = [optimisticPlayer, optimisticMonster]

        // When
        sut.updateMap(for: mapId, with: staleAuthoritativeState)

        // Then: both highlights and zooms survive, but only a player-pin
        // location is optimistic; every game-master field is authoritative.
        let mergedPlayer = try #require(sut.gameItem(for: mapId).mapPins.first { $0.id == playerId })
        #expect(mergedPlayer.name == authoritativePlayer.name)
        #expect(mergedPlayer.photoId == authoritativePlayer.photoId)
        #expect(mergedPlayer.location == optimisticPlayer.location)
        #expect(mergedPlayer.size == authoritativePlayer.size)
        #expect(mergedPlayer.isShown == authoritativePlayer.isShown)
        #expect(mergedPlayer.isDead == authoritativePlayer.isDead)
        #expect(mergedPlayer.isZoom)
        #expect(mergedPlayer.isHighlighted)
        #expect(mergedPlayer.timeInterval == optimisticPlayer.timeInterval)

        let mergedMonster = try #require(sut.gameItem(for: mapId).mapPins.first { $0.id == monsterId })
        #expect(mergedMonster.name == authoritativeMonster.name)
        #expect(mergedMonster.location == authoritativeMonster.location)
        #expect(mergedMonster.size == authoritativeMonster.size)
        #expect(mergedMonster.isShown == authoritativeMonster.isShown)
        #expect(mergedMonster.isDead == authoritativeMonster.isDead)
        #expect(mergedMonster.isZoom)
        #expect(mergedMonster.isHighlighted)
        #expect(mergedMonster.timeInterval == optimisticMonster.timeInterval)
    }
}
#endif
