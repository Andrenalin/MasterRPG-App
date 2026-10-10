// @copyright André Trettin

#if os(visionOS)
import CoreRPG
import Foundation
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

    static func audio(named path: String) throws -> AudioFileResource {
        if let resource = audioResources[path] {
            return resource
        }
        let resource = try AudioFileResource.load(
            named: path,
            from: "static_scene.usda",
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

/// Off-table park position for a pool die that isn't part of any seat's
/// currently focused set — every die's initial pose (`Die20`/`Die.init`),
/// and reapplied by `GameTableModel.applyDiceRoll` whenever a previously-
/// active slot falls out of the focused set. Replaces this table's
/// original approach of leaving the die at its (irrelevant) nominal
/// position and hiding it by setting `Entity.isEnabled = false` instead.
///
/// `Entity.isEnabled` is a purely local, unsynced RealityKit property —
/// none of Apple's own TabletopKit samples (dice, cards, the coin-
/// collecting mini-game) ever set it on equipment; every hide/park/reset
/// they show goes through the equipment's own *synced* pose or parentID
/// instead (e.g. the playing-card sample's own off-table `poseOffTable`
/// pattern this mirrors, or the mini-game's `ResetPlayer` moving a piece to
/// `.bankID(for:)`). A permanently-disabled die — every pool slot, from
/// creation, until its owning seat actually rolls — was never enabled on a
/// joining player's own device, and it turned out that also meant it was
/// never registered as "static equipment" for TabletopKit's own RealityKit-
/// level shared-simulation join there. The very first snapshot read that
/// touched one of those still-disabled dice crashed with "Could not find
/// static equipment with identifier: ...". Far outside the table's
/// 2.0×1.5 m surface (`GameMetrics.tableLength`/`tableWidth`) and every
/// seat position (`PlayerSeat.seatPoses`), so a parked die reads as
/// plainly off-table rather than overlapping a claimed seat.
extension TableVisualState.Pose2D {
    static var parkedDicePose: Self {
        .init(position: .init(x: -5, z: -5), rotation: .zero)
    }
}

struct Die20: EntityEquipment {
    let id: ID
    let entity: Entity
    let audioPlaybackController: AudioPlaybackController?
    var initialState: DieState
    let representation: TossableRepresentation

    // Return the orientation of the die entity to a given value face up.
    func restingOrientation(state: DieState) -> Rotation3D {
        // `0` is this table's own sentinel for a currently-unused pool slot
        // (see `GameSetup.maxDicePerType` and `TableVisualState.Pose2D.parkedDicePose`)
        // — the die is parked off-table whenever this holds, so its
        // orientation is irrelevant. Handled before the face lookup so it doesn't trip the
        // "invalid value" fallback below, which is for genuine sync issues.
        guard state.value != TableDieValue.parked else { return .init() }
        guard let normal = Self.faceNormals[TableDieValue.face(state.value)] else {
            // `state.value` arrives via TabletopKit's synchronized `UpdateEquipmentAction<DieState>`,
            // so a version skew or corrupted/delayed sync payload could plausibly deliver an
            // out-of-range value here. Log and fall back to the identity orientation instead of
            // crashing every SharePlay participant at once.
            Logger.gameTable.error("Invalid D20 die value \(state.value, privacy: .public); using identity orientation as a fallback")
            return .init()
        }

        let up = SIMD3<Float>(0, 1, 0)
        let cosine = min(max(dot(normal, up), -1), 1)
        let rotationAxis = cross(normal, up)
        let axisLength = length(rotationAxis)
        guard axisLength > 0.000_001 else {
            return cosine > 0
                ? .init()
                : .init(angle: .init(degrees: 180), axis: .init(x: 1, y: 0, z: 0))
        }

        let axis = rotationAxis / axisLength
        return .init(
            angle: .init(radians: acos(Double(cosine))),
            axis: .init(
                x: Double(axis.x),
                y: Double(axis.y),
                z: Double(axis.z)
            )
        )
    }

    /// Height (metres) the D20 presents on the table, whatever size its asset is authored at:
    /// `D20White.usdz` is an Object Capture scan at roughly real size (~35 mm).
    static let displayHeight: Float = 0.075

    /// Outward face normals of `D20White.usdz`, keyed by the number printed on that face.
    /// Measured from the scanned mesh (the numbers exist only in its baked texture) rather
    /// than taken from an idealized D20, so opposite faces are only ~179° apart. The asset
    /// rests with 1 on top (+y) and 20 underneath.
    private static let faceNormals: [Int: SIMD3<Float>] = [
        1:  .init(-0.02937186,  0.99942795, -0.01676517),
        2:  .init(-0.57530483, -0.76594368,  0.28697496),
        3:  .init( 0.46030532,  0.33109698, -0.82370735),
        4:  .init( 0.27046883, -0.31043183,  0.91130604),
        5:  .init(-0.67357019,  0.30542637,  0.67306607),
        6:  .init( 0.95596970, -0.29325682, -0.01106242),
        7:  .init(-0.54030937,  0.73680726, -0.40642447),
        8:  .init( 0.11184998, -0.75054924, -0.65127983),
        9:  .init( 0.90389291,  0.35227540,  0.24265129),
        10: .init(-0.47162709, -0.34664314, -0.81080603),
        11: .init( 0.48109705,  0.35400128,  0.80201541),
        12: .init(-0.90312790, -0.35696853, -0.23860733),
        13: .init(-0.11144258,  0.75399434,  0.64735855),
        14: .init( 0.55942843, -0.72638569,  0.39925389),
        15: .init(-0.95853365,  0.28476978,  0.01092795),
        16: .init( 0.69070339, -0.29553462, -0.65999100),
        17: .init(-0.25462721,  0.31287159, -0.91502806),
        18: .init(-0.45607540, -0.35027610,  0.81810872),
        19: .init( 0.59019689,  0.76037354, -0.27110831),
        20: .init( 0.04128365, -0.99912692,  0.00640834)
    ]

    @MainActor
    init(id: ID, seatControl: ControllingSeats = .any, seatIndex: Int = 0, dieNumber: Int = 1) {
        self.id = id
        // `entity` is a required, non-optional property of TabletopKit's `EntityEquipment`
        // protocol. Rather than crash the whole tabletop feature over a missing/corrupt
        // bundled asset (a packaging bug, not something reachable from user/runtime
        // conditions), fall back to a plain procedural mesh so the die still renders,
        // rolls, and reports a value — just without its custom artwork.
        let model: Entity
        do {
            model = try DieAssets.entity(named: "D20White")
        } catch {
            Logger.gameTable.error(
                "Failed to load the bundled D20White RealityKit asset: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private); using a procedural fallback mesh"
            )
            model = Self.makeFallbackEntity()
        }
        // Object Capture puts the scan's origin under its base, but TabletopKit turns and
        // rests a tossable about the equipment entity's own origin (Apple's `Die.usdz` is
        // authored centred for the same reason). Re-centre the mesh inside a pivot entity,
        // otherwise every face-up rotation would swing the die around its "20" face.
        let unscaledBounds = model.visualBounds(relativeTo: nil)
        model.position -= unscaledBounds.center
        let pivot = Entity()
        pivot.name = "D20"
        pivot.addChild(model)
        self.entity = pivot
        // Scale from the mesh's own unscaled bounds, read *before* any scale is applied —
        // see `representation` below for why its height isn't a post-scale `visualBounds` read.
        let unscaledHeight = unscaledBounds.extents.y
        if unscaledHeight > 0 {
            self.entity.scale = SIMD3<Float>(repeating: Self.displayHeight / unscaledHeight)
        }
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
        // `.icosahedron(height:)` wants the face-to-opposite-face measurement, i.e. the
        // vertical (+y) extent the die presents once resting on the table — which is what the
        // scale above normalizes to `displayHeight` (the asset rests on its "20" face).
        // Passed as that known constant, not a fresh post-scale
        // `entity.visualBounds(relativeTo: nil).extents.y` read: if `visualBounds` doesn't
        // immediately reflect the `.scale` just set (unverifiable without live device
        // testing), `representation` would describe a die of a different size than the one
        // rendered. TabletopKit's own toss physics uses `representation` for collision/rest,
        // so a mismatch makes the die fly off the table or sink into it instead of settling.
        representation = .icosahedron(height: Self.displayHeight)
        // `value: 0` — this table's own sentinel meaning "not part of the
        // seat's currently focused dice set" (see `GameTableModel.applyDiceRoll`);
        // `restingOrientation` above treats it specially rather than as a
        // corrupt/out-of-range value. `pose: .parkedDicePose` — every slot
        // starts off-table, not merely disabled; see that pose's own doc for
        // why a locally-disabled entity crashed a joining player instead of
        // just staying invisible.
        initialState = .init(value: 0, parentID: .tableId, seatControl: seatControl, pose: .parkedDicePose, entity: self.entity)

        // The direct on-table toss gesture otherwise has no accessible
        // equivalent. `GameTableModel.tossDieForAccessibility`
        // reads `DiceComponent` back out to apply a random result the same
        // way a character-sheet roll does (§5.1).
        self.entity.components.set(DiceComponent(dieId: id, sides: 20))
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = Self.accessibilityLabel(seatIndex: seatIndex, dieNumber: dieNumber)
        accessibility.systemActions = .activate
        self.entity.components.set(accessibility)

        // Deliberately no `self.entity.isEnabled = false` here — every seat's
        // pool is pre-allocated (TabletopKit equipment can't be added once
        // `TableSetup` is frozen), but hiding an unclaimed/unused slot is now
        // done entirely through its synced `.parkedDicePose` above, not by
        // disabling the entity. See that pose's own doc.
    }

    /// Seat 0 is always the game master (see `GameTableModel.assignSeatsForSharePlay`).
    private static func accessibilityLabel(seatIndex: Int, dieNumber: Int) -> LocalizedStringResource {
        seatIndex == 0
            ? LocalizedStringResource("Game master's D20 die \(dieNumber)", bundle: .module)
            : LocalizedStringResource("Player seat \(seatIndex) D20 die \(dieNumber)", bundle: .module)
    }

    @MainActor
    func playTossSound() {
        guard let audioPlaybackController else { return }
        audioPlaybackController.seek(to: .zero)
        audioPlaybackController.play()
    }

    /// A plain procedural stand-in for the bundled D20 mesh. Its own size is irrelevant:
    /// `init` scales whatever it gets to `displayHeight`, the same as the loaded asset.
    @MainActor
    private static func makeFallbackEntity() -> Entity {
        let model = ModelEntity(
            mesh: .generateSphere(radius: 0.5),
            materials: [SimpleMaterial(color: .white, isMetallic: false)]
        )
        model.name = "D20Fallback"
        return model
    }
}

struct Die: EntityEquipment {
    let id: ID
    let entity: Entity
    let audioPlaybackController: AudioPlaybackController?
    var initialState: DieState
    let representation: TossableRepresentation
    
    // Return the orientation of the die entity to a given value face up.
    func restingOrientation(state: DieState) -> Rotation3D {
        // The die asset's default orientation shows 6 on top (+y), 2 on the right (+x), and 3 on the front (+z).
        switch TableDieValue.face(state.value) {
            case 0:
                // This table's own sentinel for a currently-unused pool slot
                // (see `GameSetup.maxDicePerType`) — the die is hidden
                // whenever this holds, so its orientation is irrelevant.
                // Handled explicitly so it doesn't fall into (and log from)
                // the genuine-sync-issue `default` case below.
                return .init()
            case 1: // Flip upside down.
                return .init(angle: .init(degrees: +180), axis: .init(x: 0, y: 0, z: 1))
            case 2: // Flip to the left once.
                return .init(angle: .init(degrees: +90), axis: .init(x: 0, y: 0, z: 1))
            case 3: // Flip to the back once.
                return .init(angle: .init(degrees: -90), axis: .init(x: 1, y: 0, z: 0))
            case 4: // Flip to the front once.
                return .init(angle: .init(degrees: +90), axis: .init(x: 1, y: 0, z: 0))
            case 5: // Flip to the right once.
                return .init(angle: .init(degrees: -90), axis: .init(x: 0, y: 0, z: 1))
            case 6: // Default orientation.
                return .init()
            default:
                // Same out-of-range-value risk as `Die20.restingOrientation` above, reachable via
                // TabletopKit's synchronized `DieState` — fall back instead of crashing every
                // SharePlay participant at once.
                Logger.gameTable.error("Invalid die value \(state.value, privacy: .public); using default orientation as a fallback")
                return .init()
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
