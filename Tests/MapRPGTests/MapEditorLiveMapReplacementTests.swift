// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import CoreRPG
import Foundation
import SwiftUI
import Testing

@testable import MapRPG

@MainActor
@Suite("Map editor live-map replacement")
struct MapEditorLiveMapReplacementTests {
    @Test("Player pin uses replacement map for UI and map-pin payload")
    func playerPinUsesReplacementMap() throws {
        let mapId = UUID()
        let playerId = UUID()
        let originalPin = Self.playerPin(
            id: playerId,
            location: CGPoint(x: 5, y: 6),
            timeInterval: 1
        )
        let fixture = makeFixture(
            map: MapModel(id: mapId, name: "Original", mapPins: [originalPin]),
            mode: .player,
            playerPinId: playerId
        )

        let replacementPin = Self.playerPin(
            id: playerId,
            location: CGPoint(x: 20, y: 30),
            timeInterval: 10
        )
        let replacement = MapModel(
            id: mapId,
            name: "Replacement",
            mapPins: [replacementPin]
        )
        fixture.root.gameController.setGame(item: replacement, itemId: mapId)

        var move = replacementPin
        move.location = CGPoint(x: 80, y: 90)
        fixture.session.route(.pin(.move(pin: move, isPointer: false)))

        let currentPin = try #require(
            replacement.mapPins.first { $0.id == playerId }
        )
        #expect(currentPin.location == move.location)
        #expect(fixture.originalMap.mapPins.first?.location == originalPin.location)
        #expect(fixture.session.pins.pinPointer(for: playerId) == currentPin)
        #expect(fixture.spy.pinUpdates.count == 1)
        let sentPin = try fixture.spy.decodedPinUpdate(at: 0)
        #expect(sentPin.id == currentPin.id)
        #expect(sentPin.location == currentPin.location)
        #expect(sentPin.timeInterval == currentPin.timeInterval)
        #expect(sentPin.isPlayer == currentPin.isPlayer)
        #expect(sentPin.players == currentPin.players)
    }

    @Test("Player pointer uses replacement map for UI and map-pin payload")
    func playerPointerUsesReplacementMap() throws {
        let mapId = UUID()
        let playerId = UUID()
        let pointerId = UUID()
        let original = MapModel(
            id: mapId,
            name: "Original",
            mapPins: [Self.playerPin(id: playerId)]
        )
        original.pointer = Self.pointer(
            id: pointerId,
            location: CGPoint(x: 1, y: 2),
            timeInterval: 1
        )
        let fixture = makeFixture(
            map: original,
            mode: .player,
            playerPinId: playerId
        )

        let replacement = MapModel(
            id: mapId,
            name: "Replacement",
            mapPins: [Self.playerPin(id: playerId)]
        )
        replacement.pointer = Self.pointer(
            id: pointerId,
            location: CGPoint(x: 30, y: 40),
            timeInterval: 10
        )
        fixture.root.gameController.setGame(item: replacement, itemId: mapId)

        var move = replacement.pointer
        move.location = CGPoint(x: 70, y: 75)
        fixture.session.route(.pin(.move(pin: move, isPointer: true)))

        #expect(replacement.pointer.location == move.location)
        #expect(fixture.originalMap.pointer.location == CGPoint(x: 1, y: 2))
        #expect(fixture.session.pins.pointer == replacement.pointer)
        #expect(fixture.spy.pinUpdates.count == 1)
        let sentPointer = try fixture.spy.decodedPinUpdate(at: 0)
        #expect(sentPointer.id == replacement.pointer.id)
        #expect(sentPointer.location == replacement.pointer.location)
        #expect(sentPointer.timeInterval == replacement.pointer.timeInterval)
        #expect(sentPointer.isShown == replacement.pointer.isShown)
    }

    @Test("Game-master pin uses replacement map for UI and map-state payload")
    func gameMasterPinUsesReplacementMap() throws {
        let mapId = UUID()
        let pinId = UUID()
        let originalPin = MapPinModel(
            id: pinId,
            name: "Original monster",
            location: CGPoint(x: 2, y: 3),
            timeInterval: 1
        )
        let fixture = makeFixture(
            map: MapModel(id: mapId, name: "Original", mapPins: [originalPin]),
            mode: .gameMaster
        )
        fixture.session.isStreaming = true

        let replacementPin = MapPinModel(
            id: pinId,
            name: "Replacement monster",
            location: CGPoint(x: 40, y: 50),
            timeInterval: 10
        )
        let replacement = MapModel(
            id: mapId,
            name: "Replacement",
            mapPins: [replacementPin]
        )
        fixture.root.gameController.setGame(item: replacement, itemId: mapId)

        var move = replacementPin
        move.location = CGPoint(x: 100, y: 110)
        fixture.session.route(.pin(.move(pin: move, isPointer: false)))

        let currentPin = try #require(
            replacement.mapPins.first { $0.id == pinId }
        )
        #expect(currentPin.location == move.location)
        #expect(fixture.originalMap.mapPins.first?.location == originalPin.location)
        #expect(fixture.session.pins.pinPointer(for: pinId) == currentPin)
        #expect(fixture.spy.mapUpdates.count == 1)
        let sentPins = try fixture.spy.decodedMapStatePins(at: 0)
        let sentPin = try #require(sentPins.first { $0.id == pinId })
        #expect(sentPin.id == currentPin.id)
        #expect(sentPin.location == currentPin.location)
        #expect(sentPin.timeInterval == currentPin.timeInterval)
        #expect(sentPin.name == currentPin.name)
    }

    private func makeFixture(
        map: MapModel,
        mode: MapMode,
        playerPinId: UUID? = nil
    ) -> LiveMapReplacementFixture {
        let root = MapRootModel.previewFixture(models: [map])
        let originalMap = root.gameController.gameItem(for: map.id)
        let spy = LiveMapReplacementUpdateSpy()
        let actions = MapEditorActions(
            sendMapUpdates: {
                if mode == .player,
                   let update = root.gameController.networkPointer(itemId: map.id) {
                    spy.recordPin(update)
                } else if mode == .gameMaster {
                    spy.recordMap(root.gameController.networkMapUpdate(for: map.id))
                }
            },
            sendPinUpdate: { pinId in
                guard let update = root.gameController.networkPin(
                    itemId: map.id,
                    pinId: pinId
                ) else { return }
                spy.recordPin(update)
            }
        )
        let session = MapEditorSession(
            map: originalMap,
            image: AKImage(),
            photoDegrees: 0,
            containerSize: CGSize(width: 800, height: 600),
            configuration: MapEditorConfiguration(
                mode: mode,
                displayMode: mode == .player ? .player : .master,
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
                map: originalMap,
                root: root
            )
        )
        return LiveMapReplacementFixture(
            root: root,
            originalMap: originalMap,
            session: session,
            spy: spy
        )
    }

    private static func playerPin(
        id: UUID,
        location: CGPoint = .zero,
        timeInterval: TimeInterval = 1
    ) -> MapPinModel {
        MapPinModel(
            id: id,
            name: "Player",
            location: location,
            isPlayer: true,
            players: [id],
            timeInterval: timeInterval
        )
    }

    private static func pointer(
        id: UUID,
        location: CGPoint,
        timeInterval: TimeInterval
    ) -> MapPinModel {
        MapPinModel(
            id: id,
            name: "Pointer",
            location: location,
            isShown: true,
            timeInterval: timeInterval
        )
    }
}

@MainActor
private struct LiveMapReplacementFixture {
    let root: MapRootModel
    let originalMap: MapModel
    let session: MapEditorSession
    let spy: LiveMapReplacementUpdateSpy
}

@MainActor
private final class LiveMapReplacementUpdateSpy {
    private(set) var pinUpdates: [NetworkCodableDataType] = []
    private(set) var mapUpdates: [NetworkCodableDataType] = []

    func recordPin(_ update: NetworkCodableDataType) {
        pinUpdates.append(update)
    }

    func recordMap(_ update: NetworkCodableDataType) {
        mapUpdates.append(update)
    }

    func decodedPinUpdate(at index: Int) throws -> MapPinModel {
        let data = try #require(pinUpdates[index].data)
        return try JSONDecoder().decode(MapPinModel.self, from: data)
    }

    func decodedMapStatePins(at index: Int) throws -> [MapPinModel] {
        let data = try #require(mapUpdates[index].data)
        let state = try #require(String(data: data, encoding: .utf8))
        let pinArrayStart = try #require(state.firstIndex(of: "["))
        return try JSONDecoder().decode(
            [MapPinModel].self,
            from: Data(state[pinArrayStart...].utf8)
        )
    }
}

#endif
