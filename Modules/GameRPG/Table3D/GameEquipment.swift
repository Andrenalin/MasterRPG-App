// @copyright André Trettin

#if os(visionOS)
import CoreRPG
import Foundation
import GroupActivities
import MapRPG
import TabletopKit
import RealityKit
import RPGTabletopGameContent
import Spatial
import DeveloperToolsSupport
import SwiftUI
import UIKit
import Combine
import os.log

extension EquipmentIdentifier {
    static var tableID: Self { .init(0) }
}

struct Table: Tabletop {
    // `width` is TabletopKit's X-extent, `height` its Z-extent (matching
    // `TableAssetFactory.makePlainWoodTable()`'s own `generateBox(width:height:depth:)`
    // call for the same mesh). The table's long dimension runs along Z
    // (`tableLength`), not X, so the long sides recede away from the
    // viewer instead of spanning left-right in front of them — see
    // `PlayerSeat.seatPoses`'s own doc for the seat layout this supports.
    var shape: TabletopShape = .rectangular(
        width: GameMetrics.tableWidth,
        height: GameMetrics.tableLength,
        thickness: GameMetrics.tableThickness
    )

    var id: EquipmentIdentifier = .tableID
}

/// Static map surface rendered in the same coordinate space as the wood table
/// and synchronized pins. It deliberately isn't TabletopKit equipment:
/// TabletopKit rests equipment against its centered table shape, while this
/// scene's generated table uses its bottom as y = 0.
@MainActor
final class Board {
    let entity: Entity
    
    // The map is a thin image plane directly on the tabletop.
    private let imagePlane: ModelEntity

    init() {
        let maxPlaneWidth = MapTableProjection.maxPlaneWidth
        let maxPlaneDepth = MapTableProjection.maxPlaneDepth
        let boardEntity = Entity()
        boardEntity.name = "MapSurface"

        let plane = ModelEntity(
            mesh: .generatePlane(width: maxPlaneWidth, depth: maxPlaneDepth),
            materials: [SimpleMaterial(color: .white, isMetallic: false)]
        )
        // The map surface shares the bottom-origin coordinate space used by
        // the generated wood mesh and the synchronized pin container.
        plane.position.y = GameMetrics.tableThickness + GameMetrics.mapSurfaceClearance
        plane.name = "MapImagePlane"
        plane.isEnabled = false
        // Hit-testable so `viewportPanGesture` (GameTableView) can target the
        // map surface directly, separately from pins and room fog — mirrors
        // `GamePortableEntities.Board`'s iOS/macOS setup exactly, including
        // its hit-test box sitting below `RoomHitArea`'s ±0.004 box around
        // this same Y so a touch over a room's fog always hits the closer
        // room volume first. See CODE_AUDIT §8.1.
        plane.components.set(BoardSurfaceComponent())
        plane.components.set(InputTargetComponent())
        plane.components.set(
            CollisionComponent(shapes: [
                ShapeResource
                    .generateBox(width: maxPlaneWidth, height: Self.hitTestBoxHeight, depth: maxPlaneDepth)
                    .offsetBy(translation: SIMD3<Float>(0, Self.hitTestYOffset, 0))
            ])
        )
        boardEntity.addChild(plane)
        self.imagePlane = plane

        self.entity = boardEntity
    }

    private static let hitTestBoxHeight: Float = 0.002
    /// Local offset (relative to `imagePlane`, itself at world Y ==
    /// `GameSetup.pinHeight`) putting the hit-test box's whole height range
    /// below `pinHeight - 0.004` — `RoomHitArea`'s lower bound — with a clear
    /// margin. Matches `GamePortableEntities.Board`'s identical constants.
    private static let hitTestYOffset: Float = -0.006
        
