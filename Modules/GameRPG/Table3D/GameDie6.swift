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

/// The cube mesh of the d6 and the d3, and the d6's per-color materials. Like the other dice, there
/// is no asset in the package: the mesh is built from `TableDie6Geometry` and the pips are drawn
/// into a texture atlas per dice color.
@MainActor
enum Die6Assets {
    private static var mesh: MeshResource?
    private static var materials: [String: PhysicallyBasedMaterial] = [:]

    /// The cube, shared by the d6 and the d3: they differ in the texture only.
    static func meshResource() throws -> MeshResource {
        if let mesh {
            return mesh
        }
        // A small bezel on every edge; the faces keep their planes, so the rest height is unchanged.
        let bevelled = TableDieBevel.mesh(faces: TableDie6Geometry.faces.map {
            TableDieBevel.Face(corners: $0.corners, normal: $0.normal, atlas: TableDie6Geometry.atlasSquare(for: $0).coordinates)
        })
        var descriptor = MeshDescriptor(name: "D6")
        descriptor.positions = MeshBuffer(bevelled.positions)
        descriptor.normals = MeshBuffer(bevelled.normals)
        descriptor.textureCoordinates = MeshBuffer(bevelled.coordinates)
        descriptor.primitives = .triangles(bevelled.indices)
        let resource = try MeshResource.generate(from: [descriptor])
        mesh = resource
        return resource
    }

    /// The d6's material in the color of a dice color code, built once per code.
    static func material(for code: String) async -> PhysicallyBasedMaterial? {
        let code = TableDiePalette.resolvedCode(code, for: .d6)
        if let material = materials[code] {
            return material
        }
        guard let atlas = await renderAtlas(palette: .palette(for: code, kind: .d6)),
              let texture = try? await TextureResource(
                  image: atlas,
                  options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll)
              ) else {
            Logger.gameTable.error("Could not build the d6 material for color \(code, privacy: .public)")
            return nil
        }
        var material = GeneratedDie.placeholderMaterial()
        material.baseColor = .init(tint: .white, texture: .init(texture))
        let cached = materials[code] ?? material
        materials[code] = cached
        return cached
    }

    /// Draws the atlas: the die's body color everywhere, and on each face its pips in the pip color.
    @concurrent
    private static func renderAtlas(palette: TableDiePalette) async -> CGImage? {
        let cell = GeneratedDie.atlasCell
        let width = cell * TableDie6Geometry.atlasColumns
        let height = cell * TableDie6Geometry.atlasRows
        guard let context = GeneratedDie.bodyContext(width: width, height: height, palette: palette) else { return nil }
        context.setFillColor(GeneratedDie.cgColor(palette.pip))

        for face in TableDie6Geometry.faces {
            let center = TableDie6Geometry.atlasSquare(for: face).center
            // A face is `faceWidthInAtlas` of the atlas wide, so offsets in parts of its width
            // are that many atlas widths; the atlas is 3 × 2 cells of equal pixel size.
            let faceWidth = CGFloat(TableDie6Geometry.faceWidthInAtlas) * CGFloat(width)
            let radius = CGFloat(TableDie6Geometry.pipRadius) * faceWidth
            for offset in TableDie6Geometry.pipOffsets(for: face.number) {
                let x = CGFloat(center.x) * CGFloat(width) + CGFloat(offset.x) * faceWidth
                // The context's y axis points up, the atlas's down; offsets are y up as well.
                let y = CGFloat(height) - CGFloat(center.y) * CGFloat(height) + CGFloat(offset.y) * faceWidth
                context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
            }
        }
        return context.makeImage()
    }
}

// MARK: - Die

struct Die6: PoolDie {
    static var kind: TableDieKind { .d6 }
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
        // The 0 sentinel is this table's own for a currently-unused pool slot
        // (see `GameSetup.maxDicePerType`) — the die is parked off-table whenever this holds, so
        // its orientation is irrelevant. Handled before the face lookup so it doesn't fall into
        // (and log from) the genuine-sync-issue fallback below.
        guard TableDieValue.face(state.value) != 0 else { return .init() }
        guard let face = TableDie6Geometry.face(number: TableDieValue.face(state.value)) else {
            // `state.value` arrives via TabletopKit's synchronized `DieState`, so a version skew
            // or corrupted/delayed sync payload could plausibly deliver an out-of-range value —
            // fall back instead of crashing every SharePlay participant at once.
            Logger.gameTable.error("Invalid die value \(state.value, privacy: .public); using default orientation as a fallback")
            return .init()
        }
        return GeneratedDie.faceUpOrientation(normal: face.normal)
    }

    @MainActor
    init(id: ID, seatControl: ControllingSeats = .any, seatIndex: Int = 0, dieNumber: Int = 1) {
        self.id = id
        // `entity` is a required, non-optional property of TabletopKit's `EntityEquipment`
        // protocol, so a mesh that can't be generated degrades to a plain box instead of crashing.
        let model: Entity
        do {
            model = ModelEntity(mesh: try Die6Assets.meshResource(), materials: [GeneratedDie.placeholderMaterial()])
        } catch {
            Logger.gameTable.error("Failed to generate the D6 mesh: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private); using a procedural fallback mesh")
            model = ModelEntity(
                mesh: .generateBox(size: TableDie6Geometry.displayHeight),
                materials: [GeneratedDie.placeholderMaterial()]
            )
        }
        model.name = "D6"
        self.entity = model
        self.entity.spatialAudio = SpatialAudioComponent()
        do {
            // Unlike the entity itself, the roll sound is a nicety, not a hard
            // requirement — degrade to a silent die rather than crash the whole
            // tabletop feature over a missing/corrupt audio resource.
            let audioResource = try DieAssets.audio(named: "/Root/dieSoundShort_mp3")
            self.audioPlaybackController = self.entity.prepareAudio(audioResource)
        } catch {
            Logger.gameTable.error(
                "Failed to prepare the Die roll sound: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)"
            )
            self.audioPlaybackController = nil
        }
        representation = .cube(height: TableDie6Geometry.displayHeight)
        // `value: 0` — this table's own sentinel for "not part of the seat's currently focused
        // dice set". `pose: .parkedDicePose` — every slot starts off-table, not merely disabled;
        // see that pose's own doc.
        initialState = .init(value: 0, parentID: .tableId, seatControl: seatControl, pose: .parkedDicePose, entity: self.entity)

        // See the matching accessibility setup on `Die20.init`.
        self.entity.components.set(DiceComponent(dieId: id, sides: 6))
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = Self.accessibilityLabel(seatIndex: seatIndex, dieNumber: dieNumber)
        accessibility.systemActions = .activate
        self.entity.components.set(accessibility)
    }

    /// Seat 0 is always the game master (see `GameTableModel.assignSeatsForSharePlay`).
    private static func accessibilityLabel(seatIndex: Int, dieNumber: Int) -> LocalizedStringResource {
        seatIndex == 0
            ? LocalizedStringResource("Game master's die \(dieNumber)", bundle: .module)
            : LocalizedStringResource("Player seat \(seatIndex) die \(dieNumber)", bundle: .module)
    }

    /// Shows the die in the material `Die6Assets.material(for:)` made for a dice color.
    @MainActor
    func apply(material: PhysicallyBasedMaterial) {
        guard var model = entity.components[ModelComponent.self] else { return }
        model.materials = model.materials.map { _ in material }
        entity.components.set(model)
    }
}
#endif
