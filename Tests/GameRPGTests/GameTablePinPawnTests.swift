// @copyright André Trettin

#if os(visionOS)
import CoreRPG
import Foundation
import RealityKit
import SwiftUI
import UIKit
import Testing

@testable import GameRPG
@testable import MapRPG

@MainActor
@Suite("visionOS map pin pawns", .serialized)
struct GameTablePinPawnTests {
    private static let pointsToMeters = MapTableProjection.fallbackPointsToMeters

    /// Whether the pawn's single ring, which is always on, shows `expected`: the health color,
    /// red when highlighted, blue for the active attacker, black when dead. See `PinPawn.update`.
    /// Compared by RGBA components, as the material's tint is converted into its own color space.
    private static func ringShows(_ expected: Color, on pawn: PinPawn) throws -> Bool {
        let ring = try #require(pawn.entity.findEntity(named: "PinHighlightRing") as? ModelEntity)
        let material = try #require(ring.model?.materials.first as? UnlitMaterial)
        let actual = rgba(material.color.tint)
        let wanted = rgba(UIColor(expected))
        return zip(actual, wanted).allSatisfy { abs($0 - $1) < 0.02 }
    }

    private static func rgba(_ color: UIColor) -> [CGFloat] {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [red, green, blue, alpha]
    }

    @Test("Multiple pawns keep independent highlight rings")
    func multiplePawnsKeepIndependentHighlightRings() throws {
        // Given
        var firstPin = MapPinModel(id: PinPawnTestID.firstPin, name: "Goblin", isHighlighted: true)
        let secondPin = MapPinModel(id: PinPawnTestID.secondPin, name: "Knight", isHighlighted: true)
        let firstPawn = PinPawn(pin: firstPin, pointsToMeters: Self.pointsToMeters)
        let secondPawn = PinPawn(pin: secondPin, pointsToMeters: Self.pointsToMeters)
        firstPawn.update(pin: firstPin, position: .zero, hiddenForMaster: false, pointsToMeters: Self.pointsToMeters)
        secondPawn.update(pin: secondPin, position: .zero, hiddenForMaster: false, pointsToMeters: Self.pointsToMeters)
        let firstRing = try #require(firstPawn.entity.findEntity(named: "PinHighlightRing"))
        let secondRing = try #require(secondPawn.entity.findEntity(named: "PinHighlightRing"))

        // Then: every pawn has its own ring, and both show the highlight
        #expect(firstRing !== secondRing)
        #expect(try Self.ringShows(.red, on: firstPawn))
        #expect(try Self.ringShows(.red, on: secondPawn))

        // When
        firstPin.isHighlighted = false
        firstPawn.update(pin: firstPin, position: .zero, hiddenForMaster: false, pointsToMeters: Self.pointsToMeters)

        // Then: only the first ring went back to the health color (grey without a reading)
        #expect(try Self.ringShows(.gray, on: firstPawn))
        #expect(try Self.ringShows(.red, on: secondPawn))
    }

