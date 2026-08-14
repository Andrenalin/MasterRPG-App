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
    var shape: TabletopShape = .rectangular(
        width: GameMetrics.tableEdge,
        height: GameMetrics.tableEdge,
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
    private let mapSize: Float
    
    init() {
        self.mapSize = MapTableProjection.mapSize
        let boardEntity = Entity()
        boardEntity.name = "MapSurface"

        let plane = ModelEntity(
            mesh: .generatePlane(width: mapSize, depth: mapSize),
            materials: [SimpleMaterial(color: .white, isMetallic: false)]
        )
        // The map surface shares the bottom-origin coordinate space used by
        // the generated wood mesh and the synchronized pin container.
        plane.position.y = GameMetrics.tableThickness + GameMetrics.mapSurfaceClearance
        plane.name = "MapImagePlane"
        plane.isEnabled = false
        boardEntity.addChild(plane)
        self.imagePlane = plane
        
        self.entity = boardEntity
    }
        
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
        
        if aspectRatio > 1.0 {
            // Landscape - width constrained
            planeWidth = mapSize
            planeDepth = mapSize / Float(aspectRatio)
        } else {
            // Portrait or square - height constrained
            planeDepth = mapSize
            planeWidth = mapSize * Float(aspectRatio)
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

        // The crop to zoom the composited image+fog to — the full map by
        // default, or a room-centered crop when a room is focused. `canvasSize`
        // doubles as both the entries' coordinate space and the output frame
        // here (unlike the iOS/macOS renderer, which keeps them separate), so
        // the crop needs no unit conversion before use below.
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

    /* There are three seats around the edges of the table.
    Each seat faces the center of the table. */
    @MainActor static let seatPoses: [TableVisualState.Pose2D] = [
        .init(position: .init(x: 0, z: Double(GameMetrics.tableEdge)), rotation: .degrees(0)),
        .init(position: .init(x: -Double(GameMetrics.tableEdge), z: 0), rotation: .degrees(-90)),
        .init(position: .init(x: Double(GameMetrics.tableEdge), z: 0), rotation: .degrees(90))
    ]
    
    init(id: TableSeatIdentifier, pose: TableVisualState.Pose2D) {
        self.id = id
        let spatialSeatPose: TableVisualState.Pose2D = .init(position: pose.position,
                                                             rotation: pose.rotation)
        initialState = .init(pose: spatialSeatPose)
    }

    /// Two table-plane positions in the given seat's own player area, side by
    /// side — for that seat's own dice. Placed at `playerAreaDistanceFromCenter`
    /// (an existing, already-correct constant for this exact purpose — see
    /// `GameMetrics`, previously declared but unused) *from the table center*,
    /// along the same angular direction as the seat, rather than inset from
    /// the seat's own position: the table (`GameMetrics.tableEdge`, a full
    /// width/depth, not a radius) is only 0.7 m across, so seats — placed at
    /// a full `tableEdge` from center — already sit well *beyond* its physical
    /// edge, the way a chair sits beyond a real table's edge. Insetting from
    /// the seat by a small amount (the previous approach) still landed
    /// outside the table surface, off in empty space.
    @MainActor
    static func diceLayout(inFrontOf seatPose: TableVisualState.Pose2D) -> [TableVisualState.Pose2D] {
        let seatPosition = seatPose.position
        let distance = (seatPosition.x * seatPosition.x + seatPosition.z * seatPosition.z).squareRoot()
        let direction: (x: Double, z: Double) = distance > 0.0001
            ? (x: seatPosition.x / distance, z: seatPosition.z / distance)
            : (x: 0, z: 1)
        // Perpendicular to `direction`, to spread the two dice apart.
        let lateral: (x: Double, z: Double) = (x: -direction.z, z: direction.x)
        let radius = Double(GameMetrics.playerAreaDistanceFromCenter)
        let lateralSpacing = 0.07

        return [-lateralSpacing, lateralSpacing].map { offset in
            TableVisualState.Pose2D(
                position: .init(
                    x: direction.x * radius + lateral.x * offset,
                    z: direction.z * radius + lateral.z * offset
                ),
                rotation: .zero
            )
        }
    }
}

// MARK: - Pin Pawn

/// Identifies a pin token entity for gesture targeting.
struct PinComponent: Component {
    let pinId: UUID
}

/// Identifies a room's fog hit-test volume for gesture targeting.
struct RoomComponent: Component {
    let roomId: UUID
}

/// A map pin token on the 3D table (player or monster), synced with the pins
/// of the current map. Lives as a plain RealityKit entity parented to
/// `GameSetup.pinContainer` — TabletopKit only snapshots TableSetup at init
/// time, so dynamic EntityEquipment additions would never appear. Pins are
/// deliberately NOT TabletopKit equipment: `mapState` is their single source
/// of truth, TabletopKit pose sync would fight it.
@MainActor
final class PinPawn {
    let pinId: UUID
    let entity: Entity
    private let baseModel: ModelEntity
    private let photoPlane: ModelEntity
    private let highlightModel: ModelEntity
    private let deathMarkModels: [ModelEntity]
    var loadedPhotoId: UUID?
    private var currentSize: MapPinModel.MapPinSize
    private var currentPointsToMeters: Float

    init(pin: MapPinModel, pointsToMeters: Float) {
        pinId = pin.id
        currentSize = pin.size
        currentPointsToMeters = pointsToMeters
        let radius = Self.radius(for: pin.size, pointsToMeters: pointsToMeters)
        let diameter = radius * 1.8

        var baseMaterial = UnlitMaterial()
        baseMaterial.color = .init(tint: UIColor(pin.color))
        baseModel = ModelEntity(mesh: .generateCylinder(height: 0.005, radius: radius), materials: [baseMaterial])
        baseModel.name = "PinBase"

        var highlightMaterial = UnlitMaterial()
        highlightMaterial.color = .init(tint: .systemRed)
        let highlight = ModelEntity(
            mesh: .generateCylinder(height: 0.001, radius: radius * 1.18),
            materials: [highlightMaterial]
        )
        highlight.name = "PinHighlightRing"
        highlight.position.y = -0.002
        highlight.isEnabled = false
        highlightModel = highlight

        var photoMaterial = UnlitMaterial()
        photoMaterial.color = .init(tint: UIColor(pin.color))
        photoPlane = ModelEntity(mesh: .generatePlane(width: diameter, depth: diameter, cornerRadius: diameter / 2), materials: [photoMaterial])
        photoPlane.name = "PinPhotoPlane"
        photoPlane.position.y = 0.004

        var deathMaterial = UnlitMaterial()
        deathMaterial.color = .init(tint: .white)
        let deathBarLength = diameter * 0.72
        let deathBarThickness = max(diameter * 0.10, 0.0015)
        let firstDeathBar = ModelEntity(
            mesh: .generateBox(width: deathBarLength, height: 0.001, depth: deathBarThickness),
            materials: [deathMaterial]
        )
        firstDeathBar.name = "PinDeathMarkFirstBar"
        firstDeathBar.position.y = 0.006
        firstDeathBar.orientation = simd_quatf(angle: .pi / 4, axis: SIMD3<Float>(0, 1, 0))
        firstDeathBar.isEnabled = false

        let secondDeathBar = ModelEntity(
            mesh: .generateBox(width: deathBarLength, height: 0.001, depth: deathBarThickness),
            materials: [deathMaterial]
        )
        secondDeathBar.name = "PinDeathMarkSecondBar"
        secondDeathBar.position.y = 0.006
        secondDeathBar.orientation = simd_quatf(angle: -.pi / 4, axis: SIMD3<Float>(0, 1, 0))
        secondDeathBar.isEnabled = false
        deathMarkModels = [firstDeathBar, secondDeathBar]

        let pinEntity = Entity()
        pinEntity.name = "Pin-\(pin.name)"
        pinEntity.addChild(highlight)
        pinEntity.addChild(baseModel)
        pinEntity.addChild(photoPlane)
        pinEntity.addChild(firstDeathBar)
        pinEntity.addChild(secondDeathBar)
        pinEntity.components.set(PinComponent(pinId: pin.id))
        pinEntity.components.set(InputTargetComponent())
        pinEntity.components.set(CollisionComponent(shapes: [.generateBox(width: diameter, height: 0.02, depth: diameter)]))
        pinEntity.components.set(HoverEffectComponent())
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource("Map pin \(pin.name)", bundle: .module)
        accessibility.value = Self.accessibilityValue(for: pin)
        accessibility.systemActions = .activate
        accessibility.customActions = [LocalizedStringResource("Toggle Pin Zoom", bundle: .module)]
        pinEntity.components.set(accessibility)
        entity = pinEntity
    }

    /// Matches the 2D map's `pin.size.size × pinScale` sizing, projected from
    /// image points into table meters via `pointsToMeters` (see
    /// `MapTableProjection.metersPerPoint`) so a token covers the same
    /// fraction of the table that its pin covers of the map image.
    static func radius(for size: MapPinModel.MapPinSize, pointsToMeters: Float) -> Float {
        Float(size.size.width) * pointsToMeters / 2
    }

    /// Applies pin state without recreating the entity. A battle attacker uses
    /// a blue ring while selected defenders retain the standard red ring.
    func update(
        pin: MapPinModel,
        position: SIMD3<Float>,
        hiddenForMaster: Bool,
        activeAttackerPinId: UUID? = nil,
        pointsToMeters: Float
    ) {
        entity.position = position
        entity.scale = SIMD3<Float>(repeating: pin.isZoom ? 4.0 : 1.0)
        if pin.size != currentSize || pointsToMeters != currentPointsToMeters {
            currentSize = pin.size
            currentPointsToMeters = pointsToMeters
            applySize(pin.size, pointsToMeters: pointsToMeters)
        }
        var baseMaterial = UnlitMaterial()
        baseMaterial.color = .init(tint: pin.isDead ? .black : UIColor(pin.color))
        baseModel.model?.materials = [baseMaterial]
        let isActiveAttacker = pin.id == activeAttackerPinId
        var highlightMaterial = UnlitMaterial()
        highlightMaterial.color = .init(tint: isActiveAttacker ? .systemBlue : .systemRed)
        highlightModel.model?.materials = [highlightMaterial]
        highlightModel.isEnabled = pin.isHighlighted || isActiveAttacker
        deathMarkModels.forEach { $0.isEnabled = pin.isDead }
        if hiddenForMaster {
            entity.components.set(OpacityComponent(opacity: 0.5))
        } else {
            entity.components.remove(OpacityComponent.self)
        }
        updateAccessibility(for: pin)
    }

    /// Puts the pin's photo (thumbnail) onto the token face.
    func setPhotoTexture(_ image: AKImage) {
        guard let cgImage = image.cgImage,
              let texture = try? TextureResource(image: cgImage, options: .init(semantic: .color)) else { return }
        var material = UnlitMaterial()
        material.color = .init(texture: .init(texture))
        photoPlane.model?.materials = [material]
    }

    private func applySize(_ size: MapPinModel.MapPinSize, pointsToMeters: Float) {
        let radius = Self.radius(for: size, pointsToMeters: pointsToMeters)
        let diameter = radius * 1.8
        baseModel.model?.mesh = .generateCylinder(height: 0.005, radius: radius)
        highlightModel.model?.mesh = .generateCylinder(height: 0.001, radius: radius * 1.18)
        photoPlane.model?.mesh = .generatePlane(width: diameter, depth: diameter, cornerRadius: diameter / 2)
        let deathBarLength = diameter * 0.72
        let deathBarThickness = max(diameter * 0.10, 0.0015)
        deathMarkModels.forEach {
            $0.model?.mesh = .generateBox(width: deathBarLength, height: 0.001, depth: deathBarThickness)
        }
        entity.components.set(CollisionComponent(shapes: [.generateBox(width: diameter, height: 0.02, depth: diameter)]))
    }

    private func updateAccessibility(for pin: MapPinModel) {
        guard var accessibility = entity.components[AccessibilityComponent.self] else { return }
        accessibility.label = LocalizedStringResource("Map pin \(pin.name)", bundle: .module)
        accessibility.value = Self.accessibilityValue(for: pin)
        entity.components.set(accessibility)
    }

    private static func accessibilityValue(for pin: MapPinModel) -> LocalizedStringResource {
        switch (pin.isShown, pin.isDead, pin.isHighlighted) {
        case (true, false, false): LocalizedStringResource("Visible, Alive, Not Highlighted", bundle: .module)
        case (true, false, true): LocalizedStringResource("Visible, Alive, Highlighted", bundle: .module)
        case (true, true, false): LocalizedStringResource("Visible, Dead, Not Highlighted", bundle: .module)
        case (true, true, true): LocalizedStringResource("Visible, Dead, Highlighted", bundle: .module)
        case (false, false, false): LocalizedStringResource("Hidden, Alive, Not Highlighted", bundle: .module)
        case (false, false, true): LocalizedStringResource("Hidden, Alive, Highlighted", bundle: .module)
        case (false, true, false): LocalizedStringResource("Hidden, Dead, Not Highlighted", bundle: .module)
        case (false, true, true): LocalizedStringResource("Hidden, Dead, Highlighted", bundle: .module)
        }
    }
}

// MARK: - Room Hit Area

/// An invisible hit-test volume matching a room's fog outline, so the fog
/// covering it can be tapped directly on the table instead of only through
/// the room menu. The map's composite board texture still draws the visible
/// fog — this entity exists purely so `RoomComponent`-targeted gestures have
/// something to hit. Lives in `GameSetup.roomHitContainer`, parallel to how
/// `PinPawn` lives in `pinContainer`.
@MainActor
final class RoomHitArea {
    let roomId: UUID
    let entity: Entity

    init(entry: MapEntryModel, projection: MapTableProjection) {
        roomId = entry.id
        let hitEntity = Entity()
        hitEntity.name = "RoomHitArea-\(entry.name)"
        hitEntity.components.set(RoomComponent(roomId: entry.id))
        hitEntity.components.set(InputTargetComponent())
        hitEntity.components.set(HoverEffectComponent())
        hitEntity.components.set(Self.collision(for: entry.coordinates, projection: projection))
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource("Room \(entry.name)", bundle: .module)
        accessibility.systemActions = .activate
        accessibility.customActions = [LocalizedStringResource("Toggle Room Focus", bundle: .module)]
        hitEntity.components.set(accessibility)
        entity = hitEntity
    }

    /// Always rebuilds: besides the room's own outline changing, the
    /// projection itself changes whenever a *different* room becomes focused
    /// (or focus clears) — same coordinates, different crop — so the
    /// `entry.coordinates` comparison alone can't gate this.
    func update(entry: MapEntryModel, projection: MapTableProjection) {
        entity.components.set(Self.collision(for: entry.coordinates, projection: projection))
    }

    /// A thin convex volume enclosing the room polygon, projected onto the
    /// table plane. Concave outlines are approximated by their convex hull —
    /// fine for a fog-reveal hit target, unlike a physics collider.
    private static func collision(for coordinates: [CGPoint], projection: MapTableProjection) -> CollisionComponent {
        guard coordinates.count >= 3 else {
            return CollisionComponent(shapes: [])
        }
        let halfThickness: Float = 0.004
        let points = coordinates.flatMap { point -> [SIMD3<Float>] in
            let base = projection.tablePosition(for: point)
            return [
                SIMD3<Float>(base.x, base.y - halfThickness, base.z),
                SIMD3<Float>(base.x, base.y + halfThickness, base.z)
            ]
        }
        return CollisionComponent(shapes: [.generateConvex(from: points)])
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
    init(id: ID, pose: TableVisualState.Pose2D, seatControl: ControllingSeats = .any) {
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
        representation = .icosahedron(height: entity.visualBounds(relativeTo: nil).extents.x)
            //.dodecahedron(height: entity.visualBounds(relativeTo: nil).extents.x)
        initialState = .init(value: 1, parentID: .tableID, seatControl: seatControl, pose: pose, entity: self.entity)
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
    init(id: ID, pose: TableVisualState.Pose2D, seatControl: ControllingSeats = .any) {
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
        initialState = .init(value: 1, parentID: .tableID, seatControl: seatControl, pose: pose, entity: self.entity)
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
    /// seats (currently 2 — see the diagram atop `GameSetup`: the table's
    /// 4th side is reserved for the shared die/deck, not a seat). A party of
    /// 3+ players therefore always has multiple players share a seat — and
    /// with it, the seat's 2 `Die20` equipment ids from
    /// `GameSetup.playerDiceIds`, so a character-sheet roll from one of
    /// those players moves the dice the other(s) also treat as their own.
    /// This can't be eliminated purely by reindexing (there are only 2
    /// buckets for 3+ players), but it's now deterministic — every device
    /// computes the same sorted `activeParticipants` list — and surfaced via
    /// `sharedSeatPlayerCount` and a log instead of being silent. See
    /// CODE_AUDIT §5.2.
    @MainActor
    func assignSeatsForSharePlay(groupSession: GroupSession<RPGActivity>?, isMaster: Bool) {
        guard let groupSession else {
            Logger.sharePlay.debug("No active GroupSession — claiming any seat for single player")
            sharedSeatPlayerCount = nil
            tabletopGame.claimAnySeat()
            return
        }

        Logger.sharePlay.debug("SharePlay seat assignment for \(groupSession.activeParticipants.count, privacy: .public) participants (isMaster: \(isMaster, privacy: .public))")

        if isMaster {
            tabletopGame.claimSeat(matching: TableSeatIdentifier(0))
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
        tabletopGame.claimSeat(matching: TableSeatIdentifier(seatIndex))
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
            return
        }

        Logger.sharePlay.debug("Setting up SharePlay seat assignment (isMaster: \(isMaster, privacy: .public))")
        gameTableModel.assignSeatsForSharePlay(groupSession: groupSession, isMaster: isMaster)

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
