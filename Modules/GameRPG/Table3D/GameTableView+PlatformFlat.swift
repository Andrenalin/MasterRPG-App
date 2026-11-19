// @copyright André Trettin

#if os(iOS) || os(macOS)
import Combine
import CoreRPG
import MapRPG
import PhotoRPG
import RealityKit
import SwiftUI

/// Camera-based 3D table for iOS and macOS. It intentionally shares the game
/// model and map/pin synchronization with the visionOS table while leaving all
/// TabletopKit session behavior in the visionOS implementation above.
///
/// Each view instance builds and owns its own `GameTableModel` — and so its own RealityKit
/// entities. Reusing one model's entities in a later view (e.g. after a 2D ↔ 3D toggle) moved them
/// between two RealityView scenes whose setup and teardown SwiftUI doesn't order, which
/// intermittently left the table black. A new map doesn't create a new view (see
/// `GameRootViewer.mapView(for:)`), so building fresh only costs a moment on a toggle.
@MainActor
public struct GameTableView: View {
    let root: GameRoot
    private let showsEmbeddedToolbar: Bool

    @State private var game: GameTableModel?
    @State private var accessibilitySubscriptions: [any Cancellable] = []

    public init(root: GameRoot) {
        self.init(root: root, showsEmbeddedToolbar: true)
    }

    init(root: GameRoot, showsEmbeddedToolbar: Bool) {
        self.root = root
        self.showsEmbeddedToolbar = showsEmbeddedToolbar
    }

