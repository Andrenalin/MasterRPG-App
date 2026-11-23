// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import CoreRPG
import Foundation
import Testing

@testable import MapRPG

/// CODE_AUDIT_24 §5.3, §5.4 and §5.8: who writes a pin's shared photo flag, when the flag ends,
/// and where new player pins are placed.
@MainActor
struct PinPhotoShareAndPlacementTests {
    // MARK: - §5.3 A player's pin move cannot change the shared photo flag

    @Test("A player pin move never changes isPhotoShared, neither turning it off nor on")
    func playerMoveKeepsIsZoom() async throws {
        let fixture = try await makeFixture(playerCount: 2)
        let mover = fixture.playerIds[0]
        let other = fixture.playerIds[1]
        #expect(fixture.sut.synchronizePlayerPins(for: fixture.map.id))
        #expect(fixture.sut.setPinPhotoShown(itemId: fixture.map.id, pinId: mover, shown: true))

        // A stale `false` with a newer timestamp moves the pin but leaves the shared photo open.
        #expect(fixture.sut.updatePin(
            itemId: fixture.map.id,
            data: move(mover, to: CGPoint(x: 300, y: 200), isPhotoShared: false),
            playerId: mover
        ))
        var pin = try #require(fixture.pin(mover))
        #expect(pin.location == CGPoint(x: 300, y: 200))
        #expect(pin.isPhotoShared)

        // A `true` from a player cannot open a photo on a pin the game master did not share.
        #expect(fixture.sut.updatePin(
            itemId: fixture.map.id,
            data: move(other, to: CGPoint(x: 310, y: 210), isPhotoShared: true),
            playerId: other
        ))
        pin = try #require(fixture.pin(other))
        #expect(pin.location == CGPoint(x: 310, y: 210))
        #expect(!pin.isPhotoShared)

        // A message that only carries the flag changes nothing at all.
        #expect(!fixture.sut.updatePin(
            itemId: fixture.map.id,
            data: move(other, to: CGPoint(x: 310, y: 210), isPhotoShared: true, offset: 5),
            playerId: other
        ))
    }

    // MARK: - §6.2 A shared full-screen photo follows the fog predicate and "Share Map"

    @Test("A pin photo goes to the players only for a pin they see, and only while the map is shared")
    func fullScreenPhotoSharingFollowsVisibility() async throws {
        let fogged = room(origin: CGPoint(x: 100, y: 100), isShown: false)
        let fixture = try await makeFixture(playerCount: 0, rooms: [fogged])
        let map = fixture.map
        let inFog = MapPinModel(id: UUID(), name: "Ogre", location: CGPoint(x: 150, y: 150), isShown: true)
        let outside = MapPinModel(id: UUID(), name: "Goblin", location: CGPoint(x: 900, y: 900), isShown: true)
        let hidden = MapPinModel(id: UUID(), name: "Trap", location: CGPoint(x: 900, y: 900), isShown: false)
        map.mapPins = [inFog, outside, hidden]

        #expect(!map.mayShareFullScreenPhoto(of: inFog, isStreaming: true), "a shown monster in an unrevealed room")
        #expect(map.mayShareFullScreenPhoto(of: outside, isStreaming: true))
        #expect(!map.mayShareFullScreenPhoto(of: hidden, isStreaming: true))
        #expect(!map.mayShareFullScreenPhoto(of: outside, isStreaming: false), "Share Map is paused")

        // The live pin decides, not the copy a menu still holds: the room is revealed meanwhile.
        map.entries[0].isShown = true
        #expect(map.mayShareFullScreenPhoto(of: inFog, isStreaming: true))
        var moved = inFog
        moved.location = CGPoint(x: 900, y: 900)
        map.mapPins[0].location = CGPoint(x: 150, y: 150)
        map.entries[0].isShown = false
        #expect(!map.mayShareFullScreenPhoto(of: moved, isStreaming: true), "the stale copy's position does not count")
    }

    // MARK: - §6.3 A player-chosen pin id never takes over a pin the map owns

    @Test("A companion with a monster's pin id neither turns the monster into a player pin nor removes it later")
    func companionIdCannotTakeOverMonsterPin() async throws {
        let fixture = try await makeFixture(playerCount: 0)
        let monster = MapPinModel(id: UUID(), name: "Ogre", location: CGPoint(x: 150, y: 150), isShown: true, timeInterval: 1)
        fixture.map.mapPins = [monster]
        let hostile = PlayerGameModel(id: monster.id, type: .player, name: "Hero", characterId: UUID())

        fixture.sut.setPlayerPin(for: monster.id, name: "Hero", characterId: hostile.characterId ?? UUID())
        #expect(fixture.pin(monster.id)?.isPlayer == false, "metadata only reaches pins that are player pins")
        #expect(fixture.pin(monster.id)?.name == "Ogre")

        fixture.sut.mapGameModel.playerPins = []
        fixture.sut.resetPlayerPins(for: [hostile])
        #expect(fixture.sut.mapGameModel.playerPins.isEmpty, "no player pin is made for the clashing id")
        #expect(fixture.pin(monster.id) == monster)

        // The companion goes away again: the monster is still on the map.
        fixture.sut.resetPlayerPins(for: [])
        #expect(fixture.pin(monster.id) == monster)
    }

    // MARK: - §9.15 The renamed flag keeps its wire name

    @Test("isPhotoShared is still written and read as isZoom")
    func photoSharedFlagKeepsItsWireName() throws {
        var pin = MapPinModel(id: UUID(), name: "Ogre")
        pin.isPhotoShared = true
        let json = try #require(String(data: JSONEncoder().encode(pin), encoding: .utf8))
        #expect(json.contains("\"isZoom\":true"))
        #expect(!json.contains("isPhotoShared"))

        // A pin saved or sent by a build before the rename.
        let legacy = try #require(json.replacingOccurrences(of: "\"isZoom\":true", with: "\"isZoom\":false").data(using: .utf8))
        #expect(try JSONDecoder().decode(MapPinModel.self, from: legacy).isPhotoShared == false)
        #expect(try JSONDecoder().decode(MapPinModel.self, from: JSONEncoder().encode(pin)).isPhotoShared)
    }

    // MARK: - §5.4 A shared photo ends with the map or the pin

    @Test("Hiding a pin ends its shared photo")
    func hidingPinClearsIsZoom() async throws {
        let fixture = try await makeFixture(playerCount: 1)
        let pinId = fixture.playerIds[0]
        #expect(fixture.sut.synchronizePlayerPins(for: fixture.map.id))
        #expect(fixture.sut.setPinPhotoShown(itemId: fixture.map.id, pinId: pinId, shown: true))

        #expect(fixture.sut.togglePin(itemId: fixture.map.id, pinId: pinId))

        let pin = try #require(fixture.pin(pinId))
        #expect(!pin.isShown)
        #expect(!pin.isPhotoShared)
        // Shown again, the next share is a change and goes out.
        #expect(fixture.sut.togglePin(itemId: fixture.map.id, pinId: pinId))
        #expect(fixture.sut.setPinPhotoShown(itemId: fixture.map.id, pinId: pinId, shown: true))
    }

    @Test("Showing another map ends every shared pin photo, on every live map")
    func clearSharedPinPhotos() async throws {
        let fixture = try await makeFixture(playerCount: 1)
        let pinId = fixture.playerIds[0]
        #expect(fixture.sut.synchronizePlayerPins(for: fixture.map.id))
        #expect(fixture.sut.synchronizePlayerPins(for: fixture.otherMap.id))
        #expect(fixture.sut.setPinPhotoShown(itemId: fixture.map.id, pinId: pinId, shown: true))
        #expect(fixture.sut.setPinPhotoShown(itemId: fixture.otherMap.id, pinId: pinId, shown: true))

        #expect(fixture.sut.clearSharedPinPhotos())

        #expect(fixture.sut.gameItem(for: fixture.map.id).mapPins.allSatisfy { !$0.isPhotoShared })
        #expect(fixture.sut.gameItem(for: fixture.otherMap.id).mapPins.allSatisfy { !$0.isPhotoShared })
        #expect(!fixture.sut.clearSharedPinPhotos())
        // The share after the clear is a real change again.
        #expect(fixture.sut.setPinPhotoShown(itemId: fixture.map.id, pinId: pinId, shown: true))
    }

    @Test("Save Game does not export a shared pin photo")
    func saveAllStripsIsZoom() async throws {
        let fixture = try await makeFixture(playerCount: 0)
        let monster = MapPinModel(id: UUID(), name: "Goblin", location: CGPoint(x: 120, y: 120), isShown: true, isPhotoShared: true)
        fixture.map.mapPins = [monster]

        _ = fixture.sut.saveAll()

        let saved = try #require(try fixture.sut.exportController.savedGameExportData(for: fixture.map.id))
        let savedMap = try JSONCoding.decoder.decode(MapModel.self, from: saved)
        #expect(savedMap.mapPins.allSatisfy { !$0.isPhotoShared })
    }

    // CODE_AUDIT_28 §5.7
    @Test("Save Game keeps clone Character ids out of the file and the running game as it is")
    func saveGameWritesLibraryPinsOnACopy() async throws {
        let fixture = try await makeFixture(playerCount: 1)
        #expect(fixture.sut.synchronizePlayerPins(for: fixture.map.id))
        let cloneId = UUID()
        let sourceId = UUID()
        fixture.sut.mapGameModel.registerBattleCharacterCopy(cloneId, source: sourceId)
        let monster = MapPinModel(id: UUID(), name: "Goblin", characterId: cloneId, location: CGPoint(x: 120, y: 120), isShown: true)
        fixture.map.mapPins.append(monster)
        let livePins = fixture.map.mapPins

        _ = fixture.sut.saveAll()
        let saved = try #require(try fixture.sut.exportController.savedGameExportData(for: fixture.map.id))
        let savedMap = try JSONCoding.decoder.decode(MapModel.self, from: saved)

        #expect(savedMap.mapPins.first { $0.id == monster.id }?.characterId == sourceId, "the clone is gone after the game")
        #expect(savedMap.mapPins.allSatisfy { !$0.isPlayer })
        #expect(fixture.map.mapPins == livePins, "a cancelled save must leave the running game its player pins and clones")
    }

    // MARK: - §5.8 Placement

    @Test("A new player pin does not land on a pin that stands in the first room")
    func newPinSkipsOccupiedSpot() async throws {
        let fixture = try await makeFixture(playerCount: 1)
        let first = fixture.playerIds[0]
        #expect(fixture.sut.synchronizePlayerPins(for: fixture.map.id))
        let firstSpot = try #require(fixture.pin(first)).location

        // A second player joins later; the first one never moved.
        let second = UUID()
        fixture.sut.mapGameModel.playerPins.append(MapPinModel(id: second, name: "Late", isPlayer: true, players: [second]))
        #expect(fixture.sut.synchronizePlayerPins(for: fixture.map.id))

        let firstAfter = try #require(fixture.pin(first)).location
        let secondSpot = try #require(fixture.pin(second)).location
        #expect(firstAfter == firstSpot)
        #expect(secondSpot != firstSpot)
        #expect(abs(secondSpot.x - firstSpot.x) >= 1 || abs(secondSpot.y - firstSpot.y) >= 1)
    }

    @Test("The first room the players see is preferred over a hidden one")
    func prefersShownRoom() async throws {
        let hidden = room(origin: CGPoint(x: 100, y: 100), isShown: false)
        let shown = room(origin: CGPoint(x: 600, y: 600), isShown: true)
        let fixture = try await makeFixture(playerCount: 1, rooms: [hidden, shown])
        #expect(fixture.sut.synchronizePlayerPins(for: fixture.map.id))

        let location = try #require(fixture.pin(fixture.playerIds[0])).location
        #expect(location.x >= 600 && location.y >= 600)
    }

    @Test("Many pins stay inside the room and never share a spot")
    func manyPinsStayInRoom() {
        let entry = room(origin: CGPoint(x: 100, y: 100), isShown: true, side: 600)
        let pins = (0..<20).map { MapPinModel(id: UUID(), name: "P\($0)", isPlayer: true) }

        let placed = MapPinPlacement.cascade(pins: pins, in: entry, pinScale: 1)

        let bounds = CGRect(x: entry.xOffset, y: entry.yOffset, width: entry.size.width, height: entry.size.height)
        #expect(placed.allSatisfy { bounds.contains($0.location) })
        #expect(Set(placed.map { "\($0.location.x),\($0.location.y)" }).count == placed.count)
    }

    @Test("Without occupied spots the cascade still fans out diagonally from the left center")
    func cascadeKeepsDiagonal() {
        let entry = room(origin: CGPoint(x: 100, y: 100), isShown: true)
        let pins = (0..<2).map { MapPinModel(id: UUID(), name: "P\($0)", isPlayer: true) }

        let placed = MapPinPlacement.cascade(pins: pins, in: entry, pinScale: 1)

        #expect(placed[0].location == CGPoint(x: 150, y: 200))
        #expect(placed[1].location.x > placed[0].location.x)
        #expect(placed[1].location.y > placed[0].location.y)
    }
}