    @Test("Dead and highlighted visuals remain independent")
    func deadAndHighlightedVisualsRemainIndependent() throws {
        var pin = MapPinModel(id: UUID(), name: "Goblin", isDead: false, isHighlighted: false)
        let pawn = PinPawn(pin: pin, pointsToMeters: Self.pointsToMeters)
        let firstDeathBar = try #require(pawn.entity.findEntity(named: "PinDeathMarkFirstBar"))
        let secondDeathBar = try #require(pawn.entity.findEntity(named: "PinDeathMarkSecondBar"))
        let photo = try #require(pawn.entity.findEntity(named: "PinPhotoPlane"))
        pawn.update(pin: pin, position: .zero, hiddenForMaster: false, pointsToMeters: Self.pointsToMeters)

        // The ring is always there; it shows the health color until the pin is highlighted.
        #expect(try Self.ringShows(.gray, on: pawn))
        #expect(!firstDeathBar.isEnabled)
        #expect(!secondDeathBar.isEnabled)
        #expect(photo.isEnabled)

        pin.isDead = true
        pin.isHighlighted = true
        pawn.update(pin: pin, position: .zero, hiddenForMaster: false, pointsToMeters: Self.pointsToMeters)

        #expect(try Self.ringShows(.red, on: pawn))
        #expect(firstDeathBar.isEnabled)
        #expect(secondDeathBar.isEnabled)
        #expect(photo.isEnabled)

        // Revived but still highlighted: the death mark goes, the highlight stays.
        pin.isDead = false
        pawn.update(pin: pin, position: .zero, hiddenForMaster: false, pointsToMeters: Self.pointsToMeters)

        #expect(try Self.ringShows(.red, on: pawn))
        #expect(!firstDeathBar.isEnabled)
        #expect(!secondDeathBar.isEnabled)

        // Dead but no longer highlighted: the death mark stays, the ring is black.
        pin.isDead = true
        pin.isHighlighted = false
        pawn.update(pin: pin, position: .zero, hiddenForMaster: false, pointsToMeters: Self.pointsToMeters)

        #expect(try Self.ringShows(.black, on: pawn))
        #expect(firstDeathBar.isEnabled)
        #expect(secondDeathBar.isEnabled)
    }

    @Test("Size update keeps an existing pawn and the shared photo flag does not scale it")
    func sizeUpdatesExistingPawnWithoutZoomScale() throws {
        var pin = MapPinModel(id: UUID(), name: "Player")
        let pawn = PinPawn(pin: pin, pointsToMeters: Self.pointsToMeters)
        let originalPhoto = try #require(pawn.entity.findEntity(named: "PinPhotoPlane"))

        pin.size = .colossal
        pin.isPhotoShared = true
        pawn.update(pin: pin, position: SIMD3<Float>(0.1, 0.03, -0.1), hiddenForMaster: false, pointsToMeters: Self.pointsToMeters)

        #expect(pawn.entity.scale == SIMD3<Float>(repeating: 1))
        #expect(pawn.entity.position == SIMD3<Float>(0.1, 0.03, -0.1))
        #expect(pawn.entity.findEntity(named: "PinPhotoPlane") === originalPhoto)
        #expect(pawn.entity.components[AccessibilityComponent.self]?.value != nil)
    }

