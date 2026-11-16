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

/// The d20's mesh and per-color materials. Like the other polyhedral dice, there is no asset in the
/// package: the mesh is built from `TableDie20Geometry` and the numerals are drawn into a texture
/// atlas per dice color.
@MainActor
enum Die20Assets {
    private static var mesh: MeshResource?
    private static var materials: [String: PhysicallyBasedMaterial] = [:]

    static func meshResource() throws -> MeshResource {
        if let mesh {
            return mesh
        }
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var coordinates: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        for face in TableDie20Geometry.faces {
            let base = UInt32(positions.count)
            positions += face.corners
            normals += Array(repeating: face.normal, count: 3)
            // The atlas is an image with y down; texture coordinates have v up.
            coordinates += TableDie20Geometry.atlasTriangle(for: face).coordinates.map { SIMD2($0.x, 1 - $0.y) }
            indices += [base, base + 1, base + 2]
        }
        var descriptor = MeshDescriptor(name: "D20")
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(coordinates)
        descriptor.primitives = .triangles(indices)
        let resource = try MeshResource.generate(from: [descriptor])
        mesh = resource
        return resource
    }

    /// The d20's material in the color of a dice color code, built once per code.
    static func material(for code: String) async -> PhysicallyBasedMaterial? {
        let code = TableDiePalette.resolvedCode(code, for: .d20)
        if let material = materials[code] {
            return material
        }
        guard let atlas = await renderAtlas(palette: .palette(for: code, kind: .d20)),
              let texture = try? await TextureResource(
                  image: atlas,
                  options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll)
              ) else {
            Logger.gameTable.error("Could not build the d20 material for color \(code, privacy: .public)")
            return nil
        }
        var material = GeneratedDie.placeholderMaterial()
        material.baseColor = .init(tint: .white, texture: .init(texture))
        let cached = materials[code] ?? material
        materials[code] = cached
        return cached
    }

    /// Draws the atlas: the die's body color everywhere, and in each face's triangle its number,
    /// upright towards the triangle's first corner, in the numeral color.
    @concurrent
    private static func renderAtlas(palette: TableDiePalette) async -> CGImage? {
        let cell = 512
        let width = cell * TableDie20Geometry.atlasColumns
        let height = cell * TableDie20Geometry.atlasRows
        guard let context = GeneratedDie.bodyContext(width: width, height: height, palette: palette) else { return nil }

        for face in TableDie20Geometry.faces {
            let center = TableDie20Geometry.atlasTriangle(for: face).center
            GeneratedDie.drawNumeral(
                String(face.number),
                at: CGPoint(x: CGFloat(center.x) * CGFloat(width), y: CGFloat(center.y) * CGFloat(height)),
                fontSize: CGFloat(cell) * (face.number >= 10 ? 0.34 : 0.42),
                underlined: TableDie20Geometry.isUnderlined(number: face.number),
                color: GeneratedDie.cgColor(palette.pip),
                imageHeight: height,
                in: context
            )
        }
        return context.makeImage()
    }
}

// MARK: - Die

struct Die20: EntityEquipment {
    let id: ID
    let entity: Entity
    let audioPlaybackController: AudioPlaybackController?
    var initialState: DieState
    let representation: TossableRepresentation

    /// Returns the orientation of the die entity that shows the given value face up.
    ///
    /// Called by TabletopKit itself (when it settles or syncs the die's state), not from our own
    /// code, so it has no call site in this repository. It is what makes the 3D table show the
    /// number that was rolled: do not delete it as unused. See CODE_AUDIT_23 §9.2.
    func restingOrientation(state: DieState) -> Rotation3D {
        // `0` is this table's own sentinel for a currently-unused pool slot
        // (see `GameSetup.maxDicePerType` and `TableVisualState.Pose2D.parkedDicePose`)
        // — the die is parked off-table whenever this holds, so its orientation is irrelevant.
        // Handled before the face lookup so it doesn't trip the "invalid value" fallback below,
        // which is for genuine sync issues.
        guard state.value != TableDieValue.parked else { return .init() }
        guard let face = TableDie20Geometry.face(number: TableDieValue.face(state.value)) else {
            // `state.value` arrives via TabletopKit's synchronized `UpdateEquipmentAction<DieState>`,
            // so a version skew or corrupted/delayed sync payload could plausibly deliver an
            // out-of-range value here. Log and fall back to the identity orientation instead of
            // crashing every SharePlay participant at once.
            Logger.gameTable.error("Invalid D20 die value \(state.value, privacy: .public); using identity orientation as a fallback")
            return .init()
        }
        return GeneratedDie.faceUpOrientation(normal: face.normal)
    }

