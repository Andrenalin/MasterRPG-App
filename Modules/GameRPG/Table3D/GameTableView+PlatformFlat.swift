// @copyright André Trettin

#if os(iOS) || os(macOS)
import Combine
import CoreRPG
import MapRPG
import RealityKit
import SwiftUI

/// Camera-based 3D table for iOS and macOS. It intentionally shares the game
/// model and map/pin synchronization with the visionOS table while leaving all
/// TabletopKit session behavior in the visionOS implementation above.
@MainActor
public struct GameTableView: View {
    let root: GameRoot
    private let retentionModel: GameScreenModel?
    private let showsEmbeddedToolbar: Bool

    @State private var game: GameTableModel?
    @State private var accessibilitySubscriptions: [any Cancellable] = []

    public init(root: GameRoot) {
        self.root = root
        retentionModel = nil
        showsEmbeddedToolbar = true
    }

    init(root: GameRoot, retentionModel: GameScreenModel?) {
        self.root = root
        self.retentionModel = retentionModel
        showsEmbeddedToolbar = false
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
        .onDisappear {
            accessibilitySubscriptions.removeAll()
            retentionModel?.retainedGameTableModel = game
            if root.gameModel.gameTableModel === game {
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

        if let retainedGame = retentionModel?.retainedGameTableModel {
            retainedGame.networkActions = root.networkActions
            retainedGame.isGameMaster = root.gameModel.gameConfig.isMaster
            retainedGame.playerPinId = retainedGame.isGameMaster
                ? nil
                : root.gameModel.gameConfig.id
            game = retainedGame
            root.gameModel.gameTableModel = retainedGame
            await retainedGame.handleMapChange(
                isGameMaster: retainedGame.isGameMaster
            )
            return
        }

        let initializedGame = GameTableModel(
            mapRoot: root.mapRoot,
            photoRoot: root.photoRoot
        )
        await initializedGame.renderer.loadAssets()
        guard !Task.isCancelled else { return }

        initializedGame.networkActions = root.networkActions
        initializedGame.isGameMaster = root.gameModel.gameConfig.isMaster
        initializedGame.playerPinId = initializedGame.isGameMaster
            ? nil
            : root.gameModel.gameConfig.id
        root.gameModel.gameTableModel = initializedGame
        game = initializedGame

        await initializedGame.handleMapChange(
            isGameMaster: initializedGame.isGameMaster
        )
        guard !Task.isCancelled else { return }
        initializedGame.syncPawnsWithMapPins()
    }
}

/// Explicit name for callers that want to distinguish the camera-based table
/// from the volumetric visionOS TabletopKit view.
public typealias GameTableRealityView = GameTableView

@MainActor
private struct GameTableRealityContent: View {
    let root: GameRoot
    let game: GameTableModel
    @Binding var accessibilitySubscriptions: [any Cancellable]
    let showsEmbeddedToolbar: Bool

    /// Captured on `boardDragGesture`'s first `.onChanged` call (when it's
    /// panning, not moving the table), cleared on `.onEnded` — the pan
    /// commits once, in a single step, rather than re-rendering the board
    /// texture on every touch-move event.
    @State private var viewportPanStart: SIMD3<Float>?
    /// See `StaleGestureTracker`'s own doc — if `.onEnded` is never delivered (system
    /// interruption, window backgrounding mid-drag), `viewportPanStart` would otherwise stay
    /// stuck non-nil forever, wedging every future pan against a stale start position.
    @State private var viewportPanTracker = StaleGestureTracker()
    /// The focused room captured when the in-flight pan started — `panViewport` discards the
    /// commit if this no longer matches the current focus by the time `.onEnded` fires. See
    /// CODE_AUDIT §5.12.
    @State private var viewportPanRoomId: UUID?
    /// The running total of table-move translation applied so far this drag (`tableMoveGesture`,
    /// or `boardDragGesture` when it's moving the table rather than panning) — `DragGesture.Value.translation`
    /// is cumulative from the gesture's start, not per-frame, so this is what lets `.onChanged`
    /// apply only the *new* delta each call. Reset on `.onEnded`.
    @State private var tableMoveLastTranslation: CGSize = .zero
    /// See `StaleGestureTracker`'s own doc — if `.onEnded` is never delivered,
    /// `tableMoveLastTranslation` would otherwise stay stuck non-zero forever, applying one
    /// large, wrong jump to the table's position on the next unrelated table-move gesture. See
    /// CODE_AUDIT §5.1.
    @State private var tableMoveTracker = StaleGestureTracker()
    /// `nil` at rest; decided once per `boardDragGesture`, on its first
    /// `.onChanged` call, from whether a room was focused *then* — not
    /// re-checked on every subsequent call, so a focus change arriving
    /// mid-drag (e.g. a synced update from another participant) can't swap
    /// behavior out from under the user's finger. `true` = panning the
    /// viewport crop; `false` = moving the table.
    @State private var boardDragPansViewport: Bool?
    /// Tracks the in-flight room toggle/focus request so a rapid second tap cancels the
    /// first instead of both racing `GameTableModel`'s fog recomposite. See CODE_AUDIT §5.5.
    @State private var roomActionCoordinator = RoomActionCoordinator()

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            content.add(game.renderer.root)
            content.add(game.renderer.camera)
            content.cameraTarget = game.setup.board.entity
            installAccessibilitySubscriptionsIfNeeded()
        } update: { content in
            content.camera = .virtual
        }
        // Always on: CameraControls is a fixed set of exclusive presets, not
        // an option set, so there's no way to keep .orbit's bundled pinch-zoom
        // and rotate while dropping only its one-finger-drag component — and
        // reassigning this value resets the camera's current framing back to
        // default. Instead, the chained gesture below wins priority over the
        // drag component for every touch, leaving only pinch-zoom/rotate to
        // `.orbit` itself.
        .realityViewCameraControls(.orbit)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            game.renderer.updateCamera(for: size)
        }
        // One physical one-finger drag, three possible meanings, tried in
        // this exact order via `.exclusively(before:)` — mirrors
        // `pinTapGesture.exclusively(before: roomTapGesture)` below, just
        // for drags instead of taps:
        //  1. `pinDragGesture` — a touch starting on a pin moves that pin.
        //     Entity-targeted, so its predicate simply never matches a
        //     touch that lands elsewhere, letting the chain fall through.
        //  2. `boardDragGesture` — a touch starting on the map surface
        //     either pans a focused room's zoomed viewport crop, or moves
        //     the table (see its own doc for which, and why). Also
        //     entity-targeted, so it's naturally disjoint from #1: pins and
        //     room fog sit closer to the camera and win hit-testing first,
        //     as `RoomHitArea`'s only other caller already relies on — a
        //     room's own tap gestures below are a *separate*, tap-only
        //     gesture chain on `RoomComponent` itself, so this never
        //     touches those either.
        //  3. `tableMoveGesture` — anything else (the bare wood table, or
        //     empty space) moves the whole table instead of orbiting the
        //     camera around it. Unlike #1/#2 this one is *not*
        //     entity-targeted (a plain `DragGesture` matches any touch), so
        //     without this ordering it would race #1/#2 for the exact same
        //     touch instead of only catching what they don't.
        .highPriorityGesture(
            pinDragGesture
                .exclusively(before: boardDragGesture)
                .exclusively(before: tableMoveGesture)
        )
        // A pin sitting over a room's fog always wins the tap — pinTapGesture
        // is listed first, and exclusively(before:) gives it precedence; its
        // targetedToEntity predicate simply never matches when the touch
        // lands only on the fog, letting roomTapGesture win instead.
        .simultaneousGesture(pinTapGesture.exclusively(before: roomTapGesture))
        .overlay(alignment: .topTrailing) {
            if showsEmbeddedToolbar {
                GameTableToolbar(root: root, game: game)
                    .padding()
            }
        }
        .overlay(alignment: .bottom) {
            GamePinActionMenu(game: game)
                .padding()
        }
        .onDisappear {
            roomActionCoordinator.cancel()
        }
    }

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

    /// Dragging the map surface either pans a focused room's zoomed
    /// viewport crop — see `GameTableModel.panViewport(fromTableStart:toTableEnd:)` —
    /// or, when no room is focused, moves the whole table instead, the
    /// same way `tableMoveGesture` does for the bare wood table/background.
    /// The pan is otherwise a no-op in that state today
    /// (`GameTableModel.panViewport(by:)` guards on `focusedRoomId`), so
    /// this fills what would otherwise be dead space for the same
    /// one-finger drag rather than leaving the table reachable only
    /// outside the map. Which mode applies is decided once and held in
    /// `boardDragPansViewport` — see its own doc for why.
    private var boardDragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .targetedToEntity(where: .has(BoardSurfaceComponent.self))
            .onChanged { value in
                let pansViewport = boardDragPansViewport ?? (game.focusedRoomId != nil)
                boardDragPansViewport = pansViewport

                if pansViewport {
                    guard let position = value.tablePosition(relativeTo: game.renderer.root) else { return }
                    if viewportPanStart == nil || viewportPanTracker.isStale(after: RoomActionCoordinator.staleGestureTimeout) {
                        viewportPanStart = position
                        viewportPanRoomId = game.focusedRoomId
                    }
                    viewportPanTracker.recordUpdate()
                } else {
                    applyTableMoveDelta(translation: value.translation)
                }
            }
            .onEnded { value in
                defer { boardDragPansViewport = nil }
                if boardDragPansViewport == true {
                    defer { viewportPanStart = nil; viewportPanTracker.reset(); viewportPanRoomId = nil }
                    guard let start = viewportPanStart,
                          let end = value.tablePosition(relativeTo: game.renderer.root) else { return }
                    game.panViewport(fromTableStart: start, toTableEnd: end, expectedRoomId: viewportPanRoomId)
                } else {
                    tableMoveLastTranslation = .zero
                    tableMoveTracker.reset()
                }
            }
    }

    /// Repositions the whole table — translating `game.renderer.root`, not
    /// `.orbit`'s bundled camera rotate — for a touch that starts on
    /// neither a pin nor the map surface; see the priority chain's own
    /// comment at this gesture's `.highPriorityGesture` call site for why
    /// `pinDragGesture`/`boardDragGesture` have to come first.
    ///
    /// Unlike those two, this isn't `.targetedToEntity` — a plain
    /// `DragGesture` has no RealityKit ray-casting context, so this uses a
    /// scaled screen-space delta (`applyTableMoveDelta(translation:)`)
    /// instead of the exact table-plane ray-cast
    /// `EntityTargetValue.tablePosition(relativeTo:)` gives the other two;
    /// it's a freeform "nudge the table into view" convenience, not a
    /// precise placement tool. `content.cameraTarget` (set to
    /// `game.setup.board.entity`, itself parented under
    /// `game.renderer.root`) keeps the camera aimed at the table as it
    /// moves, for free.
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

    /// Shared by `tableMoveGesture` and `boardDragGesture` (when the latter
    /// is moving the table rather than panning) — `translation` is each
    /// gesture's own cumulative-since-start value, whatever its concrete
    /// type (`DragGesture.Value` or `EntityTargetValue<DragGesture.Value>`
    /// both expose it as `CGSize`), so only the value itself needs passing.
    private func applyTableMoveDelta(translation: CGSize) {
        if tableMoveTracker.isStale(after: RoomActionCoordinator.staleGestureTimeout) {
            // The previous drag's `.onEnded` was likely never delivered (system
            // interruption, window backgrounding mid-drag) — re-arm from this call's
            // value instead of computing a delta against the stale one, mirroring
            // `viewportPanStart`/`StaleGestureTracker`. See CODE_AUDIT §5.1.
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

    /// Meters the table moves per screen point dragged — a hand-tuned feel
    /// (a comfortable drag across a typical viewport repositions the table
    /// by roughly its own size), not a precise 1:1 mapping; see
    /// `tableMoveGesture`'s own doc for why it can't derive an exact one.
    private static let tableMoveScale: Float = 0.001

    /// Double tap toggles zoom for both roles. Single tap toggles highlight
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

    private func installAccessibilitySubscriptionsIfNeeded() {
        guard accessibilitySubscriptions.isEmpty,
              let scene = game.renderer.root.scene else { return }

        let activate = scene.subscribe(to: AccessibilityEvents.Activate.self) { event in
            Task { @MainActor in
                if let pinId = event.entity.components[PinComponent.self]?.pinId {
                    game.pinTapped(pinId: pinId)
                } else if let roomId = event.entity.components[RoomComponent.self]?.roomId {
                    roomActionCoordinator.perform { await game.toggleRoomVisibility(roomId) }
                }
            }
        }
        let zoom = scene.subscribe(to: AccessibilityEvents.CustomAction.self) { event in
            Task { @MainActor in
                if let pinId = event.entity.components[PinComponent.self]?.pinId {
                    game.pinDoubleTapped(pinId: pinId)
                } else if let roomId = event.entity.components[RoomComponent.self]?.roomId {
                    roomActionCoordinator.perform { await game.toggleRoomFocus(roomId) }
                }
            }
        }
        accessibilitySubscriptions = [activate, zoom]
    }
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
#endif