    // Update the map from PhotoModel data while preserving its aspect ratio.
    func updateMap(image: AKImage, degrees: Double, displayConfig: DisplayConfigModel?, mapModel: MapModel?, isGameMaster: Bool, panOffset: CGPoint) {
        guard image.cgImage != nil else {
            Logger.gameTable.error("Failed to create a board image from the current photo")
            return
        }

        // Map rooms and pins are stored in the photo's oriented coordinate space.
        // Size the board from that same space so the texture and tokens agree at
        // 90/270-degree rotations.
        let displaySize = mapModel.map {
            CGSize(width: $0.width, height: $0.height)
        } ?? Self.orientedSize(for: image.fixedSize, degrees: degrees)
        guard displaySize.width > 0, displaySize.height > 0 else { return }
        let aspectRatio = displaySize.width / displaySize.height
        
        var planeWidth: Float
        var planeDepth: Float

        // Fit inside the (possibly non-square) `maxPlaneWidth` ×
        // `maxPlaneDepth` box preserving aspect ratio — mirrors
        // `MapTableProjection.init`'s identical fit-box math, which this
        // plane's dimensions must stay in lockstep with so pins/rooms line
        // up with the rendered texture.
        let boxAspectRatio = MapTableProjection.maxPlaneWidth / MapTableProjection.maxPlaneDepth
        if aspectRatio > Double(boxAspectRatio) {
            // Width constrained
            planeWidth = MapTableProjection.maxPlaneWidth
            planeDepth = MapTableProjection.maxPlaneWidth / Float(aspectRatio)
        } else {
            // Depth constrained
            planeDepth = MapTableProjection.maxPlaneDepth
            planeWidth = MapTableProjection.maxPlaneDepth * Float(aspectRatio)
        }
        
        // Update image plane mesh with correct aspect ratio
        imagePlane.model?.mesh = .generatePlane(width: planeWidth, depth: planeDepth)
        
        // Always orient the photo before applying fog. Map entry coordinates are
        // already expressed in this oriented canvas.
        guard let compositeImage = generateCompositeTexture(
            baseImage: image,
            degrees: degrees,
            canvasSize: displaySize,
            mapModel: mapModel,
            displayConfig: displayConfig,
            isGameMaster: isGameMaster,
            panOffset: panOffset
        ) else { return }
        
        // Update the texture using new visionOS 2.0+ API
        do {
            let texture = try TextureResource(image: compositeImage, options: .init(semantic: .color))
            var mapMaterial = UnlitMaterial()
            mapMaterial.color = .init(texture: .init(texture))
            imagePlane.model?.materials = [mapMaterial]
            imagePlane.isEnabled = true
        } catch {
            Logger.gameTable.error(
                "Failed to create the visionOS board texture: \(error.localizedDescription, privacy: .public)"
            )
            var mapMaterial = UnlitMaterial()
            mapMaterial.color = .init(tint: .gray)
            imagePlane.model?.materials = [mapMaterial]
            imagePlane.isEnabled = true
        }
        
    }

    /// Removes a previously rendered map when game selection or photo loading
    /// no longer supplies a board image.
    func clearMap() {
        imagePlane.isEnabled = false
    }
    