private extension PinPhotoShareAndPlacementTests {
    @MainActor struct Fixture {
        let sut: GameController
        let map: MapModel
        let otherMap: MapModel
        let playerIds: [UUID]

        func pin(_ id: UUID) -> MapPinModel? {
            sut.gameItem(for: map.id).mapPins.first { $0.id == id }
        }
    }

    func makeFixture(playerCount: Int, rooms: [MapEntryModel]? = nil) async throws -> Fixture {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let playerIds = (0..<playerCount).map { _ in UUID() }
        let map = MapModel(id: UUID(), name: "A", entries: rooms ?? [room(origin: CGPoint(x: 100, y: 100), isShown: true)])
        let otherMap = MapModel(id: UUID(), name: "B", entries: [room(origin: CGPoint(x: 500, y: 500), isShown: true)])
        sut.mapGameModel.playerPins = playerIds.enumerated().map { index, id in
            MapPinModel(id: id, name: "Hero \(index)", isPlayer: true, players: [id])
        }
        sut.setGame(item: map, itemId: map.id)
        sut.setGame(item: otherMap, itemId: otherMap.id)
        return Fixture(sut: sut, map: sut.gameItem(for: map.id), otherMap: sut.gameItem(for: otherMap.id), playerIds: playerIds)
    }

    func room(origin: CGPoint, isShown: Bool, side: CGFloat = 200) -> MapEntryModel {
        MapEntryModel(
            id: UUID(),
            name: "Room",
            content: "",
            coordinates: [
                origin,
                CGPoint(x: origin.x + side, y: origin.y),
                CGPoint(x: origin.x + side, y: origin.y + side),
                CGPoint(x: origin.x, y: origin.y + side)
            ],
            isShown: isShown
        )
    }

    func move(_ pinId: UUID, to location: CGPoint, isPhotoShared: Bool, offset: TimeInterval = 1) -> Data? {
        MapPinModel(
            id: pinId,
            name: "Hero",
            location: location,
            isPlayer: true,
            players: [pinId],
            timeInterval: Date.now.timeIntervalSince1970 + offset,
            isPhotoShared: isPhotoShared
        ).encodeData()
    }
}
#endif
