// @copyright André Trettin

#if os(visionOS)
import CoreRPG
import Foundation
import ImageIO
import RealityKit
import RPGTabletopGameContent
import Spatial
import TabletopKit
import UIKit
import os.log

// MARK: - Shared Assets

/// Loads each bundled die mesh and roll sound once and hands out clones. Every seat pre-allocates a
/// pool of dice (`GameSetup.maxDicePerType` per type, per seat), so loading per die meant dozens of
/// identical synchronous disk loads on the main actor when the table opened.
@MainActor
enum DieAssets {
    private static var prototypes: [String: Entity] = [:]
    private static var audioResources: [String: AudioFileResource] = [:]

    static func entity(named name: String) throws -> Entity {
        if let prototype = prototypes[name] {
            return prototype.clone(recursive: true)
        }
        let prototype = try Entity.load(named: name, in: tabletopGameContentBundle)
        prototypes[name] = prototype
        return prototype.clone(recursive: true)
    }

    // MARK: d6 colors

    private static var d6Materials: [String: PhysicallyBasedMaterial] = [:]

    /// The d6's material in the color of a dice color code: the bundled die's own material (its
    /// normal, occlusion and roughness maps stay) with a base color atlas drawn from the code's
    /// palette — the body color where `DieFaceMask.png` is body, the pip color where it is a pip.
    /// Built once per code and cached; `nil` if the die asset or its mask can't be loaded.
    static func d6Material(for code: String) async -> PhysicallyBasedMaterial? {
        let code = TableDiePalette.resolvedCode(code, for: .d6)
        if let material = d6Materials[code] {
            return material
        }
        guard let prototype = try? entity(named: "Die"),
              var material = firstPhysicallyBasedMaterial(in: prototype),
              let atlas = await renderD6Atlas(palette: .palette(for: code, kind: .d6)),
              let texture = try? await TextureResource(
                  image: atlas,
                  options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll)
              ) else {
            Logger.gameTable.error("Could not build the d6 material for color \(code, privacy: .public); keeping the white die")
            return nil
        }
        material.baseColor = .init(tint: .white, texture: .init(texture))
        // A second caller may have finished first while this one was awaiting; keep one.
        let cached = d6Materials[code] ?? material
        d6Materials[code] = cached
        return cached
    }

    private static func firstPhysicallyBasedMaterial(in entity: Entity) -> PhysicallyBasedMaterial? {
        if let model = entity.components[ModelComponent.self],
           let material = model.materials.lazy.compactMap({ $0 as? PhysicallyBasedMaterial }).first {
            return material
        }
        return entity.children.lazy.compactMap { firstPhysicallyBasedMaterial(in: $0) }.first
    }

    /// Draws the die's base color atlas: every texel is the palette's pip color mixed with its
    /// body color by how much body the mask has there. Pure CPU work on a 2048² image, so it
    /// leaves the caller's actor.
    @concurrent
    private static func renderD6Atlas(palette: TableDiePalette) async -> CGImage? {
        guard let url = tabletopGameContentBundle.url(forResource: "DieFaceMask", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let mask = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let width = mask.width
        let height = mask.height

        var gray = [UInt8](repeating: 0, count: width * height)
        let drewMask = gray.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.draw(mask, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drewMask else { return nil }

        // One lookup per mask value instead of a mix per texel.
        func channel(_ pip: Float, _ body: Float, _ t: Float) -> UInt8 {
            UInt8((min(max(pip + (body - pip) * t, 0), 1) * 255).rounded())
        }
        let lookup: [(r: UInt8, g: UInt8, b: UInt8)] = (0 ... 255).map { value in
            let t = Float(value) / 255
            return (
                channel(palette.pip.red, palette.body.red, t),
                channel(palette.pip.green, palette.body.green, t),
                channel(palette.pip.blue, palette.body.blue, t)
            )
        }
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        for index in gray.indices {
            let color = lookup[Int(gray[index])]
            rgba[index * 4] = color.r
            rgba[index * 4 + 1] = color.g
            rgba[index * 4 + 2] = color.b
        }
        return rgba.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )?.makeImage()
        }
    }

    static func audio(named path: String) throws -> AudioFileResource {
        if let resource = audioResources[path] {
            return resource
        }
        let resource = try AudioFileResource.load(
            named: path,
            from: "dice_sounds.usda",
            in: tabletopGameContentBundle
        )
        audioResources[path] = resource
        return resource
    }
}

// MARK: - Dice Accessibility

/// Identifies a die entity for VoiceOver's accessibility "activate" gesture
/// — see `GameTableModel.tossDieForAccessibility`. Mirrors `PinComponent`/
/// `RoomComponent`, but on `Die20`/`Die` themselves (TabletopKit equipment,
/// not a plain entity), rather than on a wrapper class.
struct DiceComponent: Component {
    let dieId: EquipmentIdentifier
    let sides: Int
}

/// Off-table park position for a pool die that is not part of any seat's focused set: every die's
/// initial pose, and reapplied by `GameTableModel.applyDiceRoll` when a slot leaves the focused set.
///
/// Dice are parked by their synced pose, never by `Entity.isEnabled`: a permanently disabled die
/// was never registered as static equipment on a joining player's device, and the first snapshot
/// read of one crashed with "Could not find static equipment with identifier: ...". Far outside the
/// table surface and every seat position, so a parked die never overlaps a claimed seat.
extension TableVisualState.Pose2D {
    static var parkedDicePose: Self {
        .init(position: .init(x: -5, z: -5), rotation: .zero)
    }
}

