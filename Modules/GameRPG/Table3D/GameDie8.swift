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

/// The d8's mesh and per-color materials. There is no d8 asset in the package: the mesh is built
/// from `TableDie8Geometry` and the numerals are drawn into a texture atlas per dice color.
@MainActor
enum Die8Assets {
    private static var mesh: MeshResource?
    private static var materials: [String: PhysicallyBasedMaterial] = [:]

    static func meshResource() throws -> MeshResource {
        if let mesh {
            return mesh
        }
        // A small bezel on every edge; the faces keep their planes, so the rest height is unchanged.
        let bevelled = TableDieBevel.mesh(faces: TableDie8Geometry.faces.map {
            TableDieBevel.Face(corners: $0.corners(circumradius: TableDie8Geometry.circumradius), normal: $0.normal, atlas: TableDie8Geometry.atlasCoordinates(for: $0))
        })
        var descriptor = MeshDescriptor(name: "D8")
        descriptor.positions = MeshBuffer(bevelled.positions)
        descriptor.normals = MeshBuffer(bevelled.normals)
        descriptor.textureCoordinates = MeshBuffer(bevelled.coordinates)
        descriptor.primitives = .triangles(bevelled.indices)
        let resource = try MeshResource.generate(from: [descriptor])
        mesh = resource
        return resource
    }

    /// The d8's material in the color of a dice color code, built once per code. The first
    /// material, before a code's texture is ready, is a plain white one (`placeholderMaterial`).
    static func material(for code: String) async -> PhysicallyBasedMaterial? {
        let code = TableDiePalette.resolvedCode(code, for: .d8)
        if let material = materials[code] {
            return material
        }
        guard let atlas = await renderAtlas(palette: .palette(for: code, kind: .d8)),
              let texture = try? await TextureResource(
                  image: atlas,
                  options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll)
              ) else {
            Logger.gameTable.error("Could not build the d8 material for color \(code, privacy: .public)")
            return nil
        }
        var material = placeholderMaterial()
        material.baseColor = .init(tint: .white, texture: .init(texture))
        let cached = materials[code] ?? material
        materials[code] = cached
        return cached
    }

    static func placeholderMaterial() -> PhysicallyBasedMaterial {
        GeneratedDie.placeholderMaterial()
    }

    /// Draws the atlas: the die's body color everywhere, and in each face's cell the face's
    /// numeral, upright towards the cell's top corner, in the pip color. A 6 and a 9 get an
    /// underline, so that they can be told apart.
    @concurrent
    private static func renderAtlas(palette: TableDiePalette) async -> CGImage? {
        let cell = GeneratedDie.atlasCell
        let width = cell * TableDie8Geometry.atlasColumns
        let height = cell * TableDie8Geometry.atlasRows
        guard let context = GeneratedDie.bodyContext(width: width, height: height, palette: palette) else { return nil }

        for face in TableDie8Geometry.faces {
            let index = face.number - 1
            let originX = CGFloat((index % TableDie8Geometry.atlasColumns) * cell)
            let originY = CGFloat((index / TableDie8Geometry.atlasColumns) * cell)
            let center = CGPoint(
                x: originX + CGFloat(TableDie8Geometry.cellCenter.x) * CGFloat(cell),
                y: originY + CGFloat(TableDie8Geometry.cellCenter.y) * CGFloat(cell)
            )
            GeneratedDie.drawNumeral(
                String(face.number),
                at: center,
                fontSize: CGFloat(cell) * 0.36,
                underlined: face.number == 6 || face.number == 9,
                color: GeneratedDie.cgColor(palette.pip),
                imageHeight: height,
                in: context
            )
        }
        return context.makeImage()
    }
}

// MARK: - Die

struct Die8: EntityEquipment {
    let id: ID
    let entity: Entity
    let audioPlaybackController: AudioPlaybackController?
    var initialState: DieState
    let representation: TossableRepresentation

    /// Returns the orientation of the die entity that shows the given value face up.
    ///
    /// Called by TabletopKit itself, not from our own code — see `Die.restingOrientation`.
    func restingOrientation(state: DieState) -> Rotation3D {
        guard state.value != TableDieValue.parked else { return .init() }
        guard let face = TableDie8Geometry.face(number: TableDieValue.face(state.value)) else {
            Logger.gameTable.error("Invalid D8 die value \(state.value, privacy: .public); using identity orientation as a fallback")
            return .init()
        }

        return GeneratedDie.faceUpOrientation(normal: face.normal)
    }

    @MainActor
    init(id: ID, seatControl: ControllingSeats = .any, seatIndex: Int = 0, dieNumber: Int = 1) {
        self.id = id
        let model: Entity
        do {
            model = ModelEntity(mesh: try Die8Assets.meshResource(), materials: [Die8Assets.placeholderMaterial()])
        } catch {
            // A packaging-free path, so this is not expected to fail; degrade like the other dice.
            Logger.gameTable.error("Failed to generate the D8 mesh: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private); using a procedural fallback mesh")
            model = ModelEntity(
                mesh: .generateBox(size: TableDie8Geometry.displayHeight),
                materials: [Die8Assets.placeholderMaterial()]
            )
        }
        model.name = "D8"
        self.entity = model
        self.entity.spatialAudio = SpatialAudioComponent()
        do {
            let audioResource = try DieAssets.audio(named: "/Root/dieSoundShort_mp3")
            self.audioPlaybackController = self.entity.prepareAudio(audioResource)
        } catch {
            Logger.gameTable.error(
                "Failed to prepare the D8 roll sound: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)"
            )
            self.audioPlaybackController = nil
        }
        // `height` is the face-to-opposite-face distance, the extent the die presents resting on a face.
        representation = .octahedron(height: TableDie8Geometry.displayHeight)
        initialState = .init(value: 0, parentID: .tableId, seatControl: seatControl, pose: .parkedDicePose, entity: self.entity)

        // See the matching accessibility setup on `Die20.init`.
        self.entity.components.set(DiceComponent(dieId: id, sides: 8))
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = Self.accessibilityLabel(seatIndex: seatIndex, dieNumber: dieNumber)
        accessibility.systemActions = .activate
        self.entity.components.set(accessibility)
    }

    /// Seat 0 is always the game master (see `GameTableModel.assignSeatsForSharePlay`).
    private static func accessibilityLabel(seatIndex: Int, dieNumber: Int) -> LocalizedStringResource {
        seatIndex == 0
            ? LocalizedStringResource("Game master's D8 die \(dieNumber)", bundle: .module)
            : LocalizedStringResource("Player seat \(seatIndex) D8 die \(dieNumber)", bundle: .module)
    }

    /// Shows the die in the material `Die8Assets.material(for:)` made for a dice color.
    @MainActor
    func apply(material: PhysicallyBasedMaterial) {
        guard var model = entity.components[ModelComponent.self] else { return }
        model.materials = model.materials.map { _ in material }
        entity.components.set(model)
    }

    @MainActor
    func playTossSound() {
        guard let audioPlaybackController else { return }
        if !audioPlaybackController.isPlaying {
            audioPlaybackController.seek(to: .zero)
            audioPlaybackController.play()
        }
    }
}
#endif