    public var body: some View {
        Group {
            if let game {
                GameTableRealityContent(
                    root: root,
                    game: game,
                    accessibilitySubscriptions: $accessibilitySubscriptions,
                    showsEmbeddedToolbar: showsEmbeddedToolbar
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.black.gradient)
        .task {
            await initializeGameIfNeeded()
        }
        .task(id: root.mapRoot.gameControllable.gameModel.currentItemId) {
            guard let game else { return }
            await game.handleMapChange(
                isGameMaster: root.gameModel.gameConfig.isMaster
            )
        }
        // The game master's weather, in 3D over the map.
        .modifier(GameTableWeatherSync(root: root, game: game))
        .onDisappear {
            accessibilitySubscriptions.removeAll()
            // A view that replaced this one may already have registered its own model; the
            // identity check leaves that registration alone.
            if let game, root.gameModel.gameTableModel === game {
                root.gameModel.gameTableModel = nil
            }
        }
    }

    private func initializeGameIfNeeded() async {
        if let game {
            // SwiftUI may temporarily disappear without destroying @State.
            // Restore the root registration so network controllers continue
            // driving the still-live table after it appears again.
            root.gameModel.gameTableModel = game
            await game.handleMapChange(
                isGameMaster: root.gameModel.gameConfig.isMaster
            )
            return
        }

        let initializedGame = GameTableModel(
            mapRoot: root.mapRoot,
            photoRoot: root.photoRoot
        )
        await initializedGame.renderer.loadAssets()
        guard !Task.isCancelled else { return }

        initializedGame.configureSession(from: root)
        root.gameModel.gameTableModel = initializedGame
        game = initializedGame

        await initializedGame.handleMapChange(
            isGameMaster: initializedGame.isGameMaster
        )
        guard !Task.isCancelled else { return }
        // The reshare baseline starts at the loaded map's values, as the 2D session's does on
        // appear; the defaults (scale 1, no hex grid) offered a reshare for every map that
        // differed from them. See CODE_AUDIT_19 §5.17.
        initializedGame.resetReshare()
        initializedGame.syncPawnsWithMapPins()
    }
}

@MainActor
private struct GameTableRealityContent: View {
    let root: GameRoot
    let game: GameTableModel
    @Binding var accessibilitySubscriptions: [any Cancellable]
    let showsEmbeddedToolbar: Bool

    /// The running total of table-move translation applied so far this drag (`tableMoveGesture` or
    /// `boardDragGesture`) — `DragGesture.Value.translation` is cumulative from the gesture's start,
    /// not per-frame, so this is what lets `.onChanged` apply only the *new* delta each call. Reset
    /// on `.onEnded`.
    @State private var tableMoveLastTranslation: CGSize = .zero
    /// See `StaleGestureTracker`'s own doc — if `.onEnded` is never delivered,
    /// `tableMoveLastTranslation` would otherwise stay stuck non-zero forever, applying one
    /// large, wrong jump to the table's position on the next unrelated table-move gesture.
    @State private var tableMoveTracker = StaleGestureTracker()
    /// The running total of `tableRotateGesture`'s rotation applied so far — like `DragGesture`'s
    /// translation, `RotateGesture.Value.rotation` is cumulative from the gesture's start. Reset on
    /// `.onEnded`.
    @State private var tableRotateLastAngle: Angle = .zero
    /// Same role as `tableMoveTracker`, for a rotate whose `.onEnded` never arrives.
    @State private var tableRotateTracker = StaleGestureTracker()
    /// Tracks the in-flight room toggle/focus request so a rapid second tap cancels the
    /// first instead of both racing `GameTableModel`'s fog recomposite.
    @State private var roomActionCoordinator = RoomActionCoordinator()
    /// The table view's geometry, which the pin action popover is placed in.
    @State private var viewport = GameTableViewport()
    /// Projects scene positions into this view for the pin action popover.
    @State private var projector = GameTableProjector()

    var body: some View {
        RealityView { content in
            // The 3D scanner can no longer get its camera afterwards. See `RealityViewPresence`.
            RealityViewPresence.noteCreated()
            content.camera = .virtual
            content.add(game.renderer.root)
            content.add(game.renderer.camera)
            content.cameraTarget = game.setup.board.entity
            installAccessibilitySubscriptionsIfNeeded()
            installPinMenuTracking(in: content)
        } update: { content in
            content.camera = .virtual
        }
        // Always on: CameraControls is a fixed set of exclusive presets, not
        // an option set, so there's no way to keep .orbit's bundled pinch-zoom
        // and rotate while dropping only its one-finger-drag component — and
        // reassigning this value resets the camera's current framing back to
        // default. Instead, the chained gesture below wins priority over the
        // drag component for every touch, leaving only pinch-zoom to
        // `.orbit` itself; `tableRotateGesture` adds the two-finger rotate.
        .realityViewCameraControls(.orbit)
        .onGeometryChange(for: GameTableViewport.self) { proxy in
            GameTableViewport(size: proxy.size, safeAreaInsets: proxy.safeAreaInsets)
        } action: { newViewport in
            if viewport.size != newViewport.size {
                game.renderer.updateCamera(for: newViewport.size)
            }
            viewport = newViewport
        }
        // One physical drag, up to three meanings, tried in this order via `.exclusively(before:)`:
        //  1. `pinDragGesture` — a touch starting on a pin moves that pin (entity-targeted, so its
        //     predicate never matches a touch that lands elsewhere, letting the chain fall through).
        //  2. `boardDragGesture` — a touch starting on the map surface or on a room's fog moves the
        //     table. Also entity-targeted; pins sit closer to the camera and win hit-testing first.
        //  3. iOS only: `tableMoveGesture` — anything else (bare wood, empty space) also moves the
        //     table. It is not entity-targeted, so this ordering keeps it from racing #1/#2 for the
        //     same touch. On macOS it is left out so a mouse drag on the background orbits the
        //     camera through `.realityViewCameraControls(.orbit)` instead of being swallowed.
        .highPriorityGesture(dragGestureChain)
        // A pin sitting over a room's fog always wins the tap — pinTapGesture
        // is listed first, and exclusively(before:) gives it precedence; its
        // targetedToEntity predicate simply never matches when the touch
        // lands only on the fog, letting roomTapGesture win instead.
        .simultaneousGesture(pinTapGesture.exclusively(before: roomTapGesture))
        .simultaneousGesture(tableRotateGesture)
        // A character or photo dragged from a list becomes a pin where it is released.
        .dropDestination(for: MapPinDropTransferable.self) { links, point in
            dropPins(links, at: point)
        }
        .overlay(alignment: .topTrailing) {
            if showsEmbeddedToolbar {
                GameTableToolbar(root: root, game: game)
                    .padding()
            }
        }
        // Above the gestures and the toolbar: the popover is drawn in this view's coordinate
        // space, next to the selected pin.
        .overlay(alignment: .topLeading) {
            GamePinActionMenu(game: game, viewport: viewport)
        }
        .overlay(alignment: .topLeading) {
            GamePinPhotoPopover(game: game, viewport: viewport)
        }
        .overlay(alignment: .topLeading) {
            GameMapPhotoPopover(game: game, viewport: viewport)
        }
        .onChange(of: root.mapRoot.photoPopover.photo) {
            game.updateMapPhotoAnchor()
        }
        .onDisappear {
            roomActionCoordinator.cancel()
        }
    }

    #if os(macOS)
    private var dragGestureChain: some Gesture {
        pinDragGesture.exclusively(before: boardDragGesture)
    }
    #else
    private var dragGestureChain: some Gesture {
        pinDragGesture
            .exclusively(before: boardDragGesture)
            .exclusively(before: tableMoveGesture)
    }
    #endif

    private var pinDragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .targetedToEntity(where: .has(PinComponent.self))
            .onChanged { value in
                withPinDragTarget(value) { parent in
                    value.tablePosition(relativeTo: parent)
                } perform: { pinId, position in
                    game.pinDragChanged(pinId: pinId, position: position)
                }
            }
            .onEnded { value in
                withPinDragTarget(value) { parent in
                    value.tablePosition(relativeTo: parent)
                } perform: { pinId, position in
                    game.pinDragEnded(pinId: pinId, position: position)
                }
            }
    }

    /// Dragging the map surface moves the whole table, the same way `tableMoveGesture` does for the
    /// bare wood table/background, so the one-finger drag does the same thing wherever it starts.
    /// Room fog counts as map surface: the game master's room hit volumes sit above the board and
    /// win the hit test, so without them here a drag over any room — most of a typical map — had
    /// no target on macOS, where there is no untargeted `tableMoveGesture` fallback. Room taps and
    /// long presses are unaffected; they fail as soon as the touch moves past this drag's minimum
    /// distance.
    private var boardDragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .targetedToEntity(where: .has(BoardSurfaceComponent.self) || .has(RoomComponent.self))
            .onChanged { value in
                applyTableMoveDelta(translation: value.translation)
            }
            .onEnded { _ in
                tableMoveLastTranslation = .zero
                tableMoveTracker.reset()
            }
    }