struct Die: EntityEquipment {
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
        guard let orientation = Self.orientation(showingFace: TableDieValue.face(state.value)) else {
            // Same out-of-range-value risk as `Die20.restingOrientation` above, reachable via
            // TabletopKit's synchronized `DieState` — fall back instead of crashing every
            // SharePlay participant at once.
            Logger.gameTable.error("Invalid die value \(state.value, privacy: .public); using default orientation as a fallback")
            return .init()
        }
        return orientation
    }

    /// The orientation of the die asset that shows the face with this many pips on top, `nil`
    /// for a number the d6 has no face for. The asset's default orientation shows 6 on top (+y),
    /// 2 on the right (+x), and 3 on the front (+z).
    static func orientation(showingFace face: Int) -> Rotation3D? {
        switch face {
            case 1: // Flip upside down.
                .init(angle: .init(degrees: +180), axis: .init(x: 0, y: 0, z: 1))
            case 2: // Flip to the left once.
                .init(angle: .init(degrees: +90), axis: .init(x: 0, y: 0, z: 1))
            case 3: // Flip to the back once.
                .init(angle: .init(degrees: -90), axis: .init(x: 1, y: 0, z: 0))
            case 4: // Flip to the front once.
                .init(angle: .init(degrees: +90), axis: .init(x: 1, y: 0, z: 0))
            case 5: // Flip to the right once.
                .init(angle: .init(degrees: -90), axis: .init(x: 0, y: 0, z: 1))
            case 6: // Default orientation.
                .init()
            default:
                nil
        }
    }

    @MainActor
    init(id: ID, seatControl: ControllingSeats = .any, seatIndex: Int = 0, dieNumber: Int = 1) {
        self.id = id
        // `entity` is a required, non-optional property of TabletopKit's `EntityEquipment`
        // protocol — see the matching comment on `Die20.init` for why this degrades to a
        // procedural fallback mesh instead of crashing.
        do {
            self.entity = try DieAssets.entity(named: "Die")
        } catch {
            Logger.gameTable.error(
                "Failed to load the bundled Die RealityKit asset: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private); using a procedural fallback mesh"
            )
            self.entity = Self.makeFallbackEntity()
        }
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
        representation = .cube(height: entity.visualBounds(relativeTo: nil).extents.x)
        // `value: 0` — see the matching comment on `Die20.init`: this
        // table's own sentinel for "not part of the seat's currently
        // focused dice set". `pose: .parkedDicePose` — see the matching
        // comment on `Die20.init` for why.
        initialState = .init(value: 0, parentID: .tableId, seatControl: seatControl, pose: .parkedDicePose, entity: self.entity)

        // See the matching accessibility setup on `Die20.init`.
        self.entity.components.set(DiceComponent(dieId: id, sides: 6))
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = Self.accessibilityLabel(seatIndex: seatIndex, dieNumber: dieNumber)
        accessibility.systemActions = .activate
        self.entity.components.set(accessibility)

        // See the matching comment on `Die20.init` — deliberately no
        // `self.entity.isEnabled = false` here either.
    }

    /// Seat 0 is always the game master (see `GameTableModel.assignSeatsForSharePlay`).
    private static func accessibilityLabel(seatIndex: Int, dieNumber: Int) -> LocalizedStringResource {
        seatIndex == 0
            ? LocalizedStringResource("Game master's die \(dieNumber)", bundle: .module)
            : LocalizedStringResource("Player seat \(seatIndex) die \(dieNumber)", bundle: .module)
    }

    /// Shows the die in the material `DieAssets.d6Material(for:)` made for a dice color.
    @MainActor
    func apply(material: PhysicallyBasedMaterial) {
        Self.setMaterial(material, in: entity)
    }

    @MainActor
    private static func setMaterial(_ material: PhysicallyBasedMaterial, in entity: Entity) {
        if var model = entity.components[ModelComponent.self] {
            model.materials = model.materials.map { _ in material }
            entity.components.set(model)
        }
        for child in entity.children {
            setMaterial(material, in: child)
        }
    }

    @MainActor
    func playTossSound() {
        guard let audioPlaybackController else { return }
        if !audioPlaybackController.isPlaying {
            audioPlaybackController.seek(to: .zero)
            audioPlaybackController.play()
        }
    }

    /// Edge length (metres) of the procedural fallback cube. Unlike `Die20`, `Die` never applies a
    /// display scale, so its fallback is sized in physical units.
    private static let fallbackSize: Float = 0.07

    /// A plain procedural stand-in for the bundled Die mesh — see `Die20.makeFallbackEntity`.
    @MainActor
    private static func makeFallbackEntity() -> Entity {
        let model = ModelEntity(
            mesh: .generateBox(size: Self.fallbackSize),
            materials: [SimpleMaterial(color: .systemBlue, isMetallic: false)]
        )
        model.name = "DieFallback"
        return model
    }
}
#endif
