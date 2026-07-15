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
        sut.updatePin(itemId: mapId, data: updatedPin.encodeData(), playerId: playerId)
        #expect(sut.gameItem(for: mapId)[MapPinId.id, playerId].location == CGPoint(x: 12, y: 34))

        let staleUpdate = MapPinModel(
            id: playerId,
            name: "Hero",
            location: CGPoint(x: 90, y: 90),
            isPlayer: true,
            players: [playerId],
            timeInterval: 2
        )
        sut.updatePin(itemId: mapId, data: staleUpdate.encodeData(), playerId: playerId)
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
        gameMap.mapPins[0].timeInterval = 30
        let volatileStateVersion = try #require(
            await sut.networkMapContentUpdate(for: mapId).contentVersion
        )

        // Then
        #expect(volatileStateVersion == initialVersion)

        // When: structural scale, geometry, and pin identity change.
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
        #expect(scaleVersion != volatileStateVersion)
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
            timeInterval: 100
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
        #expect(appliedPin.size == .large)
        #expect(appliedPin.players == [pinId])
        #expect(appliedPin.location == newerLocalPin.location)
        #expect(appliedPin.isShown == newerLocalPin.isShown)
        #expect(appliedPin.timeInterval == newerLocalPin.timeInterval)
    }
}
#endif
