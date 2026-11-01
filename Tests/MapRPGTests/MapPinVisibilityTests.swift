// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import CoreRPG
import Foundation
import SwiftUI
import Testing

@testable import MapRPG

@MainActor
struct MapPinVisibilityTests {
    let square = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)]

    @Test func pinCodableRoundTripAndLegacyDefaults() throws {
        // Given
        let characterId = UUID()
        let pin = MapPinModel(
            id: UUID(),
            name: "Fallen Hero",
            characterId: characterId,
            isDead: true,
            isHighlighted: true
        )

        // When
        let encoded = try JSONEncoder().encode(pin)
        let decoded = try JSONDecoder().decode(MapPinModel.self, from: encoded)
        let encodedObject = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        var missingDeadObject = encodedObject
        missingDeadObject.removeValue(forKey: "isDead")
        let missingDeadPin = try JSONDecoder().decode(
            MapPinModel.self,
            from: JSONSerialization.data(withJSONObject: missingDeadObject)
        )
        var missingHighlightObject = encodedObject
        missingHighlightObject.removeValue(forKey: "isHighlighted")
        let missingHighlightPin = try JSONDecoder().decode(
            MapPinModel.self,
            from: JSONSerialization.data(withJSONObject: missingHighlightObject)
        )
        var legacyObject = encodedObject
        legacyObject.removeValue(forKey: "isDead")
        legacyObject.removeValue(forKey: "isHighlighted")
        legacyObject.removeValue(forKey: "characterId")
        let legacyPin = try JSONDecoder().decode(
            MapPinModel.self,
            from: JSONSerialization.data(withJSONObject: legacyObject)
        )

        // Then
        #expect(decoded.isDead)
        #expect(decoded.isHighlighted)
        #expect(decoded.characterId == characterId)
        #expect(!missingDeadPin.isDead)
        #expect(missingDeadPin.isHighlighted)
        #expect(missingHighlightPin.isDead)
        #expect(!missingHighlightPin.isHighlighted)
        #expect(!legacyPin.isDead)
        #expect(!legacyPin.isHighlighted)
        #expect(legacyPin.characterId == nil)
        // No "healthPercent" key at all (pre-migration payload/pin): decodes
        // to `nil`, the "health unknown" grey border, not 0%.
        #expect(legacyPin.healthPercent == nil)
    }

    @Test func healthPercentCodableRoundTrip() throws {
        var pin = MapPinModel(id: UUID(), name: "Wounded", healthPercent: 37.5)

        let encoded = try JSONEncoder().encode(pin)
        let decoded = try JSONDecoder().decode(MapPinModel.self, from: encoded)
        #expect(decoded.healthPercent == 37.5)

        pin.healthPercent = nil
        let encodedUnknown = try JSONEncoder().encode(pin)
        let decodedUnknown = try JSONDecoder().decode(MapPinModel.self, from: encodedUnknown)
        #expect(decodedUnknown.healthPercent == nil)
    }

    @Test func healthBorderColorThresholds() {
        var pin = MapPinModel(id: UUID(), name: "Combatant")

        pin.healthPercent = nil
        #expect(pin.healthBorderColor == .gray)

        pin.healthPercent = 49
        #expect(pin.healthBorderColor == .red)

        pin.healthPercent = 50
        #expect(pin.healthBorderColor == .orange)

        pin.healthPercent = 79
        #expect(pin.healthBorderColor == .orange)

        pin.healthPercent = 80
        #expect(pin.healthBorderColor == .green)

        pin.healthPercent = 100
        #expect(pin.healthBorderColor == .green)
    }

    @Test func monsterInHiddenRoomIsNotSentToPlayers() throws {
        // Given: a hidden room with a shown monster inside, a shown player pin inside, and a
        // shown monster outside every room.
        let room = MapEntryModel(id: UUID(), name: "Crypt", content: "", coordinates: square, isShown: false)
        let inside = CGPoint(x: 50, y: 50)
        let monster = MapPinModel(id: UUID(), name: "Lich", location: inside, isShown: true)
        let player = MapPinModel(id: UUID(), name: "Hero", location: inside, isShown: true, isPlayer: true)
        let outside = MapPinModel(id: UUID(), name: "Rat", location: CGPoint(x: 500, y: 500), isShown: true)
        let map = MapModel(id: UUID(), name: "Map", entries: [room], mapPins: [monster, player, outside])

        // When
        let hiddenVisible = GameController.pinsVisibleToPlayers(in: map).map(\.id)
        let hiddenSnapshot = MapSnapshot(map).redactedForNonMaster().mapPins.wrappedValue.map(\.id)
        map.toggle(room.id)
        let revealedVisible = GameController.pinsVisibleToPlayers(in: map).map(\.id)

        // Then
        #expect(Set(hiddenVisible) == [player.id, outside.id])
        #expect(Set(hiddenSnapshot) == [player.id, outside.id])
        #expect(Set(revealedVisible) == [monster.id, player.id, outside.id])
    }

    @Test func revealingARoomChangesTheContentFingerprint() {
        // Given
        let room = MapEntryModel(id: UUID(), name: "Crypt", content: "Secret", coordinates: square, isShown: false)
        let map = MapModel(id: UUID(), name: "Map", entries: [room])
        let hiddenVersion = MapUpdatePayload(model: map).contentVersion

        // When
        map.toggle(room.id)
        let revealedVersion = MapUpdatePayload(model: map).contentVersion

        // Then
        #expect(hiddenVersion != revealedVersion)
    }

    @Test func entryContainsPoint() {
        let entry = MapEntryModel(id: UUID(), name: "Room", content: "", coordinates: square)

        #expect(entry.contains(CGPoint(x: 50, y: 50)))
        #expect(!entry.contains(CGPoint(x: 150, y: 50)))
    }

    @Test func entryContainsRejectsDegeneratePolygon() {
        let entry = MapEntryModel(id: UUID(), name: "Line", content: "", coordinates: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100)])

        #expect(!entry.contains(CGPoint(x: 50, y: 50)))
    }

    @Test func entryContainsConcavePolygon() {
        // L-shape: the notch (upper right) is outside.
        let lShape = [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0), CGPoint(x: 50, y: 50), CGPoint(x: 100, y: 50), CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)]
        let entry = MapEntryModel(id: UUID(), name: "L", content: "", coordinates: lShape)

        #expect(entry.contains(CGPoint(x: 25, y: 25)))
        #expect(entry.contains(CGPoint(x: 75, y: 75)))
        #expect(!entry.contains(CGPoint(x: 75, y: 25)))
    }

    @Test func locationHiddenForPlayersOnlyInsideHiddenRooms() {
        let hidden = MapEntryModel(id: UUID(), name: "Hidden", content: "", coordinates: square, isShown: false)
        let shownCoordinates = square.map { CGPoint(x: $0.x + 200, y: $0.y) }
        let shown = MapEntryModel(id: UUID(), name: "Shown", content: "", coordinates: shownCoordinates, isShown: true)
        let map = MapModel(id: UUID(), name: "Dungeon", entries: [hidden, shown])

        #expect(map.isLocationHiddenForPlayers(CGPoint(x: 50, y: 50)))
        #expect(!map.isLocationHiddenForPlayers(CGPoint(x: 250, y: 50)))
        // Outside every room: no fog, visible.
        #expect(!map.isLocationHiddenForPlayers(CGPoint(x: 500, y: 500)))
    }

    @Test func movePinUpdatesGameItemAndPlayerPins() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let mapId = UUID()
        let pinId = UUID()
        let pin = MapPinModel(id: pinId, name: "Hero", isPlayer: true, players: [pinId], timeInterval: 1)
        let map = MapModel(id: mapId, name: "Dungeon", mapPins: [pin])
        root.itemController.replace(model: map, isInsert: true)
        sut.setGame(item: map.copy(), itemId: mapId)
        sut.mapGameModel.playerPins = [pin]

        let moved = sut.movePin(itemId: mapId, pinId: pinId, location: CGPoint(x: 42, y: 24))

        #expect(moved)
        let itemPin = sut.gameItem(for: mapId).mapPins.first { $0.id == pinId }
        #expect(itemPin?.location == CGPoint(x: 42, y: 24))
        #expect((itemPin?.timeInterval ?? 0) > 1)
        #expect(sut.mapGameModel.playerPins.first { $0.id == pinId }?.location == CGPoint(x: 42, y: 24))
    }

    @Test func togglePinFlipsVisibilityAndStampsTime() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let mapId = UUID()
        let pinId = UUID()
        let pin = MapPinModel(id: pinId, name: "Ogre", isShown: true, timeInterval: 1)
        let map = MapModel(id: mapId, name: "Dungeon", mapPins: [pin])
        root.itemController.replace(model: map, isInsert: true)
        sut.setGame(item: map.copy(), itemId: mapId)

        #expect(sut.togglePin(itemId: mapId, pinId: pinId))

        let itemPin = sut.gameItem(for: mapId).mapPins.first { $0.id == pinId }
        #expect(itemPin?.isShown == false)
        #expect((itemPin?.timeInterval ?? 0) > 1)
        #expect(!sut.togglePin(itemId: mapId, pinId: UUID()))
    }

    @Test func deadResizeHighlightAndZoomUpdateGameAndSessionState() async throws {
        // Given
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let mapId = UUID()
        let pinId = UUID()
        let pin = MapPinModel(
            id: pinId,
            name: "Hero",
            size: .normal,
            isPlayer: true,
            players: [pinId],
            timeInterval: 1
        )
        let map = MapModel(id: mapId, name: "Dungeon", mapPins: [pin])
        root.itemController.replace(model: map, isInsert: true)
        sut.setGame(item: map.copy(), itemId: mapId)
        sut.mapGameModel.playerPins = [pin]

        // When
        #expect(sut.toggleDeadPin(itemId: mapId, pinId: pinId))
        #expect(sut.resizePin(itemId: mapId, pinId: pinId))
        #expect(sut.toggleHighlightPin(itemId: mapId, pinId: pinId, isGameMaster: true))
        #expect(sut.zoomPin(itemId: mapId, pinId: pinId))

        // Then
        let itemPin = try #require(sut.gameItem(for: mapId).mapPins.first { $0.id == pinId })
        let sessionPin = try #require(sut.mapGameModel.playerPins.first { $0.id == pinId })
        #expect(itemPin.isDead)
        #expect(itemPin.size == .large)
        #expect(itemPin.isHighlighted)
        #expect(itemPin.isZoom)
        #expect(itemPin.timeInterval > 1)
        #expect(sessionPin == itemPin)

        let unknownPinId = UUID()
        #expect(!sut.toggleDeadPin(itemId: mapId, pinId: unknownPinId))
        #expect(!sut.resizePin(itemId: mapId, pinId: unknownPinId))
        #expect(!sut.toggleHighlightPin(itemId: mapId, pinId: unknownPinId, isGameMaster: true))
        #expect(!sut.zoomPin(itemId: mapId, pinId: unknownPinId))
    }

    @Test func networkPinEncodesCurrentPinState() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let mapId = UUID()
        let pinId = UUID()
        let pin = MapPinModel(id: pinId, name: "Hero", isPlayer: true, players: [pinId])
        let map = MapModel(id: mapId, name: "Dungeon", mapPins: [pin])
        root.itemController.replace(model: map, isInsert: true)
        sut.setGame(item: map.copy(), itemId: mapId)
        _ = sut.movePin(itemId: mapId, pinId: pinId, location: CGPoint(x: 7, y: 9))

        let data = try #require(sut.networkPin(itemId: mapId, pinId: pinId))
        let expectedAssetVersion = await sut.mapAssetVersion(for: mapId)

        #expect(data.id == mapId)
        #expect(data.type == .map)
        #expect(data.version == sut.gameItem(for: mapId).version)
        #expect(data.assetVersion == expectedAssetVersion)
        #expect(data.contentVersion == sut.mapContentVersion(for: mapId))
        let decoded = try #require(MapPinModel.decodeData(of: data.data))
        #expect(decoded.id == pinId)
        #expect(decoded.location == CGPoint(x: 7, y: 9))
        #expect(sut.networkPin(itemId: mapId, pinId: UUID()) == nil)
    }

    @Test func authoritativeMapGenerationIsUsedAndResetWithGameState() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let mapId = UUID()
        let pinId = UUID()
        let map = MapModel(
            id: mapId,
            name: "Imported player map",
            mapPins: [MapPinModel(id: pinId, name: "Hero")]
        )
        root.itemController.replace(model: map, isInsert: true)
        sut.setGame(item: map.copy(), itemId: mapId)
        let authoritative = NetworkCodableDataType(
            id: mapId,
            type: .map,
            version: 71,
            assetVersion: 72,
            contentVersion: 73
        )

        sut.recordAuthoritativeMapGeneration(authoritative)

        let cached = try #require(sut.networkPin(itemId: mapId, pinId: pinId))
        #expect(cached.version == 71)
        #expect(cached.assetVersion == 72)
        #expect(cached.contentVersion == 73)
        #expect(await sut.mapAssetVersion(for: mapId) == 72)

        sut.resetGameState()

        let reset = try #require(sut.networkPin(itemId: mapId, pinId: pinId))
        #expect(reset.version == map.version)
        #expect(reset.assetVersion != 72)
        #expect(reset.contentVersion != 73)
        #expect(await sut.mapAssetVersion(for: mapId) != 72)

        sut.recordAuthoritativeMapGeneration(authoritative)
        sut.recordAuthoritativeMapGeneration(NetworkCodableDataType(
            id: mapId,
            type: .map,
            version: 1
        ))
        let legacy = try #require(sut.networkPin(itemId: mapId, pinId: pinId))
        #expect(legacy.version == map.version)
        #expect(legacy.assetVersion != 72)
        #expect(legacy.contentVersion != 73)
        #expect(await sut.mapAssetVersion(for: mapId) != 72)
    }

    @Test func movePinUnknownPinReturnsFalse() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let mapId = UUID()
        let map = MapModel(id: mapId, name: "Dungeon")
        root.itemController.replace(model: map, isInsert: true)
        sut.setGame(item: map.copy(), itemId: mapId)

        #expect(!sut.movePin(itemId: mapId, pinId: UUID(), location: .zero))
    }

    @Test func roomCommandsUseMapToggleRulesAndReportActualChanges() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let mapId = UUID()
        let roomId = UUID()
        let hexId = UUID()
        let room = MapEntryModel(
            id: roomId,
            name: "Great Hall",
            content: "",
            coordinates: square,
            isShown: false
        )
        let hex = MapEntryModel(
            id: hexId,
            name: "Hex",
            content: "",
            coordinates: square,
            isHexGrid: true,
            isShown: false
        )
        let map = MapModel(id: mapId, name: "Dungeon", entries: [hex, room])
        root.itemController.replace(model: map, isInsert: true)
        sut.setGame(item: map.copy(), itemId: mapId)

        #expect(sut.toggleRoom(itemId: mapId, roomId: hexId))
        #expect(sut.gameItem(for: mapId).entries.allSatisfy { $0.isShown })
        #expect(!sut.toggleRoom(itemId: mapId, roomId: UUID()))

        #expect(sut.setRoomsShown(
            itemId: mapId,
            roomIds: [hexId, roomId],
            isShown: false
        ))
        #expect(sut.gameItem(for: mapId).entries.allSatisfy { !$0.isShown })
        #expect(!sut.setRoomsShown(
            itemId: mapId,
            roomIds: [hexId, roomId],
            isShown: false
        ))
    }

    @Test func pointerCommandsMoveToggleAndEncodeTheSharedPointer() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let mapId = UUID()
        let map = MapModel(id: mapId, name: "Dungeon")
        root.itemController.replace(model: map, isInsert: true)
        sut.setGame(item: map.copy(), itemId: mapId)
        let liveMap = sut.gameItem(for: mapId)
        liveMap.pointer.timeInterval = 1

        #expect(sut.movePointer(
            itemId: mapId,
            location: CGPoint(x: 42, y: 24)
        ))
        #expect(!sut.movePointer(
            itemId: mapId,
            location: CGPoint(x: 42, y: 24)
        ))
        #expect(sut.togglePointer(itemId: mapId))

        let pointer = liveMap.pointer
        #expect(pointer.location == CGPoint(x: 42, y: 24))
        #expect(pointer.isShown)
        #expect(pointer.timeInterval > 1)

        let data = try #require(sut.networkPointer(itemId: mapId))
        let decoded = try #require(MapPinModel.decodeData(of: data.data))
        #expect(data.id == mapId)
        // SwiftUI may decode a named color (for example `.red`) into an
        // equivalent RGBA-backed Color that is not identity-equal. Verify the
        // fields authorized by the pointer network route explicitly.
        #expect(decoded.id == pointer.id)
        #expect(decoded.name == pointer.name)
        #expect(decoded.location == pointer.location)
        #expect(decoded.size == pointer.size)
        #expect(decoded.isShown == pointer.isShown)
        #expect(decoded.timeInterval == pointer.timeInterval)
    }

    @Test("A map state for players carries the shown pins only")
    func mapStateLeavesHiddenPinsOut() throws {
        // Given
        let shown = MapPinModel(id: UUID(), name: "Goblin", isShown: true)
        let hidden = MapPinModel(id: UUID(), name: "Hidden dragon", location: CGPoint(x: 3, y: 4), isShown: false)
        let map = MapModel(id: UUID(), name: "Dungeon", entries: [], mapPins: [shown, hidden])

        // When
        let visible = GameController.pinsVisibleToPlayers(in: map)
        let encoded = try #require(JSONString.encode(value: visible))

        // Then
        #expect(visible.map(\.id) == [shown.id])
        #expect(!encoded.contains("Hidden dragon"))
    }
}
#endif
