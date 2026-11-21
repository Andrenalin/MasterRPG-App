// @copyright André Trettin

#if (os(iOS) || os(macOS) || os(visionOS)) && canImport(Testing)
import CoreGraphics
import CoreRPG
import Foundation
import RealityKit
import Testing

@testable import GameRPG
@testable import MapRPG

@MainActor
@Suite("Pin pawn photo standee")
struct PinPawnStandeeTests {
    private static let pointsToMeters = MapTableProjection.fallbackPointsToMeters

    /// A solid RGBA image with a transparent border, like a cutout.
    private static func cutout(width: Int = 64, height: Int = 128) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 8, y: 8, width: width - 16, height: height - 16))
        return try #require(context.makeImage())
    }

    private static func standee(of pawn: PinPawn) throws -> Entity {
        try #require(pawn.entity.findEntity(named: "PinStandee"))
    }

    private static func collisionBox(of pawn: PinPawn) throws -> BoundingBox {
        let collision = try #require(pawn.entity.components[CollisionComponent.self])
        return try #require(collision.shapes.first).bounds
    }

    private func makePawn(_ pin: MapPinModel = MapPinModel(id: UUID(), name: "Goblin")) -> PinPawn {
        let pawn = PinPawn(pin: pin, pointsToMeters: Self.pointsToMeters)
        pawn.update(pin: pin, position: .zero, hiddenForMaster: false, pointsToMeters: Self.pointsToMeters)
        return pawn
    }

    @Test("A new pawn has no standee and a flat hit box")
    func startsWithoutStandee() throws {
        let pawn = makePawn()

        #expect(try !Self.standee(of: pawn).isEnabled)
        let flat = try Self.collisionBox(of: pawn)
        #expect(abs(flat.extents.y - PinStandeeLayout.flatCollisionHeight) < 1e-5)
    }

    @Test("Setting a cutout shows the standee and grows the hit box to cover the figure")
    func cutoutShowsStandee() throws {
        let pawn = makePawn()

        #expect(pawn.setStandee(try Self.cutout()))

        #expect(try Self.standee(of: pawn).isEnabled)
        let box = try Self.collisionBox(of: pawn)
        #expect(box.extents.y > PinStandeeLayout.flatCollisionHeight)
    }

    @Test("A new photo or a cleared photo removes the previous standee")
    func photoChangeRemovesStandee() throws {
        let pin = MapPinModel(id: UUID(), name: "Goblin")
        let pawn = makePawn(pin)
        #expect(pawn.setStandee(try Self.cutout()))

        pawn.clearPhotoTexture(for: pin)

        #expect(try !Self.standee(of: pawn).isEnabled)
        #expect(pawn.loadedPhotoId == nil)
        let flat = try Self.collisionBox(of: pawn)
        #expect(abs(flat.extents.y - PinStandeeLayout.flatCollisionHeight) < 1e-5)
    }

    @Test("A dead pin lays its standee down, a revived one stands it up again")
    func deadPinLaysStandeeDown() throws {
        var pin = MapPinModel(id: UUID(), name: "Goblin")
        let pawn = makePawn(pin)
        #expect(pawn.setStandee(try Self.cutout()))
        let standee = try Self.standee(of: pawn)
        let uprightExtent = try Self.collisionBox(of: pawn).extents.y
        #expect(abs(standee.position.y - PinStandeeLayout.bottomY) < 1e-6)

        pin.isDead = true
        pawn.update(pin: pin, position: .zero, hiddenForMaster: false, pointsToMeters: Self.pointsToMeters)

        #expect(abs(standee.position.y - PinStandeeLayout.fallenY) < 1e-6)
        #expect(abs(try Self.collisionBox(of: pawn).extents.y - PinStandeeLayout.flatCollisionHeight) < 1e-5)

        pin.isDead = false
        pawn.update(pin: pin, position: .zero, hiddenForMaster: false, pointsToMeters: Self.pointsToMeters)

        #expect(abs(standee.position.y - PinStandeeLayout.bottomY) < 1e-6)
        #expect(abs(try Self.collisionBox(of: pawn).extents.y - uprightExtent) < 1e-5)
    }

    @Test("Resizing the pin resizes the standee and keeps its entity")
    func resizeKeepsStandee() throws {
        var pin = MapPinModel(id: UUID(), name: "Goblin")
        let pawn = makePawn(pin)
        #expect(pawn.setStandee(try Self.cutout()))
        let standee = try Self.standee(of: pawn)
        let smallHeight = try Self.collisionBox(of: pawn).extents.y

        pin.size = .colossal
        pawn.update(pin: pin, position: .zero, hiddenForMaster: false, pointsToMeters: Self.pointsToMeters)

        #expect(try Self.standee(of: pawn) === standee)
        #expect(standee.isEnabled)
        #expect(try Self.collisionBox(of: pawn).extents.y > smallHeight)
    }

    @Test("An unchanged update does not touch the standee pose")
    func unchangedUpdateIsIdempotent() throws {
        let pin = MapPinModel(id: UUID(), name: "Goblin")
        let pawn = makePawn(pin)
        #expect(pawn.setStandee(try Self.cutout()))
        let standee = try Self.standee(of: pawn)
        let before = standee.transform

        pawn.update(pin: pin, position: .zero, hiddenForMaster: false, pointsToMeters: Self.pointsToMeters)
        pawn.update(pin: pin, position: .zero, hiddenForMaster: false, pointsToMeters: Self.pointsToMeters)

        #expect(standee.transform == before)
        #expect(standee.isEnabled)
    }
}
#endif
