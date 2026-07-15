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
}
#endif
