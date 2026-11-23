// @copyright André Trettin

#if os(visionOS)
import CoreGraphics
import CoreRPG
import Foundation
import RealityKit
import RPGTabletopGameContent
import Spatial
import TabletopKit
import UIKit
import os.log

// MARK: - Generated Assets

/// The d4's mesh and per-color materials. Like the other polyhedral dice, there is no asset in the
/// package: the mesh is built from `TableDie4Geometry` and the numbers are drawn into a texture
/// atlas per dice color.
@MainActor
enum Die4Assets {
    private static var mesh: MeshResource?
    private static var materials: [String: PhysicallyBasedMaterial] = [:]

    static func meshResource() throws -> MeshResource {
        if let mesh {
            return mesh
        }
        // A small bezel on every edge; the faces keep their planes, so the rest height is unchanged.
        let bevelled = TableDieBevel.mesh(faces: TableDie4Geometry.faces.map {
            TableDieBevel.Face(corners: $0.corners, normal: $0.normal, atlas: TableDie4Geometry.atlasFace(for: $0).coordinates)
        })
        var descriptor = MeshDescriptor(name: "D4")
        descriptor.positions = MeshBuffer(bevelled.positions)
        descriptor.normals = MeshBuffer(bevelled.normals)
        descriptor.textureCoordinates = MeshBuffer(bevelled.coordinates)
        descriptor.primitives = .triangles(bevelled.indices)
        let resource = try MeshResource.generate(from: [descriptor])
        mesh = resource
        return resource
    }

    /// The d4's material in the color of a dice color code, built once per code.
    static func material(for code: String) async -> PhysicallyBasedMaterial? {
        let code = TableDiePalette.resolvedCode(code, for: .d4)
        if let material = materials[code] {
            return material
        }
        guard let atlas = await renderAtlas(palette: .palette(for: code, kind: .d4)),
              let texture = try? await TextureResource(
                  image: atlas,
                  options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll)
              ) else {
            Logger.gameTable.error("Could not build the d4 material for color \(code, privacy: .public)")
            return nil
        }
        var material = GeneratedDie.placeholderMaterial()
        material.baseColor = .init(tint: .white, texture: .init(texture))
        let cached = materials[code] ?? material
        materials[code] = cached
        return cached
    }

    /// Draws the atlas: the die's body color everywhere, and on each face the numbers of its three
    /// corners, each with its top towards its corner, in the numeral color.
    @concurrent
    private static func renderAtlas(palette: TableDiePalette) async -> CGImage? {
        let cell = GeneratedDie.atlasCell * 2
        let width = cell * TableDie4Geometry.atlasColumns
        let height = cell * TableDie4Geometry.atlasRows
        guard let context = GeneratedDie.bodyContext(width: width, height: height, palette: palette) else { return nil }

        for face in TableDie4Geometry.faces {
            for numeral in TableDie4Geometry.atlasFace(for: face).numerals {
                GeneratedDie.drawNumeral(
                    String(numeral.number),
                    at: CGPoint(x: CGFloat(numeral.center.x) * CGFloat(width), y: CGFloat(numeral.center.y) * CGFloat(height)),
                    fontSize: CGFloat(cell) * 0.2,
                    underlined: false,
                    pointing: CGVector(dx: CGFloat(numeral.direction.x), dy: CGFloat(numeral.direction.y)),
                    color: GeneratedDie.cgColor(palette.pip),
                    imageHeight: height,
                    in: context
                )
            }
        }
        return context.makeImage()
    }
}

// MARK: - Die

struct Die4: PoolDie {
    static var kind: TableDieKind { .d4 }
    let id: ID
    let entity: Entity
    let audioPlaybackController: AudioPlaybackController?
    var initialState: DieState
    let representation: TossableRepresentation

    /// Returns the orientation of the die entity that shows the given value: the corner with
    /// that number points up and the die rests on the face opposite it.
    ///
    /// Called by TabletopKit itself, not from our own code — see `Die.restingOrientation`.
    func restingOrientation(state: DieState) -> Rotation3D {
        guard state.value != TableDieValue.parked else { return .init() }
        guard let corner = TableDie4Geometry.direction(ofNumber: TableDieValue.face(state.value)) else {
            Logger.gameTable.error("Invalid D4 die value \(state.value, privacy: .public); using identity orientation as a fallback")
            return .init()
        }
        return GeneratedDie.faceUpOrientation(normal: corner)
    }

    @MainActor
    init(id: ID, seatControl: ControllingSeats = .any, seatIndex: Int = 0, dieNumber: Int = 1) {
        self.id = id
        let model: Entity
        do {
            model = ModelEntity(mesh: try Die4Assets.meshResource(), materials: [GeneratedDie.placeholderMaterial()])
        } catch {
            Logger.gameTable.error("Failed to generate the D4 mesh: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private); using a procedural fallback mesh")
            model = ModelEntity(
                mesh: .generateBox(size: TableDie4Geometry.displayHeight),
                materials: [GeneratedDie.placeholderMaterial()]
            )
        }
        model.name = "D4"
        self.entity = model
        self.entity.spatialAudio = SpatialAudioComponent()
        do {
            let audioResource = try DieAssets.audio(named: "/Root/dieSoundShort_mp3")
            self.audioPlaybackController = self.entity.prepareAudio(audioResource)
        } catch {
            Logger.gameTable.error(
                "Failed to prepare the D4 roll sound: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)"
            )
            self.audioPlaybackController = nil
        }
        // `height` is the height the die stands on a face, from the face to the corner above it.
        representation = .tetrahedron(height: TableDie4Geometry.displayHeight)
        initialState = .init(value: 0, parentID: .tableId, seatControl: seatControl, pose: .parkedDicePose, entity: self.entity)

        // See the matching accessibility setup on `Die20.init`.
        self.entity.components.set(DiceComponent(dieId: id, sides: 4))
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = Self.accessibilityLabel(seatIndex: seatIndex, dieNumber: dieNumber)
        accessibility.systemActions = .activate
        self.entity.components.set(accessibility)
    }

    /// Seat 0 is always the game master (see `GameTableModel.assignSeatsForSharePlay`).
    private static func accessibilityLabel(seatIndex: Int, dieNumber: Int) -> LocalizedStringResource {
        seatIndex == 0
            ? LocalizedStringResource("Game master's D4 die \(dieNumber)", bundle: .module)
            : LocalizedStringResource("Player seat \(seatIndex) D4 die \(dieNumber)", bundle: .module)
    }

    /// Shows the die in the material `Die4Assets.material(for:)` made for a dice color.
    @MainActor
    func apply(material: PhysicallyBasedMaterial) {
        guard var model = entity.components[ModelComponent.self] else { return }
        model.materials = model.materials.map { _ in material }
        entity.components.set(model)
    }
}
#endif