    #if !os(macOS)
    /// Repositions the whole table — translating `game.renderer.root`, not `.orbit`'s bundled camera
    /// rotate — for a touch that starts on neither a pin nor the map surface. Unlike the two above
    /// this isn't `.targetedToEntity` (a plain `DragGesture` has no RealityKit ray-casting context),
    /// so it uses a scaled screen-space delta: a freeform "nudge the table into view" convenience,
    /// not a precise placement tool. `content.cameraTarget` keeps the camera aimed at the table as
    /// it moves.
    private var tableMoveGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                applyTableMoveDelta(translation: value.translation)
            }
            .onEnded { _ in
                tableMoveLastTranslation = .zero
                tableMoveTracker.reset()
            }
    }
    #endif

    /// Shared by `tableMoveGesture` and `boardDragGesture` — `translation` is each gesture's own
    /// cumulative-since-start value (`DragGesture.Value` and `EntityTargetValue<DragGesture.Value>`
    /// both expose it as `CGSize`), so only the value itself needs passing.
    private func applyTableMoveDelta(translation: CGSize) {
        if tableMoveTracker.isStale(after: StaleGestureTracker.defaultTimeout) {
            // The previous drag's `.onEnded` was likely never delivered (system interruption,
            // window backgrounding mid-drag) — re-arm from this call's value instead of computing
            // a delta against the stale one.
            tableMoveLastTranslation = translation
        }
        let delta = CGSize(
            width: translation.width - tableMoveLastTranslation.width,
            height: translation.height - tableMoveLastTranslation.height
        )
        tableMoveLastTranslation = translation
        tableMoveTracker.recordUpdate()
        game.renderer.root.position.x += Float(delta.width) * Self.tableMoveScale
        game.renderer.root.position.z += Float(delta.height) * Self.tableMoveScale
    }

    /// Two-finger rotate (a trackpad rotate on macOS) turns the table about its own vertical axis.
    /// Not entity-targeted, so it works wherever it starts — above all on the map, which covers most
    /// of the table: `.orbit` has no two-finger rotate on iOS, and on macOS its mouse-drag orbit only
    /// answers a drag that starts on the bare table. Simultaneous, so `.orbit`'s pinch-zoom still
    /// works in the same two-finger gesture.
    private var tableRotateGesture: some Gesture {
        RotateGesture(minimumAngleDelta: .degrees(1))
            .onChanged { value in
                applyTableRotationDelta(rotation: value.rotation)
            }
            .onEnded { _ in
                tableRotateLastAngle = .zero
                tableRotateTracker.reset()
            }
    }

    private func applyTableRotationDelta(rotation: Angle) {
        if tableRotateTracker.isStale(after: StaleGestureTracker.defaultTimeout) {
            // See `applyTableMoveDelta`: re-arm instead of applying a delta against a lost gesture.
            tableRotateLastAngle = rotation
        }
        let delta = rotation.radians - tableRotateLastAngle.radians
        tableRotateLastAngle = rotation
        tableRotateTracker.recordUpdate()
        // SwiftUI angles grow clockwise on screen; seen from the camera above the table, a clockwise
        // turn is a negative rotation about +Y. The root's origin is the table's center, so the
        // table turns in place wherever it has been moved to.
        let turn = simd_quatf(angle: -Float(delta), axis: SIMD3<Float>(0, 1, 0))
        game.renderer.root.orientation = turn * game.renderer.root.orientation
    }

    /// Meters the table moves per screen point dragged — a hand-tuned feel
    /// (a comfortable drag across a typical viewport repositions the table
    /// by roughly its own size), not a precise 1:1 mapping; see
    /// `tableMoveGesture`'s own doc for why it can't derive an exact one.
    private static let tableMoveScale: Float = 0.001

    /// Double tap opens the pin's photo popover for both roles. Single tap toggles highlight
    /// for a player, but opens/closes the master's local action menu
    /// instead — long press is no longer used for pins.
    private var pinTapGesture: some Gesture {
        TapGesture(count: 2)
            .targetedToEntity(where: .has(PinComponent.self))
            .exclusively(
                before: TapGesture()
                    .targetedToEntity(where: .has(PinComponent.self))
            )
            .onEnded { value in
                switch value {
                case .first(let doubleTap):
                    guard let pinId = doubleTap.entity.components[PinComponent.self]?.pinId else { return }
                    game.pinDoubleTapped(pinId: pinId)
                case .second(let tap):
                    guard let pinId = tap.entity.components[PinComponent.self]?.pinId else { return }
                    game.pinTapped(pinId: pinId)
                }
            }
    }

    /// Long press toggles room focus, double tap toggles room visibility —
    /// mirroring the 2D map's room gestures. No single-tap: an accidental tap
    /// on the fog shouldn't do anything by itself.
    private var roomTapGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.45, maximumDistance: 5)
            .targetedToEntity(where: .has(RoomComponent.self))
            .exclusively(
                before: TapGesture(count: 2)
                    .targetedToEntity(where: .has(RoomComponent.self))
            )
            .onEnded { value in
                switch value {
                case .first(let longPress):
                    guard let roomId = longPress.entity.components[RoomComponent.self]?.roomId else { return }
                    roomActionCoordinator.perform { await game.toggleRoomFocus(roomId) }
                case .second(let doubleTap):
                    guard let roomId = doubleTap.entity.components[RoomComponent.self]?.roomId else { return }
                    roomActionCoordinator.perform { await game.toggleRoomVisibility(roomId) }
                }
            }
    }

    /// Keeps `GameTableModel.popoverSources` on their targets (the selected pin, the photo pin, the map photo). The system's camera controls
    /// orbit and zoom without telling SwiftUI, so the pin is projected again on every rendered
    /// frame; the model publishes only a visible change.
    /// Adds the dropped characters (not their entries) and photos as pins at the drop point: the
    /// view point is cast onto the pin plane, the same way a pin drag finds its position.
    private func dropPins(_ links: [MapPinDropTransferable], at point: CGPoint) -> Bool {
        let items = links
            .filter { $0.module == .photo || ($0.module == .value && $0.entryId == nil) }
            .map { ItemRowModel(itemId: $0.itemId, typeId: $0.module) }
        guard !items.isEmpty,
              let content = projector.content,
              let ray = content.ray(through: point, in: .local, to: game.setup.pinContainer),
              abs(ray.direction.y) > 0.000_001 else { return false }
        let distance = (MapTableProjection.pinHeight - ray.origin.y) / ray.direction.y
        guard distance.isFinite, distance >= 0 else { return false }
        return game.dropPins(items, at: ray.origin + ray.direction * distance)
    }

    private func installPinMenuTracking(in content: RealityViewCameraContent) {
        projector.content = content
        // Captured weakly and directly, so the scene's handler holds neither the model nor
        // this view value, nor the content it renders into.
        _ = content.subscribe(to: SceneEvents.Update.self) { [weak game, weak projector] _ in
            guard let game, let content = projector?.content else { return }
            game.updatePopoverSources { position in
                content.project(point: position, to: .local)
            }
        }
    }

    private func installAccessibilitySubscriptionsIfNeeded() {
        guard accessibilitySubscriptions.isEmpty,
              let scene = game.renderer.root.scene else { return }

        // Captured directly so the event closures don't hold this view value (and, through its
        // binding, the storage that holds these subscriptions).
        let coordinator = roomActionCoordinator
        let game = game
        let activate = scene.subscribe(to: AccessibilityEvents.Activate.self) { event in
            Task { @MainActor in
                if let pinId = event.entity.components[PinComponent.self]?.pinId {
                    game.pinTapped(pinId: pinId)
                } else if let roomId = event.entity.components[RoomComponent.self]?.roomId {
                    coordinator.perform { await game.toggleRoomVisibility(roomId) }
                }
            }
        }
        let zoom = scene.subscribe(to: AccessibilityEvents.CustomAction.self) { event in
            Task { @MainActor in
                if let pinId = event.entity.components[PinComponent.self]?.pinId {
                    game.pinDoubleTapped(pinId: pinId)
                } else if let roomId = event.entity.components[RoomComponent.self]?.roomId {
                    coordinator.perform { await game.toggleRoomFocus(roomId) }
                }
            }
        }
        accessibilitySubscriptions = [activate, zoom]
    }
}