    // Generate a composite texture with fog of war overlays drawn on top of the base image
    @MainActor private func generateCompositeTexture(
        baseImage: AKImage,
        degrees: Double,
        canvasSize: CGSize,
        mapModel: MapModel?,
        displayConfig: DisplayConfigModel?,
        isGameMaster: Bool,
        panOffset: CGPoint
    ) -> CGImage? {
        guard let fallbackImage = baseImage.cgImage else { return nil }
        let normalizedDegrees = degrees.truncatingRemainder(dividingBy: 360)
        let sourceSize = baseImage.fixedSize
        let orientedSize = Self.orientedSize(for: sourceSize, degrees: normalizedDegrees)
        let entriesToRender = if isGameMaster {
            mapModel?.entries ?? []
        } else {
            mapModel?.entries.filter { !$0.isShown } ?? []
        }

        // Always the full map — the 3D board never crops/zooms into a
        // focused room (only the 2D map does; see `GameTableModel.boardFocusRect`).
        // `canvasSize` doubles as both the entries' coordinate space and the
        // output frame here (unlike the iOS/macOS renderer, which keeps them
        // separate), so this needs no unit conversion before use below.
        let focusRect = GameTableModel.boardFocusRect(
            entries: mapModel?.entries ?? [],
            imageSize: canvasSize,
            panOffset: panOffset
        )
        let zoomScaleX = focusRect.width > 0 ? canvasSize.width / focusRect.width : 1
        let zoomScaleY = focusRect.height > 0 ? canvasSize.height / focusRect.height : 1

        // Create a SwiftUI view that layers the image with fog of war overlays
        let compositeView = ZStack {
            ZStack {
                Image(akImage: baseImage)
                    .resizable()
                    .frame(width: sourceSize.width, height: sourceSize.height)
                    .rotationEffect(.degrees(normalizedDegrees))
            }
            .frame(width: orientedSize.width, height: orientedSize.height)
            .frame(width: canvasSize.width, height: canvasSize.height)
            
            Canvas { context, size in
                // Draw each entry as a polygon
                for entry in entriesToRender {
                    guard !entry.coordinates.isEmpty else { continue }
                    
                    // Create a path from the entry coordinates
                    var path = Path()
                    let firstPoint = entry.coordinates[0]
                    path.move(to: firstPoint)
                    
                    for point in entry.coordinates.dropFirst() {
                        path.addLine(to: point)
                    }
                    
                    // Close the path
                    path.closeSubpath()
                    
                    if isGameMaster {
                        // Game Master: Show transparent green with border (matching MapViewer .master mode)
                        if entry.isShown {
                            // Shown areas: light green (opacity 0.1) with green border
                            context.fill(path, with: .color(Color.green.opacity(0.1)))
                            context.stroke(
                                path,
                                with: .color(Color.green.opacity(0.8)),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
                            )
                        } else {
                            // Hidden areas: semi-transparent green (opacity 0.5) with green border
                            context.fill(path, with: .color(Color.green.opacity(0.5)))
                            context.stroke(
                                path,
                                with: .color(Color.green.opacity(0.8)),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
                            )
                        }
                    } else {
                        // Player: Only show solid fog for hidden areas (matching MapViewer .player mode)
                        if !entry.isShown {
                            // Fill with the configured fog color
                            context.fill(path, with: .color(displayConfig?.color ?? .black))

                            // Draw border if configured
                            if displayConfig?.hasBorder == true, let displayConfig {
                                context.stroke(
                                    path,
                                    with: .color(displayConfig.borderColor),
                                    lineWidth: displayConfig.borderThickness
                                )
                            }
                        }
                    }

                    // The 3D board never crops/zooms into a focused room (see
                    // `GameTableModel.boardFocusRect`) — a red border marks
                    // where the 2D map's own zoom is centered instead.
                    if entry.focused {
                        context.stroke(
                            path,
                            with: .color(.red),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round)
                        )
                    }
                }
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        // No-ops (scale 1, offset 0) when nothing is focused — `focusRect`
        // then equals the full `canvasSize` rect.
        .scaleEffect(x: zoomScaleX, y: zoomScaleY, anchor: .topLeading)
        .offset(x: -focusRect.minX * zoomScaleX, y: -focusRect.minY * zoomScaleY)
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        .clipped()

        // The frame is already expressed in image-space pixels/points. Rendering
        // it at 3x attempted textures up to nine times larger than necessary and
        // stalled room toggles on the main actor. Keep the longest edge within a
        // conservative GPU texture budget.
        let renderer = ImageRenderer(content: compositeView)
        let longestEdge = max(canvasSize.width, canvasSize.height)
        renderer.scale = longestEdge > 0 ? min(1, 2_048 / longestEdge) : 1
        
        #if os(macOS)
        if let nsImage = renderer.nsImage,
           let tiffData = nsImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let cgImage = bitmap.cgImage {
            return cgImage
        }
        #else
        if let uiImage = renderer.uiImage,
           let cgImage = uiImage.cgImage {
            return cgImage
        }
        #endif
        
        Logger.gameTable.warning("Failed to composite the board texture; using the original image")
        return fallbackImage
    }

    private static func orientedSize(for size: CGSize, degrees: Double) -> CGSize {
        let normalized = abs(degrees.truncatingRemainder(dividingBy: 180))
        guard abs(normalized - 90) < 0.001 else { return size }
        return CGSize(width: size.height, height: size.width)
    }
}

struct PlayerSeat: TableSeat {
    let id: ID
    var initialState: TableSeatState