    @Test("Game-master menu points at the selected pawn; showing its photo swaps the popovers")
    func gameMasterMenuStaysOutsidePawnScaleHierarchy() async throws {
        // Given
        let pin = MapPinModel(id: PinPawnTestID.gameMasterPin, name: "Dragon")
        let fixture = try await makeFixture(pin: pin, isGameMaster: true)
        let pawn = try #require(fixture.game.setup.pinPawns.first { $0.pinId == pin.id })
        let attachment = Entity()
        fixture.game.registerAttachment(attachment, for: .pinMenu)
        fixture.game.attachmentHeightChanged(0.06, for: .pinMenu)

        // When
        fixture.game.pinTapped(pinId: pin.id)

        // Then: the anchor, at the arrow's tip, sits above the pawn; the attachment hangs
        // above it by half its own height.
        let anchor = fixture.game.popoverAnchors[.pinMenu].entity
        let expectedAnchorPosition = SIMD3<Float>(
            pawn.entity.position.x,
            pawn.entity.position.y + GameTableModel.pinMenuArrowTipHeight,
            pawn.entity.position.z
        )
        #expect(attachment.isEnabled)
        #expect(anchor.position == expectedAnchorPosition)
        #expect(attachment.position == SIMD3<Float>(0, 0.03, 0))
        #expect(attachment.parent === anchor)
        #expect(anchor.parent === fixture.game.renderer.root)
        #expect(pawn.entity.parent === fixture.game.setup.pinContainer)

        // When: the game master double taps the pin, which shows its photo to everyone.
        fixture.game.pinDoubleTapped(pinId: pin.id)

        // Then: the token is not enlarged, the photo popover took the menu's place.
        #expect(pawn.entity.scale == SIMD3<Float>(repeating: 1))
        #expect(fixture.game.photoPinId == pin.id)
        #expect(fixture.game.selectedPinId == nil)
        #expect(anchor.parent === fixture.game.renderer.root)
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

        // The editor copy intentionally has a different pin. Pawn sync must
        // come from the live game map that mapState replaces.
        #expect(fixture.persistentMap.mapPins.map(\.id) == [PinPawnTestID.persistentPin])
        #expect(fixture.game.setup.pinPawns.map(\.pinId) == [pin.id])
        #expect(try !Self.ringShows(.red, on: pawn))

        // When
        fixture.game.pinTapped(pinId: pin.id)

        // Then
        let highlightedPin = try #require(fixture.liveMap.mapPins.first { $0.id == pin.id })
        let firstCall = try #require(fixture.networkSpy.calls.first)
        let firstPayload = try #require(firstCall.data.data)
        let firstSentPin = try JSONDecoder().decode(MapPinModel.self, from: firstPayload)
        #expect(highlightedPin.isHighlighted)
        #expect(try Self.ringShows(.red, on: pawn))
        #expect(firstCall.action == .mapPin)
        #expect(firstCall.data.id == fixture.liveMap.id)
        #expect(firstSentPin.id == pin.id)
        #expect(firstSentPin.isHighlighted)
        #expect(!firstSentPin.isPhotoShared)

        // When: a double tap opens the photo on this device only.
        fixture.game.pinDoubleTapped(pinId: pin.id)

        // Then: nothing was mutated or sent, and the token is not enlarged.
        let unchangedPin = try #require(fixture.liveMap.mapPins.first { $0.id == pin.id })
        #expect(fixture.game.photoPinId == pin.id)
        #expect(unchangedPin.isHighlighted)
        #expect(!unchangedPin.isPhotoShared)
        #expect(pawn.entity.scale == SIMD3<Float>(repeating: 1))
        #expect(fixture.networkSpy.calls.map(\.action) == [.mapPin])

        // When: the second double tap closes it.
        fixture.game.pinDoubleTapped(pinId: pin.id)

        // Then
        #expect(fixture.game.photoPinId == nil)
    }

    @Test("Game-master menu actions broadcast the map state; a double tap shares the photo; hiding ends it")
    func gameMasterMutationsBroadcastMapState() async throws {
        // Given
        let pin = MapPinModel(id: PinPawnTestID.gameMasterPin, name: "Ogre")
        let fixture = try await makeFixture(pin: pin, isGameMaster: true)

        // When: a tap opens the pin's action menu, which then highlights, kills and resizes it.
        fixture.game.pinTapped(pinId: pin.id)
        #expect(fixture.game.selectedPinId == pin.id)
        fixture.game.toggleSelectedPinHighlight()
        fixture.game.toggleSelectedPinDead()
        fixture.game.resizeSelectedPin()
        fixture.game.pinDoubleTapped(pinId: pin.id)

        // Then
        let updatedPin = try #require(fixture.liveMap.mapPins.first { $0.id == pin.id })
        #expect(updatedPin.isPhotoShared)
        #expect(updatedPin.isDead)
        #expect(updatedPin.isHighlighted)
        #expect(updatedPin.isShown)
        #expect(updatedPin.size == .large)
        #expect(fixture.networkSpy.calls.count == 4)

        // When: the menu hides the pin again, which ends its shared photo.
        fixture.game.pinTapped(pinId: pin.id)
        fixture.game.toggleSelectedPinVisibility()

        // Then
        let hiddenPin = try #require(fixture.liveMap.mapPins.first { $0.id == pin.id })
        #expect(!hiddenPin.isShown)
        #expect(!hiddenPin.isPhotoShared)
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

        let game = GameTableModel(mapRoot: mapRoot, photoRoot: mapRoot.photoRoot)
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
