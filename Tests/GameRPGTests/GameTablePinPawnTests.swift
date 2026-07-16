// @copyright André Trettin

#if os(visionOS) && canImport(Testing)
import CoreRPG
import Foundation
import RealityKit
import Testing

@testable import GameRPG
@testable import MapRPG

@MainActor
@Suite("visionOS map pin pawns", .serialized)
struct GameTablePinPawnTests {
    @Test("Multiple pawns keep independent highlight rings")
    func multiplePawnsKeepIndependentHighlightRings() throws {
        // Given
        var firstPin = MapPinModel(id: PinPawnTestID.firstPin, name: "Goblin", isHighlighted: true)
        let secondPin = MapPinModel(id: PinPawnTestID.secondPin, name: "Knight", isHighlighted: true)
        let firstPawn = PinPawn(pin: firstPin)
        let secondPawn = PinPawn(pin: secondPin)
        firstPawn.update(pin: firstPin, position: .zero, hiddenForMaster: false)
        secondPawn.update(pin: secondPin, position: .zero, hiddenForMaster: false)
        let firstRing = try #require(firstPawn.entity.findEntity(named: "PinHighlightRing"))
        let secondRing = try #require(secondPawn.entity.findEntity(named: "PinHighlightRing"))

        // Then
        #expect(firstRing !== secondRing)
        #expect(firstRing.isEnabled)
        #expect(secondRing.isEnabled)

        // When
        firstPin.isHighlighted = false
        firstPawn.update(pin: firstPin, position: .zero, hiddenForMaster: false)

        // Then
        #expect(!firstRing.isEnabled)
        #expect(secondRing.isEnabled)
    }

    @Test("Dead and highlighted visuals remain independent")
    func deadAndHighlightedVisualsRemainIndependent() throws {
        var pin = MapPinModel(id: UUID(), name: "Goblin", isDead: false, isHighlighted: false)
        let pawn = PinPawn(pin: pin)
        let highlight = try #require(pawn.entity.findEntity(named: "PinHighlightRing"))
        let firstDeathBar = try #require(pawn.entity.findEntity(named: "PinDeathMarkFirstBar"))
        let secondDeathBar = try #require(pawn.entity.findEntity(named: "PinDeathMarkSecondBar"))
        let photo = try #require(pawn.entity.findEntity(named: "PinPhotoPlane"))

        #expect(!highlight.isEnabled)
        #expect(!firstDeathBar.isEnabled)
        #expect(!secondDeathBar.isEnabled)
        #expect(photo.isEnabled)

        pin.isDead = true
        pin.isHighlighted = true
        pawn.update(pin: pin, position: .zero, hiddenForMaster: false)

        #expect(highlight.isEnabled)
        #expect(firstDeathBar.isEnabled)
        #expect(secondDeathBar.isEnabled)
        #expect(photo.isEnabled)

        pin.isDead = false
        pawn.update(pin: pin, position: .zero, hiddenForMaster: false)

        #expect(highlight.isEnabled)
        #expect(!firstDeathBar.isEnabled)
        #expect(!secondDeathBar.isEnabled)
    }

    @Test("Zoom and size update an existing pawn")
    func zoomAndSizeUpdateExistingPawn() throws {
        var pin = MapPinModel(id: UUID(), name: "Player")
        let pawn = PinPawn(pin: pin)
        let originalPhoto = try #require(pawn.entity.findEntity(named: "PinPhotoPlane"))

        pin.size = .colossal
        pin.isZoom = true
        pawn.update(pin: pin, position: SIMD3<Float>(0.1, 0.03, -0.1), hiddenForMaster: false)

        #expect(pawn.entity.scale == SIMD3<Float>(repeating: 4))
        #expect(pawn.entity.position == SIMD3<Float>(0.1, 0.03, -0.1))
        #expect(pawn.entity.findEntity(named: "PinPhotoPlane") === originalPhoto)
        #expect(pawn.entity.components[AccessibilityComponent.self]?.value != nil)
    }

    @Test("Game-master menu stays above the selected pawn without inheriting pawn zoom")
    func gameMasterMenuStaysOutsidePawnScaleHierarchy() async throws {
        // Given
        let pin = MapPinModel(id: PinPawnTestID.gameMasterPin, name: "Dragon")
        let fixture = try await makeFixture(pin: pin, isGameMaster: true)
        let pawn = try #require(fixture.game.setup.pinPawns.first { $0.pinId == pin.id })
        let attachment = Entity()
        fixture.game.registerPinMenuAttachment(attachment)

        // When
        fixture.game.pinTapped(pinId: pin.id)

        // Then
        let expectedPosition = SIMD3<Float>(
            pawn.entity.position.x,
            pawn.entity.position.y + 0.09,
            pawn.entity.position.z
        )
        #expect(attachment.isEnabled)
        #expect(attachment.position == expectedPosition)
        #expect(attachment.parent === fixture.game.renderer.root)
        #expect(attachment.parent !== pawn.entity)
        #expect(pawn.entity.parent === fixture.game.setup.pinContainer)

        // When
        fixture.game.toggleSelectedPinZoom()

        // Then
        #expect(pawn.entity.scale == SIMD3<Float>(repeating: 4))
        #expect(attachment.scale == SIMD3<Float>(repeating: 1))
        #expect(attachment.parent === fixture.game.renderer.root)
        #expect(attachment.position == expectedPosition)
    }

