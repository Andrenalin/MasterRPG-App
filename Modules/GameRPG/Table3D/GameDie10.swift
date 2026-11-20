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

/// The d10's mesh and per-color materials. Like the d8, there is no asset in the package: the mesh
/// is built from `TableDie10Geometry` and the numerals are drawn into a texture atlas per dice color.
@MainActor
enum Die10Assets {
    private static var mesh: MeshResource?
    private static var materials: [String: PhysicallyBasedMaterial] = [:]

    static func meshResource() throws -> MeshResource {
        if let mesh {
            return mesh
        }
        // A small bezel on every edge; the faces keep their planes, so the rest height is unchanged.
        let bevelled = TableDieBevel.mesh(faces: TableDie10Geometry.faces.map {
            TableDieBevel.Face(corners: $0.corners, normal: $0.normal, atlas: TableDie10Geometry.atlasKite(for: $0).coordinates)
        })
        var descriptor = MeshDescriptor(name: "D10")
        descriptor.positions = MeshBuffer(bevelled.positions)
        descriptor.normals = MeshBuffer(bevelled.normals)
        descriptor.textureCoordinates = MeshBuffer(bevelled.coordinates)
        descriptor.primitives = .triangles(bevelled.indices)
        let resource = try MeshResource.generate(from: [descriptor])
        mesh = resource
        return resource
    }

    /// The d10's material in the color of a dice color code, built once per code. Codes C, D and F
    /// are the tens dice (10 … 90, 00), as in the 2D art.
    static func material(for code: String) async -> PhysicallyBasedMaterial? {
        let code = TableDiePalette.resolvedCode(code, for: .d10)
        if let material = materials[code] {
            return material
        }
        guard let atlas = await renderAtlas(
                  palette: .palette(for: code, kind: .d10),
                  percentile: TableDie10Geometry.isPercentile(code: code)
              ),
              let texture = try? await TextureResource(
                  image: atlas,
                  options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll)
              ) else {
            Logger.gameTable.error("Could not build the d10 material for color \(code, privacy: .public)")
            return nil
        }
        var material = GeneratedDie.placeholderMaterial()
        material.baseColor = .init(tint: .white, texture: .init(texture))
        let cached = materials[code] ?? material
        materials[code] = cached
        return cached
    }

    /// Draws the atlas: the die's body color everywhere, and in each face's kite its label,
    /// upright towards the kite's apex, in the numeral color.
    @concurrent
    private static func renderAtlas(palette: TableDiePalette, percentile: Bool) async -> CGImage? {
        let cell = GeneratedDie.atlasCell
        let width = cell * TableDie10Geometry.atlasColumns
        let height = cell * TableDie10Geometry.atlasRows
        guard let context = GeneratedDie.bodyContext(width: width, height: height, palette: palette) else { return nil }

        for face in TableDie10Geometry.faces {
            let label = TableDie10Geometry.label(forFace: face.number, percentile: percentile)
            let center = TableDie10Geometry.atlasKite(for: face).center
            GeneratedDie.drawNumeral(
                label,
                at: CGPoint(x: CGFloat(center.x) * CGFloat(width), y: CGFloat(center.y) * CGFloat(height)),
                fontSize: CGFloat(cell) * (label.count > 1 ? 0.24 : 0.32),
                underlined: TableDie10Geometry.isUnderlined(label: label),
                color: GeneratedDie.cgColor(palette.pip),
                imageHeight: height,
                in: context
            )
        }
        return context.makeImage()
    }
}

// MARK: - Die

struct Die10: EntityEquipment {
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
        guard let face = TableDie10Geometry.face(number: TableDieValue.face(state.value)) else {
            Logger.gameTable.error("Invalid D10 die value \(state.value, privacy: .public); using identity orientation as a fallback")
            return .init()
        }
        return GeneratedDie.faceUpOrientation(normal: face.normal)
    }

    @MainActor
    init(id: ID, seatControl: ControllingSeats = .any, seatIndex: Int = 0, dieNumber: Int = 1) {
        self.id = id
        let model: Entity
        do {
            model = ModelEntity(mesh: try Die10Assets.meshResource(), materials: [GeneratedDie.placeholderMaterial()])
        } catch {
            Logger.gameTable.error("Failed to generate the D10 mesh: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private); using a procedural fallback mesh")
            model = ModelEntity(
                mesh: .generateBox(size: TableDie10Geometry.displayHeight),
                materials: [GeneratedDie.placeholderMaterial()]
            )
        }
        model.name = "D10"
        self.entity = model
        self.entity.spatialAudio = SpatialAudioComponent()
        do {
            let audioResource = try DieAssets.audio(named: "/Root/dieSoundShort_mp3")
            self.audioPlaybackController = self.entity.prepareAudio(audioResource)
        } catch {
            Logger.gameTable.error(
                "Failed to prepare the D10 roll sound: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)"
            )
            self.audioPlaybackController = nil
        }
        // `height` is the face-to-opposite-face distance, the extent the die presents resting on a face.
        representation = .decahedron(height: TableDie10Geometry.displayHeight)
        initialState = .init(value: 0, parentID: .tableId, seatControl: seatControl, pose: .parkedDicePose, entity: self.entity)

        // See the matching accessibility setup on `Die20.init`.
        self.entity.components.set(DiceComponent(dieId: id, sides: 10))
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = Self.accessibilityLabel(seatIndex: seatIndex, dieNumber: dieNumber)
        accessibility.systemActions = .activate
        self.entity.components.set(accessibility)
    }

    /// Seat 0 is always the game master (see `GameTableModel.assignSeatsForSharePlay`).
    private static func accessibilityLabel(seatIndex: Int, dieNumber: Int) -> LocalizedStringResource {
        seatIndex == 0
            ? LocalizedStringResource("Game master's D10 die \(dieNumber)", bundle: .module)
            : LocalizedStringResource("Player seat \(seatIndex) D10 die \(dieNumber)", bundle: .module)
    }

    /// Shows the die in the material `Die10Assets.material(for:)` made for a dice color.
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