    /* Six seats around the rectangular table: the master (index 0) centered
    on the near (+Z, South, viewer-facing) short edge, with the table's
    long sides running away from the viewer along Z rather than spanning
    left-right in front of them. Four more seats flank those long
    (West/East) sides in two bands — near master (indices 1–2) and toward
    the far end (indices 3–4) — and the sixth seat (index 5) sits opposite
    the master on the far (-Z, North) short edge. Each seat faces the
    center of the table. The master sits on the near short edge
    specifically so it lines up with the volumetric window's own default
    viewing position and this view's ornaments/dice-bar (see `GameSetup`'s
    own doc for why — without an active SharePlay session, nothing else
    rotates the table to face whichever seat is claimed).
    `assignSeatsForSharePlay` claims seats 1...5 in this array's order, so
    joining players fill West-then-East, near-band-then-far-band, exactly
    matching the order below. Every short-edge/long-side seat still sits a
    full table-length/-width beyond the table center along its own axis —
    same "well beyond the physical edge, the way a chair sits beyond a real
    table's edge" ratio the original layout used (see `diceLayout`'s doc
    for the matching dice-side reasoning). */
    @MainActor static let seatPoses: [TableVisualState.Pose2D] = [
        // Master — South (near, +Z) short edge, centered.
        .init(position: .init(x: 0, z: Double(GameMetrics.tableLength)), rotation: .degrees(0)),
        // West side, near band (close to master/South).
        .init(position: .init(x: -Double(GameMetrics.tableWidth), z: 0.5), rotation: .degrees(270)),
        // East side, near band (close to master/South).
        .init(position: .init(x: Double(GameMetrics.tableWidth), z: 0.5), rotation: .degrees(90)),
        // West side, far band (toward North).
        .init(position: .init(x: -Double(GameMetrics.tableWidth), z: -0.5), rotation: .degrees(270)),
        // East side, far band (toward North).
        .init(position: .init(x: Double(GameMetrics.tableWidth), z: -0.5), rotation: .degrees(90)),
        // North (far, -Z) short edge — the sixth seat.
        .init(position: .init(x: 0, z: -Double(GameMetrics.tableLength)), rotation: .degrees(180))
    ]

    init(id: TableSeatIdentifier, pose: TableVisualState.Pose2D) {
        self.id = id
        let spatialSeatPose: TableVisualState.Pose2D = .init(position: pose.position,
                                                             rotation: pose.rotation)
        initialState = .init(pose: spatialSeatPose)
    }