/// Holds the reality view's content for the pin action popover's projection. Owned by the view's
/// state, so a scene event handler can reach the content without keeping it alive.
@MainActor
private final class GameTableProjector {
    var content: RealityViewCameraContent?
}

private extension EntityTargetValue where Value == DragGesture.Value {
    @MainActor
    func tablePosition(relativeTo parent: Entity) -> SIMD3<Float>? {
        guard let ray = ray(
            through: self.location,
            in: .local,
            to: parent
        ), abs(ray.direction.y) > 0.000_001 else { return nil }

        let distance = (MapTableProjection.pinHeight - ray.origin.y) / ray.direction.y
        guard distance.isFinite, distance >= 0 else { return nil }
        return ray.origin + ray.direction * distance
    }
}

#Preview("3D Table") {
    GameTableView(root: .preview)
}

/// A table with one selected pin, without a map: enough for the pin action popover to appear.
private struct GameTablePinActionsPreview: View {
    @State private var game = makeGame()
    @State private var accessibilitySubscriptions: [any Cancellable] = []

    var body: some View {
        GameTableRealityContent(
            root: .preview,
            game: game,
            accessibilitySubscriptions: $accessibilitySubscriptions,
            showsEmbeddedToolbar: false
        )
        .background(.black.gradient)
        .task {
            await game.renderer.loadAssets()
        }
    }

    private static func makeGame() -> GameTableModel {
        let game = GameTableModel(mapRoot: .preview, photoRoot: .preview)
        let pin = MapPinModel(id: UUID(), name: "Goblin Guard", color: .red, location: .zero)
        let pawn = PinPawn(pin: pin, pointsToMeters: MapTableProjection.fallbackPointsToMeters)
        pawn.update(
            pin: pin,
            position: SIMD3<Float>(0.2, MapTableProjection.pinHeight, -0.1),
            hiddenForMaster: false,
            pointsToMeters: MapTableProjection.fallbackPointsToMeters
        )
        game.setup.pinContainer.addChild(pawn.entity)
        game.setup.pinPawns.append(pawn)
        game.isGameMaster = true
        game.selectedPinId = pin.id
        game.selectedPin = pin
        return game
    }
}

#Preview("3D Table pin actions") {
    GameTablePinActionsPreview()
        .frame(width: 800, height: 600)
}
#endif