    @MainActor
    init(id: ID, seatControl: ControllingSeats = .any, seatIndex: Int = 0, dieNumber: Int = 1) {
        self.id = id
        // `entity` is a required, non-optional property of TabletopKit's `EntityEquipment`
        // protocol. Rather than crash the whole tabletop feature over a mesh that can't be
        // generated, fall back to a plain procedural mesh so the die still renders, rolls, and
        // reports a value — just without its numbers.
        let model: Entity
        do {
            model = ModelEntity(mesh: try Die20Assets.meshResource(), materials: [GeneratedDie.placeholderMaterial()])
        } catch {
            Logger.gameTable.error("Failed to generate the D20 mesh: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private); using a procedural fallback mesh")
            model = ModelEntity(
                mesh: .generateSphere(radius: TableDie20Geometry.displayHeight / 2),
                materials: [GeneratedDie.placeholderMaterial()]
            )
        }
        model.name = "D20"
        self.entity = model
        self.entity.spatialAudio = SpatialAudioComponent()
        do {
            // Keep the sound authored in Reality Composer Pro and prepare it
            // on the die so RealityKit emits it from the moving D20 location.
            let audioResource = try DieAssets.audio(named: "/Root/dieSoundLong_mp3")
            self.audioPlaybackController = self.entity.prepareAudio(audioResource)
        } catch {
            Logger.gameTable.error(
                "Failed to prepare the D20 roll sound: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)"
            )
            self.audioPlaybackController = nil
        }
        // `.icosahedron(height:)` wants the face-to-opposite-face measurement, i.e. the vertical
        // (+y) extent the die presents once resting on the table: the mesh is built to exactly
        // `displayHeight` between opposite faces, with face 1 up. TabletopKit's own toss physics
        // uses `representation` for collision/rest, so it has to describe the die rendered.
        representation = .icosahedron(height: TableDie20Geometry.displayHeight)
        // `value: 0` — this table's own sentinel meaning "not part of the seat's currently
        // focused dice set" (see `GameTableModel.applyDiceRoll`); `restingOrientation` above
        // treats it specially rather than as a corrupt/out-of-range value. `pose:
        // .parkedDicePose` — every slot starts off-table, not merely disabled; see that pose's
        // own doc for why a locally-disabled entity crashed a joining player instead of just
        // staying invisible.
        initialState = .init(value: 0, parentID: .tableId, seatControl: seatControl, pose: .parkedDicePose, entity: self.entity)

        // The direct on-table toss gesture otherwise has no accessible equivalent.
        // `GameTableModel.tossDieForAccessibility` reads `DiceComponent` back out to apply a
        // random result the same way a character-sheet roll does (§5.1).
        self.entity.components.set(DiceComponent(dieId: id, sides: 20))
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = Self.accessibilityLabel(seatIndex: seatIndex, dieNumber: dieNumber)
        accessibility.systemActions = .activate
        self.entity.components.set(accessibility)

        // Deliberately no `self.entity.isEnabled = false` here — every seat's pool is
        // pre-allocated (TabletopKit equipment can't be added once `TableSetup` is frozen), but
        // hiding an unclaimed/unused slot is done entirely through its synced `.parkedDicePose`
        // above, not by disabling the entity. See that pose's own doc.
    }

    /// Seat 0 is always the game master (see `GameTableModel.assignSeatsForSharePlay`).
    private static func accessibilityLabel(seatIndex: Int, dieNumber: Int) -> LocalizedStringResource {
        seatIndex == 0
            ? LocalizedStringResource("Game master's D20 die \(dieNumber)", bundle: .module)
            : LocalizedStringResource("Player seat \(seatIndex) D20 die \(dieNumber)", bundle: .module)
    }

    /// Shows the die in the material `Die20Assets.material(for:)` made for a dice color.
    @MainActor
    func apply(material: PhysicallyBasedMaterial) {
        guard var model = entity.components[ModelComponent.self] else { return }
        model.materials = model.materials.map { _ in material }
        entity.components.set(model)
    }

    @MainActor
    func playTossSound() {
        guard let audioPlaybackController else { return }
        audioPlaybackController.seek(to: .zero)
        audioPlaybackController.play()
    }
}
#endif
