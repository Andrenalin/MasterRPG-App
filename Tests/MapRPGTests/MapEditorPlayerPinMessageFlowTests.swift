// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import CoreRPG
import Foundation
import SwiftUI
import Testing

@testable import MapRPG

@MainActor
@Suite("Map editor player pin message flow")
struct MapEditorPlayerPinMessageFlowTests {
    @Test("Player movement sends only the owned pin")
    func playerMovementSendsOnlyOwnedPin() throws {
        // Given
        let playerId = UUID()
        let foreignId = UUID()
        let playerPin = MapPinModel(
            id: playerId,
            name: "Player",
            location: CGPoint(x: 10, y: 20),
            isShown: true,
            isPlayer: true,
            players: [playerId],
            timeInterval: 1
        )
        let foreignPin = MapPinModel(
            id: foreignId,
            name: "Other player",
            location: CGPoint(x: 30, y: 40),
            isShown: true,
            isPlayer: true,
            players: [foreignId],
            timeInterval: 1
        )
        let fixture = makeFixture(
            pins: [playerPin, foreignPin],
            playerPinId: playerId
        )
        let playerNode = try #require(fixture.session.pins.pinNode(for: playerId))

        // When
        playerNode.move(by: CGSize(width: 12, height: -4))

        // Then
        let updatedPlayer = try #require(
            fixture.liveMap.mapPins.first { $0.id == playerId }
        )
        #expect(updatedPlayer.location == CGPoint(x: 22, y: 16))
        #expect(updatedPlayer.timeInterval > playerPin.timeInterval)
        #expect(fixture.updateSpy.pinIds == [playerId])
        let sentPlayer = try fixture.updateSpy.decodedPin(at: 0)
        #expect(sentPlayer.id == updatedPlayer.id)
        #expect(sentPlayer.location == updatedPlayer.location)
        #expect(sentPlayer.timeInterval == updatedPlayer.timeInterval)
        #expect(sentPlayer.isPlayer == updatedPlayer.isPlayer)
        #expect(sentPlayer.players == updatedPlayer.players)

        // When: a player attempts to move somebody else's pin.
        var foreignMove = foreignPin
        foreignMove.location = CGPoint(x: 90, y: 100)
        foreignMove.timeInterval = 2
        fixture.session.route(.pin(.move(pin: foreignMove, isPointer: false)))