    /// `count` table-plane positions in the given seat's own player area,
    /// laid out side by side and centered on the seat itself — for that
    /// seat's own dice, sized to however many `GameTableModel.applyDiceRoll`
    /// currently needs visible (see `GameSetup.maxDicePerType`), not the
    /// full pre-allocated pool.
    ///
    /// Derived from the seat's own facing `rotation`, not a radius along its
    /// raw `position` (the original single-seat-per-side approach): with two
    /// seats sharing a long side (see `seatPoses`), both share the same
    /// facing direction but sit at different lateral offsets, so the row
    /// needs to be centered under *this* seat's own position, not the
    /// table's. `direction` (the seat's own outward-facing axis) locates
    /// that near table edge — inset by `GameMetrics.diceEdgeInset` so the
    /// dice land just inside the table's physical edge rather than off the
    /// surface, the way a chair sits beyond that edge. `lateralOffset`
    /// re-centers the row under the seat's actual lateral position along
    /// that edge.
    @MainActor
    static func diceLayout(inFrontOf seatPose: TableVisualState.Pose2D, count: Int) -> [TableVisualState.Pose2D] {
        guard count > 0 else { return [] }
        let radians = seatPose.rotation.radians
        // The direction a seat at this rotation faces *away* from the table
        // center — e.g. a north-side seat (rotation 0°, facing into the
        // table) points further north. Dice sit between the seat and the
        // center, along this same axis. See `PlayerSeat.seatPoses`'s doc for
        // why rotation 0° maps to +Z here.
        let direction: (x: Double, z: Double) = (sin(radians), cos(radians))
        // Perpendicular to `direction`, to spread the dice apart and to
        // locate the seat's own lateral position along its edge.
        let lateral: (x: Double, z: Double) = (-direction.z, direction.x)

        // The seat's near table edge along its own facing axis. `direction`
        // is always axis-aligned (a multiple of 90°), so exactly one term is
        // non-zero — this picks `tableWidth` (X is the short axis now) for
        // the West/East long-side seats, and `tableLength` (Z is the long
        // axis now) for the South/North short-edge seats, automatically.
        let halfExtent = abs(direction.x) * Double(GameMetrics.tableWidth / 2)
            + abs(direction.z) * Double(GameMetrics.tableLength / 2)
        let radius = halfExtent - Double(GameMetrics.diceEdgeInset)

        // This seat's own position along the lateral axis — 0 for the
        // single end seats (which sit exactly on `direction`'s own axis),
        // non-zero for a long-side seat sharing that side with another.
        let seatPosition = seatPose.position
        let lateralOffset = seatPosition.x * lateral.x + seatPosition.z * lateral.z

        // Distance between neighboring dice, center to center. This was
        // shrunk from the original 2-die-only layout's 0.14 m to 0.05 m to
        // keep a seat's row compact at `maxDicePerType`'s largest realistic
        // mixes, but never re-checked against the die's own physical size —
        // at 0.05 m, two ~0.075 m-wide D20s (see `Die20`'s own
        // `representation`) overlap enough that TabletopKit resolves it by
        // resting one on top of the other instead of side by side. 0.11 m
        // (tried first, aiming for the "half a die's width" gap this method
        // was originally asked for) still left a partial, roughly
        // half-die-height overlap — the die's true collision size needs
        // closer to that original 0.14 m after all. 0.15 m stays a hair
        // above it for margin, since the previous, closer-but-still-short
        // guess undershot.
        let spacing = 0.15
        let totalWidth = spacing * Double(count - 1)

        return (0 ..< count).map { index in
            let offset = lateralOffset + Double(index) * spacing - totalWidth / 2
            return TableVisualState.Pose2D(
                position: .init(
                    x: direction.x * radius + lateral.x * offset,
                    z: direction.z * radius + lateral.z * offset
                ),
                rotation: .zero
            )
        }
    }
}

// MARK: - Dice Accessibility

/// Identifies a die entity for VoiceOver's accessibility "activate" gesture
/// — see `GameTableModel.tossDieForAccessibility`. Mirrors `PinComponent`/
/// `RoomComponent`, but on `Die20`/`Die` themselves (TabletopKit equipment,
/// not a plain entity), rather than on a wrapper class. See CODE_AUDIT §8.2.
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
        guard state.value != 0 else { return .init() }
        guard let normal = Self.faceNormals[state.value] else {
            // `state.value` arrives via TabletopKit's synchronized `UpdateEquipmentAction<DieState>`,
            // so a version skew or corrupted/delayed sync payload could plausibly deliver an
            // out-of-range value here. Log and fall back to the identity orientation instead of
            // crashing every SharePlay participant at once. See CODE_AUDIT §5.2.
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

    /// Outward normals measured from the engraved faces in `D20Blue.usdz`.
    /// They intentionally describe the asset rather than an idealized D20;
    /// the source mesh includes a small built-in tilt.
    private static let faceNormals: [Int: SIMD3<Float>] = [
        1:  .init(-0.00000010, -0.98224616, -0.18759662),
        2:  .init( 0.57735944,  0.79464918, -0.18758698),
        3:  .init(-0.93417156, -0.30353564, -0.18758911),
        4:  .init( 0.57735360,  0.18759663,  0.79465115),
        5:  .init( 0.93417138, -0.30353573, -0.18758917),
        6:  .init(-0.35682914, -0.49112195,  0.79465228),
        7:  .init( 0.00000001, -0.60706472, -0.79465228),
        8:  .init(-0.57735920,  0.79464918, -0.18758711),
        9:  .init(-0.57735366,  0.18759674,  0.79465103),
        10: .init(-0.35682899,  0.49112207, -0.79465228),
        11: .init( 0.35682896, -0.49112198,  0.79465222),
        12: .init( 0.35682914,  0.49112195, -0.79465228),
        13: .init( 0.57735920, -0.79464912,  0.18758705),
        14: .init(-0.00000001,  0.60706478,  0.79465228),
        15: .init( 0.57735366, -0.18759671, -0.79465091),
        16: .init(-0.93417144,  0.30353579,  0.18758918),
        17: .init(-0.57735354, -0.18759662, -0.79465109),
        18: .init( 0.93417156,  0.30353567,  0.18758911),
        19: .init(-0.57735932, -0.79464906,  0.18758710),
        20: .init( 0.00000004,  0.98224616,  0.18759669)
    ]
    
    @MainActor
    init(id: ID, seatControl: ControllingSeats = .any, seatIndex: Int = 0, dieNumber: Int = 1) {
        self.id = id
        // `entity` is a required, non-optional property of TabletopKit's `EntityEquipment`
        // protocol. Rather than crash the whole tabletop feature over a missing/corrupt
        // bundled asset (a packaging bug, not something reachable from user/runtime
        // conditions), fall back to a plain procedural mesh so the die still renders,
        // rolls, and reports a value — just without its custom artwork.
        do {
            self.entity = try Entity.load(named: "D20Blue", in: tabletopGameContentBundle)
        } catch {
            Logger.gameTable.error(
                "Failed to load the bundled D20Blue RealityKit asset: \(error.localizedDescription, privacy: .public); using a procedural fallback mesh"
            )
            self.entity = Self.makeFallbackEntity()
        }
        // Read the mesh's own unscaled bounds *before* applying the display
        // scale below, then multiply by that same known factor explicitly —
        // see `representation`'s own doc for why relying on `visualBounds`
        // to already reflect the just-set `.scale` isn't safe enough here.
        let unscaledHeight = self.entity.visualBounds(relativeTo: nil).extents.y
        self.entity.scale.x = 0.00025
        self.entity.scale.y = 0.00025
        self.entity.scale.z = 0.00025
        self.entity.spatialAudio = SpatialAudioComponent()
        do {
            // Keep the sound authored in Reality Composer Pro and prepare it
            // on the die so RealityKit emits it from the moving D20 location.
            let audioResource = try AudioFileResource.load(
                named: "/Root/dieSoundLong_mp3",
                from: "static_scene.usda",
                in: tabletopGameContentBundle
            )
            self.audioPlaybackController = self.entity.prepareAudio(audioResource)
        } catch {
            Logger.gameTable.error(
                "Failed to prepare the D20 roll sound: \(error.localizedDescription, privacy: .public)"
            )
            self.audioPlaybackController = nil
        }
        // `.icosahedron(height:)` wants the face-to-opposite-face measurement, i.e. the
        // vertical (+y) extent the die presents once resting on the table — not `.extents.x`,
        // which `Die` (a cube, symmetric on every axis) can get away with but a D20 can't.
        // Computed from `unscaledHeight * 0.00025`, not a fresh post-scale
        // `entity.visualBounds(relativeTo: nil).extents.y` read: `Die` (a cube) never sets
        // its own `.scale` at all, so it has no equivalent risk — but for `Die20`, if
        // `visualBounds` doesn't immediately reflect the `.scale` set just above (unverifiable
        // without live device testing), `representation` would describe a die roughly 4000×
        // larger than what's actually rendered. TabletopKit's own toss physics uses
        // `representation` for collision/rest — a mismatch that size would make it treat a
        // few-centimeter die as several meters across, which is consistent with the die flying
        // wildly off the table after a toss instead of settling on it. Multiplying the known
        // pre-scale bounds by the same literal scale factor sidesteps the question entirely.
        representation = .icosahedron(height: unscaledHeight * 0.00025)
        // `value: 0` — this table's own sentinel meaning "not part of the
        // seat's currently focused dice set" (see `GameTableModel.applyDiceRoll`);
        // `restingOrientation` above treats it specially rather than as a
        // corrupt/out-of-range value. `pose: .parkedDicePose` — every slot
        // starts off-table, not merely disabled; see that pose's own doc for
        // why a locally-disabled entity crashed a joining player instead of
        // just staying invisible.
        initialState = .init(value: 0, parentID: .tableID, seatControl: seatControl, pose: .parkedDicePose, entity: self.entity)

        // The direct on-table toss gesture otherwise has no accessible
        // equivalent — see CODE_AUDIT §8.2. `GameTableModel.tossDieForAccessibility`
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

    /// Seat 0 is always the game master (see `GameEquipment.assignSeatsForSharePlay`).
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

    /// A plain procedural stand-in for the bundled D20 mesh, sized so it still
    /// looks and behaves like a die after the same 0.00025 scale factor applied
    /// to the loaded asset is applied to it.
    @MainActor
    private static func makeFallbackEntity() -> Entity {
        let model = ModelEntity(
            mesh: .generateSphere(radius: 80),
            materials: [SimpleMaterial(color: .systemBlue, isMetallic: false)]
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
        switch state.value {
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
                // SharePlay participant at once. See CODE_AUDIT §5.2.
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
            self.entity = try Entity.load(named: "Die", in: tabletopGameContentBundle)
        } catch {
            Logger.gameTable.error(
                "Failed to load the bundled Die RealityKit asset: \(error.localizedDescription, privacy: .public); using a procedural fallback mesh"
            )
            self.entity = Self.makeFallbackEntity()
        }
        do {
            // Unlike the entity itself, the roll sound is a nicety, not a hard
            // requirement — degrade to a silent die rather than crash the whole
            // tabletop feature over a missing/corrupt audio resource.
            let audioResource = try AudioFileResource.load(
                named: "/Root/dieSoundShort_mp3",
                from: "static_scene.usda",
                in: tabletopGameContentBundle
            )
            self.audioPlaybackController = self.entity.prepareAudio(audioResource)
        } catch {
            Logger.gameTable.error(
                "Failed to prepare the Die roll sound: \(error.localizedDescription, privacy: .public)"
            )
            self.audioPlaybackController = nil
        }
        representation = .cube(height: entity.visualBounds(relativeTo: nil).extents.x)
        // `value: 0` — see the matching comment on `Die20.init`: this
        // table's own sentinel for "not part of the seat's currently
        // focused dice set". `pose: .parkedDicePose` — see the matching
        // comment on `Die20.init` for why.
        initialState = .init(value: 0, parentID: .tableID, seatControl: seatControl, pose: .parkedDicePose, entity: self.entity)

        // See the matching accessibility setup on `Die20.init` (CODE_AUDIT §8.2).
        self.entity.components.set(DiceComponent(dieId: id, sides: 6))
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = Self.accessibilityLabel(seatIndex: seatIndex, dieNumber: dieNumber)
        accessibility.systemActions = .activate
        self.entity.components.set(accessibility)

        // See the matching comment on `Die20.init` — deliberately no
        // `self.entity.isEnabled = false` here either.
    }

    /// Seat 0 is always the game master (see `GameEquipment.assignSeatsForSharePlay`).
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

    /// A plain procedural stand-in for the bundled Die mesh — see `Die20.makeFallbackEntity`.
    @MainActor
    private static func makeFallbackEntity() -> Entity {
        let model = ModelEntity(
            mesh: .generateBox(size: 140),
            materials: [SimpleMaterial(color: .systemBlue, isMetallic: false)]
        )
        model.name = "DieFallback"
        return model
    }
}

// MARK: - SharePlay Seat Assignment

extension GameTableModel {
    /// Assigns seats to SharePlay participants. Master always gets seat 0; players fill seats 1+.
    ///
    /// The table only has `PlayerSeat.seatPoses.count - 1` physical player
    /// seats (currently 5 — see `PlayerSeat.seatPoses`). A party larger than
    /// that therefore always has multiple players share a seat — and with
    /// it, the seat's dice pools from `GameSetup.playerD20Ids`/
    /// `playerD6Ids`, so a character-sheet roll from one of those players
    /// moves the dice the other(s) also treat as their own.
    /// This can't be eliminated purely by reindexing (there are only 5
    /// buckets for larger parties), but it's now deterministic — every
    /// device computes the same sorted `activeParticipants` list — and
    /// surfaced via `sharedSeatPlayerCount` and a log instead of being
    /// silent. See CODE_AUDIT §5.2.
    /// Submits `claimSeat` only if this exact `(session, seat)` pair hasn't
    /// already been requested — see `GameTableModel.lastRequestedSeatAssignment`'s
    /// own doc for why a redundant identical claim is unsafe, not just
    /// wasteful.
    @MainActor
    private func claimSeatIfNeeded(_ seatId: TableSeatIdentifier, sessionId: UUID) {
        guard lastRequestedSeatAssignment?.sessionId != sessionId
            || lastRequestedSeatAssignment?.seatId != seatId
        else { return }
        lastRequestedSeatAssignment = (sessionId, seatId)
        tabletopGame.claimSeat(matching: seatId)
    }

    @MainActor
    func assignSeatsForSharePlay(groupSession: GroupSession<RPGActivity>?, isMaster: Bool) {
        guard let groupSession else {
            Logger.sharePlay.debug("No active GroupSession — claiming any seat for single player")
            sharedSeatPlayerCount = nil
            lastRequestedSeatAssignment = nil
            tabletopGame.claimAnySeat()
            return
        }

        Logger.sharePlay.debug("SharePlay seat assignment for \(groupSession.activeParticipants.count, privacy: .public) participants (isMaster: \(isMaster, privacy: .public))")

        if isMaster {
            claimSeatIfNeeded(TableSeatIdentifier(0), sessionId: groupSession.id)
            sharedSeatPlayerCount = nil
            Logger.sharePlay.debug("Assigned seat 0 (master)")
            return
        }

        // Players sort by ID for consistent assignment; seat 0 is reserved
        // for master. `activeParticipants` carries no host/role marker, so
        // the master's own participant can't be excluded from this ranking
        // — it simply occupies one rank alongside everyone else and is
        // handled entirely by the `isMaster` branch above.
        let localParticipant = groupSession.localParticipant
        let sortedParticipants = groupSession.activeParticipants
            .sorted { $0.id.uuidString < $1.id.uuidString }

        guard let localIndex = sortedParticipants.firstIndex(where: { $0.id == localParticipant.id }) else {
            Logger.sharePlay.debug("Could not find local participant — claiming any seat")
            sharedSeatPlayerCount = nil
            lastRequestedSeatAssignment = nil
            tabletopGame.claimAnySeat()
            return
        }

        // Seat 0 is master; player seats start at 1 and wrap within available slots
        let playerSeatCount = PlayerSeat.seatPoses.count - 1
        let seatIndex = (localIndex % playerSeatCount) + 1
        // `sortedParticipants` includes the master (there's no way to
        // exclude them specifically — see the doc comment above), so this
        // slightly overcounts the true player count by one. Harmless here:
        // it only feeds the ">" oversubscription check and the logged
        // number, not the seat math itself.
        let playerCount = sortedParticipants.count - 1
        if playerCount > playerSeatCount {
            sharedSeatPlayerCount = playerCount
            Logger.sharePlay.warning(
                "\(playerCount, privacy: .public) players but only \(playerSeatCount, privacy: .public) table seats — seat \(seatIndex, privacy: .public) (and its dice) may be shared with another player"
            )
        } else {
            sharedSeatPlayerCount = nil
        }
        Logger.sharePlay.debug("Assigned seat \(seatIndex, privacy: .public) to player (index \(localIndex, privacy: .public))")
        claimSeatIfNeeded(TableSeatIdentifier(seatIndex), sessionId: groupSession.id)
    }

    @MainActor
    func updateSeatsForParticipantChange(groupSession: GroupSession<RPGActivity>?, isMaster: Bool) {
        guard groupSession != nil else { return }
        Logger.sharePlay.debug("Participants changed — reassigning seats")
        assignSeatsForSharePlay(groupSession: groupSession, isMaster: isMaster)
    }
}

// MARK: - SharePlay Coordination Extension

extension RPGSharePlayController {
    @MainActor
    func setupSeatAssignment(gameTableModel: GameTableModel) {
        let isMaster = gameModel?.gameConfig.isMaster ?? false
        guard let groupSession else {
            Logger.sharePlay.debug("Setting up single-player seating")
            gameTableModel.assignSeatsForSharePlay(groupSession: nil, isMaster: isMaster)
            // No coordinator to race here — see `GameObserver.canAutoClaimSeat`'s own doc.
            gameTableModel.observer.canAutoClaimSeat = true
            return
        }

        Logger.sharePlay.debug("Setting up SharePlay seat assignment (isMaster: \(isMaster, privacy: .public))")
        gameTableModel.assignSeatsForSharePlay(groupSession: groupSession, isMaster: isMaster)
        // The real, coordinated claim above has now been submitted (this method only
        // ever runs after `coordinateWithSession(_:)` has attached — see both call
        // sites' own docs), so `GameObserver`'s fallback re-claim is safe from here on.
        gameTableModel.observer.canAutoClaimSeat = true

        let seatTask = Task { [weak self] in
            for await _ in groupSession.$activeParticipants.values {
                guard let self else { return }
                let isMaster = self.gameModel?.gameConfig.isMaster ?? false
                gameTableModel.updateSeatsForParticipantChange(groupSession: self.groupSession, isMaster: isMaster)
            }
        }
        trackSessionTask(seatTask, key: Self.seatObservationTaskKey)
    }
}

private extension RPGSharePlayController {
    static let seatObservationTaskKey = UUID()
}

#endif
