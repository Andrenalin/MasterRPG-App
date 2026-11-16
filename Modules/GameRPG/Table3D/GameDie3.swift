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

/// The d3's materials. Its mesh is the d6's (`DieAssets.entity(named: "Die")`); what differs is the
/// texture: the numbers 1, 2 and 3 drawn into the faces' places on the d6's atlas, in the body and
/// numeral colors of a dice color code. The d6's normal, occlusion and roughness maps have its pips
/// baked in, so the d3 goes without them and is a smooth, glossy die.
@MainActor
enum Die3Assets {
    private static var materials: [String: PhysicallyBasedMaterial] = [:]

    /// The d3's material in the color of a dice color code, built once per code.
    static func material(for code: String) async -> PhysicallyBasedMaterial? {
        let code = TableDiePalette.resolvedCode(code, for: .d3)
        if let material = materials[code] {
            return material
        }
        guard let atlas = await renderAtlas(palette: .palette(for: code, kind: .d3)),
              let texture = try? await TextureResource(
                  image: atlas,
                  options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll)
              ) else {
            Logger.gameTable.error("Could not build the d3 material for color \(code, privacy: .public)")
            return nil
        }
        var material = GeneratedDie.placeholderMaterial()
        material.baseColor = .init(tint: .white, texture: .init(texture))
        let cached = materials[code] ?? material
        materials[code] = cached
        return cached
    }

    /// Draws the atlas: the die's body color everywhere, and on each face of the d6 mesh the number
    /// it shows on the d3, in the numeral color.
    @concurrent
    private static func renderAtlas(palette: TableDiePalette) async -> CGImage? {
        let size = 2048
        guard let context = GeneratedDie.bodyContext(width: size, height: size, palette: palette) else { return nil }
        for island in TableDie3Layout.islands {
            GeneratedDie.drawNumeral(
                String(island.number),
                at: CGPoint(x: CGFloat(island.center.x) * CGFloat(size), y: CGFloat(island.center.y) * CGFloat(size)),
                fontSize: CGFloat(size) * 0.2,
                underlined: false,
                color: GeneratedDie.cgColor(palette.pip),
                imageHeight: size,
                in: context
            )
        }
        return context.makeImage()
    }
}

// MARK: - Die

struct Die3: EntityEquipment {
    let id: ID
    let entity: Entity
    let audioPlaybackController: AudioPlaybackController?
    var initialState: DieState
    let representation: TossableRepresentation

    /// Returns the orientation of the die entity that shows the given value on top: the d6 face
    /// with as many pips as the value, which carries that number on the d3.
    ///
    /// Called by TabletopKit itself, not from our own code — see `Die.restingOrientation`.
    func restingOrientation(state: DieState) -> Rotation3D {
        guard state.value != TableDieValue.parked else { return .init() }
        guard let face = TableDie3Layout.faceUp(forValue: TableDieValue.face(state.value)),
              let orientation = Die.orientation(showingFace: face) else {
            Logger.gameTable.error("Invalid D3 die value \(state.value, privacy: .public); using default orientation as a fallback")
            return .init()
        }
        return orientation
    }

    @MainActor
    init(id: ID, seatControl: ControllingSeats = .any, seatIndex: Int = 0, dieNumber: Int = 1) {
        self.id = id
        // See the matching comment on `Die.init`: a missing asset degrades to a procedural mesh.
        do {
            self.entity = try DieAssets.entity(named: "Die")
        } catch {
            Logger.gameTable.error(
                "Failed to load the bundled Die RealityKit asset for the D3: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private); using a procedural fallback mesh"
            )
            self.entity = ModelEntity(mesh: .generateBox(size: 0.07), materials: [GeneratedDie.placeholderMaterial()])
        }
        // The d6's own material shows its pips; until the color's texture is ready, a plain one.
        GeneratedDie.setMaterial(GeneratedDie.placeholderMaterial(), in: self.entity)
        self.entity.name = "D3"
        do {
            let audioResource = try DieAssets.audio(named: "/Root/dieSoundShort_mp3")
            self.audioPlaybackController = self.entity.prepareAudio(audioResource)
        } catch {
            Logger.gameTable.error(
                "Failed to prepare the D3 roll sound: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)"
            )
            self.audioPlaybackController = nil
        }
        representation = .cube(height: entity.visualBounds(relativeTo: nil).extents.x)
        initialState = .init(value: 0, parentID: .tableId, seatControl: seatControl, pose: .parkedDicePose, entity: self.entity)

        // See the matching accessibility setup on `Die20.init`.
        self.entity.components.set(DiceComponent(dieId: id, sides: 3))
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = Self.accessibilityLabel(seatIndex: seatIndex, dieNumber: dieNumber)
        accessibility.systemActions = .activate
        self.entity.components.set(accessibility)
    }

    /// Seat 0 is always the game master (see `GameTableModel.assignSeatsForSharePlay`).
    private static func accessibilityLabel(seatIndex: Int, dieNumber: Int) -> LocalizedStringResource {
        seatIndex == 0
            ? LocalizedStringResource("Game master's D3 die \(dieNumber)", bundle: .module)
            : LocalizedStringResource("Player seat \(seatIndex) D3 die \(dieNumber)", bundle: .module)
    }

    /// Shows the die in the material `Die3Assets.material(for:)` made for a dice color.
    @MainActor
    func apply(material: PhysicallyBasedMaterial) {
        GeneratedDie.setMaterial(material, in: entity)
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