        // Then
        #expect(
            fixture.liveMap.mapPins.first { $0.id == foreignId }?.location
                == foreignPin.location
        )
        #expect(fixture.updateSpy.pinIds == [playerId])
    }

    @Test("Player highlight and zoom send visible pins but reject hidden pins")
    func playerSharedActionsRequireVisiblePins() throws {
        // Given
        let playerId = UUID()
        let visibleId = UUID()
        let hiddenId = UUID()
        let playerPin = MapPinModel(
            id: playerId,
            name: "Player",
            isPlayer: true,
            players: [playerId]
        )
        let visiblePin = MapPinModel(
            id: visibleId,
            name: "Visible monster",
            isShown: true,
            timeInterval: 1
        )
        let hiddenPin = MapPinModel(
            id: hiddenId,
            name: "Hidden monster",
            isShown: false,
            timeInterval: 1
        )
        let fixture = makeFixture(
            pins: [playerPin, visiblePin, hiddenPin],
            playerPinId: playerId
        )
        let visibleNode = try #require(fixture.session.pins.pinNode(for: visibleId))
        let hiddenNode = try #require(fixture.session.pins.pinNode(for: hiddenId))

        // When
        visibleNode.handleTap(context: .none)
        visibleNode.handleDoubleTap()
        hiddenNode.handleTap(context: .none)
        hiddenNode.handleDoubleTap()

        // Then
        let updatedVisible = try #require(
            fixture.liveMap.mapPins.first { $0.id == visibleId }
        )
        let unchangedHidden = try #require(
            fixture.liveMap.mapPins.first { $0.id == hiddenId }
        )
        #expect(updatedVisible.isHighlighted)
        #expect(updatedVisible.isZoom)
        #expect(!unchangedHidden.isHighlighted)
        #expect(!unchangedHidden.isZoom)
        #expect(fixture.updateSpy.pinIds == [visibleId, visibleId])

        let highlightedPayload = try fixture.updateSpy.decodedPin(at: 0)
        let zoomedPayload = try fixture.updateSpy.decodedPin(at: 1)
        #expect(highlightedPayload.isHighlighted)
        #expect(!highlightedPayload.isZoom)
        #expect(zoomedPayload.isHighlighted)
        #expect(zoomedPayload.isZoom)
    }

    @Test("Player pointer movement uses the map-pin route")
    func playerPointerMovementUsesMapPinRoute() throws {
        // Given
        let playerId = UUID()
        let pointer = MapPinModel(
            id: UUID(),
            name: "Pointer",
            location: CGPoint(x: 5, y: 6),
            isShown: true,
            timeInterval: 1
        )
        let fixture = makeFixture(
            pins: [MapPinModel(
                id: playerId,
                name: "Player",
                isPlayer: true,
                players: [playerId]
            )],
            pointer: pointer,
            playerPinId: playerId
        )

        // When
        fixture.session.pins.pointerNode.move(
            by: CGSize(width: 15, height: 24)
        )

        // Then
        #expect(fixture.liveMap.pointer.location == CGPoint(x: 20, y: 30))
        #expect(fixture.liveMap.pointer.timeInterval > pointer.timeInterval)
        #expect(fixture.updateSpy.pinIds == [pointer.id])
        let sentPointer = try fixture.updateSpy.decodedPin(at: 0)
        #expect(sentPointer.id == fixture.liveMap.pointer.id)
        #expect(sentPointer.location == fixture.liveMap.pointer.location)
        #expect(sentPointer.timeInterval == fixture.liveMap.pointer.timeInterval)
        #expect(sentPointer.isShown == fixture.liveMap.pointer.isShown)
    }

    private func makeFixture(
        pins: [MapPinModel],
        pointer: MapPinModel = .empty,
        playerPinId: UUID
    ) -> MapEditorPlayerPinFixture {
        let persistentMap = MapModel(
            id: MapModel.previewId,
            name: "Player pin test map",
            mapPins: pins
        )
        persistentMap.pointer = pointer
        let root = MapRootModel.previewFixture(models: [persistentMap])
        let liveMap = root.gameController.gameItem(for: persistentMap.id)
        // `MapModel.pointer` is runtime-only and deliberately excluded from
        // `copy()`, so seed it on the live game model used by the router.
        liveMap.pointer = pointer
        let updateSpy = PlayerPinUpdateSpy()
        let actions = MapEditorActions(
            sendMapUpdates: {
                guard let update = root.gameController.networkPointer(
                    itemId: liveMap.id
                ) else { return }
                updateSpy.record(pinId: liveMap.pointer.id, update: update)
            },
            sendPinUpdate: { pinId in
                guard let update = root.gameController.networkPin(
                    itemId: liveMap.id,
                    pinId: pinId
                ) else { return }
                updateSpy.record(pinId: pinId, update: update)
            }
        )
        let session = MapEditorSession(
            map: liveMap,
            image: AKImage(),
            photoDegrees: 0,
            containerSize: CGSize(width: 800, height: 600),
            configuration: MapEditorConfiguration(
                mode: .player,
                displayMode: .player,
                playerPinId: playerPinId
            ),
            actions: actions
        )
        session.installActionRouter(
            MapEditorActionRouter(
                session: session,
                editController: root.editController,
                mapEditController: MapEditController(
                    editController: root.editController
                ),
                map: liveMap,
                root: root
            )
        )

        return MapEditorPlayerPinFixture(
            liveMap: liveMap,
            session: session,
            updateSpy: updateSpy
        )
    }
}

@MainActor
private struct MapEditorPlayerPinFixture {
    let liveMap: MapModel
    let session: MapEditorSession
    let updateSpy: PlayerPinUpdateSpy
}

@MainActor
private final class PlayerPinUpdateSpy {
    private(set) var pinIds: [UUID] = []
    private(set) var updates: [NetworkCodableDataType] = []

    func record(pinId: UUID, update: NetworkCodableDataType) {
        pinIds.append(pinId)
        updates.append(update)
    }

    func decodedPin(at index: Int) throws -> MapPinModel {
        let update = try #require(updates.dropFirst(index).first)
        let data = try #require(update.data)
        return try JSONDecoder().decode(MapPinModel.self, from: data)
    }
}

#endif