    @Test("Player taps mutate the live pin and send targeted map-pin updates")
    func playerTapsMutateLivePinAndSendMapPinUpdates() async throws {
        // Given
        let pin = MapPinModel(
            id: PinPawnTestID.playerPin,
            name: "Player",
            isPlayer: true,
            players: [PinPawnTestID.playerPin]
        )
        let fixture = try await makeFixture(pin: pin, isGameMaster: false)
        let pawn = try #require(fixture.game.setup.pinPawns.first { $0.pinId == pin.id })
        let highlightRing = try #require(pawn.entity.findEntity(named: "PinHighlightRing"))

        // The editor copy intentionally has a different pin. Pawn sync must
        // come from the live game map that mapState replaces.
        #expect(fixture.persistentMap.mapPins.map(\.id) == [PinPawnTestID.persistentPin])
        #expect(fixture.game.setup.pinPawns.map(\.pinId) == [pin.id])
        #expect(!highlightRing.isEnabled)

        // When
        fixture.game.pinTapped(pinId: pin.id)

        // Then
        let highlightedPin = try #require(fixture.liveMap.mapPins.first { $0.id == pin.id })
        let firstCall = try #require(fixture.networkSpy.calls.first)
        let firstPayload = try #require(firstCall.data.data)
        let firstSentPin = try JSONDecoder().decode(MapPinModel.self, from: firstPayload)
        #expect(highlightedPin.isHighlighted)
        #expect(highlightRing.isEnabled)
        #expect(firstCall.action == .mapPin)
        #expect(firstCall.data.id == fixture.liveMap.id)
        #expect(firstSentPin.id == pin.id)
        #expect(firstSentPin.isHighlighted)
        #expect(!firstSentPin.isZoom)

        // When
        fixture.game.pinDoubleTapped(pinId: pin.id)

        // Then
        let zoomedPin = try #require(fixture.liveMap.mapPins.first { $0.id == pin.id })
        let secondCall = try #require(fixture.networkSpy.calls.last)
        let secondPayload = try #require(secondCall.data.data)
        let secondSentPin = try JSONDecoder().decode(MapPinModel.self, from: secondPayload)
        #expect(zoomedPin.isHighlighted)
        #expect(zoomedPin.isZoom)
        #expect(pawn.entity.scale == SIMD3<Float>(repeating: 4))
        #expect(fixture.networkSpy.calls.map(\.action) == [.mapPin, .mapPin])
        #expect(secondSentPin.id == pin.id)
        #expect(secondSentPin.isHighlighted)
        #expect(secondSentPin.isZoom)
    }

    @Test("Game-master double tap and every menu mutation broadcast map state")
    func gameMasterMutationsBroadcastMapState() async throws {
        // Given
        let pin = MapPinModel(id: PinPawnTestID.gameMasterPin, name: "Ogre")
        let fixture = try await makeFixture(pin: pin, isGameMaster: true)
        fixture.game.pinTapped(pinId: pin.id)

        // When
        fixture.game.pinDoubleTapped(pinId: pin.id)
        fixture.game.toggleSelectedPinDead()
        fixture.game.toggleSelectedPinVisibility()
        fixture.game.resizeSelectedPin()
        fixture.game.toggleSelectedPinZoom()

        // Then
        let updatedPin = try #require(fixture.liveMap.mapPins.first { $0.id == pin.id })
        #expect(!updatedPin.isZoom)
        #expect(updatedPin.isDead)
        #expect(!updatedPin.isShown)
        #expect(updatedPin.size == .large)
        #expect(fixture.networkSpy.calls.count == 5)
        #expect(fixture.networkSpy.calls.allSatisfy { $0.action == .mapState })
        #expect(fixture.networkSpy.calls.allSatisfy { $0.data.id == fixture.liveMap.id })
        #expect(fixture.networkSpy.calls.allSatisfy { $0.data.type == .map })
    }

    private func makeFixture(pin: MapPinModel, isGameMaster: Bool) async throws -> GameTableFixture {
        let persistentPin = MapPinModel(id: PinPawnTestID.persistentPin, name: "Persistent editor pin")
        let persistentMap = MapModel(
            id: MapModel.previewId,
            name: "Table test map",
            mapPins: [persistentPin]
        )
        let mapRoot = MapRootModel.previewFixture(models: [persistentMap])
        let liveMap = try #require(
            mapRoot.mapGameControllable.gameModel.itemData[persistentMap.id] as? MapModel
        )
        liveMap.mapPins = [pin]

        let game = await GameTableModel(mapRoot: mapRoot, photoRoot: mapRoot.photoRoot)
        let networkSpy = NetworkActionSpy()
        game.currentMapId = persistentMap.id
        game.isGameMaster = isGameMaster
        game.playerPinId = isGameMaster ? nil : pin.id
        game.networkActions = networkSpy.actions
        game.syncPawnsWithMapPins()

        return GameTableFixture(
            game: game,
            liveMap: liveMap,
            persistentMap: persistentMap,
            networkSpy: networkSpy
        )
    }
}

private struct GameTableFixture {
    let game: GameTableModel
    let liveMap: MapModel
    let persistentMap: MapModel
    let networkSpy: NetworkActionSpy
}

@MainActor
private final class NetworkActionSpy {
    struct Call {
        let data: NetworkCodableDataType
        let action: RPGMessageActionType
        let playerId: UUID?
    }

    private(set) var calls: [Call] = []

    lazy var actions = NetworkActions(
        shareId: { _ in },
        send: { _ in },
        game: { [weak self] data, action, playerId in
            self?.calls.append(Call(data: data, action: action, playerId: playerId))
        }
    )
}

private enum PinPawnTestID {
    static let persistentPin = UUID(uuid: (0xA0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
    static let firstPin = UUID(uuid: (0xA0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2))
    static let secondPin = UUID(uuid: (0xA0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3))
    static let playerPin = UUID(uuid: (0xA0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4))
    static let gameMasterPin = UUID(uuid: (0xA0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5))
}

#endif
