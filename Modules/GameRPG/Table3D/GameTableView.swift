// @copyright André Trettin

#if os(visionOS)
import Combine
import CoreRPG
import DiceRPG
import Foundation
import GroupActivities
import MapRPG
import RealityKit
import SpaceRPG
import SwiftUI
import TabletopKit

extension GameTableView {
    /// How far back from the volumetric window's front (near-viewer, +Z)
    /// face the table sits — feeds `GameRenderer.rootOffset`'s placement
    /// math (see that property's own doc). Tightened from an earlier 0.5 m
    /// held purely for viewer comfort (so the table wouldn't land right at
    /// the volume's near clipping bound when the window opens), which also
    /// left the window's system grab handle and this view's own
    /// `.bottomLeadingFront`/`.bottomTrailingFront` ornaments — both
    /// anchored to that same front face — sitting a visible ~0.5 m off the
    /// table's actual edge. 1 cm (matching `sideClearance`), 5 cm, and 10 cm
    /// all still clipped on-device — not the table mesh itself (a plain,
    /// bounding-box-exact box, see `TableAssetFactory.makePlainWoodTable()`),
    /// but the master (South) seat's own tossed dice: `PlayerSeat.diceLayout`
    /// already rests them only ~6 cm inside the table's own front edge
    /// (`GameMetrics.diceEdgeInset`), and a toss's physics carries them
    /// further forward, transiently, before they settle — with less than
    /// 15 cm of margin that overshoot clipped straight through the volume's
    /// front bound and made the die vanish mid-toss. Confirmed working
    /// on-device at 15 cm; don't retighten this without re-testing an actual
    /// dice toss (a static screenshot of the table at rest won't show the
    /// problem). Declared here, not in `GameRenderer` itself, so it shares
    /// one definition with `volumeSize` below instead of two files each
    /// hardcoding the same literal. `public` — read from `WindowVisionList`,
    /// in the app target rather than this module.
    public static let frontClearance: Double = 0.15
    /// Clearance left on each side (X) of the table's own footprint —
    /// deliberately tight (not `backClearance`'s 0.15 m) so the leading/
    /// trailing window handle and this view's own `.bottomLeadingFront`/
    /// `.bottomTrailingFront` ornaments sit right at the table's edge
    /// instead of the ~0.3 m gap the old `tableLength`-derived width left.
    /// `TableScaleGestureController.maxScale` is tuned against this same
    /// 1 cm budget — see its own doc before widening this back out.
    static let sideClearance: Double = 0.01
    /// Clearance left beyond the table's own footprint at the volume's back
    /// (far, −Z) edge — mirrors the ~0.15 m the original 0.7 m square table
    /// used, carried forward unchanged since. Not tightened alongside
    /// `sideClearance`/`frontClearance`: nothing is anchored to the back
    /// edge the way the handle/ornaments are to the sides and front.
    static let backClearance: Double = 0.15
    /// Fixed height (m) of the volumetric window — headroom for a tossed
    /// die's return-to-place arc (see `GameRenderer.placeTable(bottomY:)`),
    /// not derived from the table's own ~0.03 m thickness. An earlier 0.3 m
    /// value was tall enough for the static table but clipped a tossed
    /// die's upward arc through the volume's ceiling mid-animation.
    static let volumeHeight: Double = 1.5

    /// Fixed size (in meters) of the volumetric window this table renders
    /// inside — the single source of truth for `WindowVisionList`'s
    /// `.defaultSize(...)` (which is also what determines where the
    /// system's own grab/resize handle lands, right at the tabletop —
    /// SwiftUI exposes no way to draw or reposition that handle from inside
    /// this view's own body) and `GameRenderer.rootOffset`'s depth term
    /// (kept there as its own read of `frontClearance`/`volumeSize` rather
    /// than a second hardcoded literal — see that property's own doc for
    /// why depth specifically stays a fixed constant instead of a live
    /// window-bounds read).
    ///
    /// `width` is derived from `GameMetrics.tableWidth` (the table's actual
    /// X-extent) plus `sideClearance` on each side — this used to reuse
    /// `tableLength` instead (the table's *Z*-extent, 2.0 m vs. `tableWidth`'s
    /// 1.5 m), which left the handle/ornaments sitting ~30 cm off the
    /// table's real edge rather than the ~1 cm this now targets. `depth`
    /// uses `tableLength` (correctly — the table's Z-extent) plus
    /// `frontClearance` at the front (also tightened, to 15 cm, for the
    /// same handle/ornament-alignment reason as `sideClearance` — see that
    /// property's own doc for why it's 15 cm rather than matching
    /// `sideClearance`'s 1 cm) and `backClearance` at the back (left alone —
    /// see its own doc).
    public static var volumeSize: Size3D {
        Size3D(
            width: Double(GameMetrics.tableWidth) + sideClearance * 2,
            height: volumeHeight,
            depth: frontClearance + Double(GameMetrics.tableLength) + backClearance
        )
    }
}

@MainActor
public struct GameTableView: View {
    let root: GameRoot

    @State private var game: GameTableModel?
    @State private var activityManager: GroupActivityManager?
    @State private var scaleController = TableScaleGestureController()
    @State private var accessibilitySubscriptions: [any Cancellable] = []
    /// Captured on the board-pan gesture's first `.onChanged` call, cleared
    /// on `.onEnded` — mirrors the iOS/macOS `viewportPanGesture`'s
    /// `viewportPanStart`. See CODE_AUDIT §8.1.
    @State private var viewportPanStart: SIMD3<Float>?
    /// Timestamp of the most recent `.onChanged` for the in-flight pan. If `.onEnded` is never
    /// delivered (system interruption, window backgrounding mid-drag), `viewportPanStart` would
    /// otherwise stay stuck non-nil forever, wedging every future pan against a stale start
    /// position. A later `.onChanged` that arrives after a long gap — meaning the previous
    /// gesture silently died — re-arms from a fresh start instead. See CODE_AUDIT §5.10.
    @State private var viewportPanLastUpdate: Date?
    /// The focused room captured when the in-flight pan started — `panViewport` discards the
    /// commit if this no longer matches the current focus by the time `.onEnded` fires. See
    /// CODE_AUDIT §5.12.
    @State private var viewportPanRoomId: UUID?
    /// Screen-local dice UI state (editing/player-dice toggles) for the
    /// ornament's dice action bar — mirrors `MasterGameScreen`'s own
    /// `diceShowOptionModel`, which is likewise owned per-screen rather than
    /// shared through `GameRoot`.
    @State private var diceDisplayModel = DiceDisplayModel()
    /// Backs `windowOpenButton` (leading ornament, row 2) and the trailing
    /// window-menu ornament's own buttons — mirrors `MasterGameScreen`/
    /// `PlayerGameScreen`'s own `gameScreenModel`, likewise owned per-screen
    /// rather than shared through `GameRoot`.
    @State private var gameScreenModel = GameScreenModel()
    /// Tracks the in-flight room toggle/focus request so a rapid second tap cancels the
    /// first instead of both racing `GameTableModel`'s fog recomposite. See CODE_AUDIT §5.5.
    @State private var roomActionTask: Task<Void, Never>?

    public init(root: GameRoot) {
        self.root = root
    }

    /// Cancels any in-flight room toggle/focus request before starting a new one — mirrors
    /// `GameTableModel.fogOfWarTask`'s own cancel-then-replace pattern instead of firing
    /// detached, untracked `Task`s per tap. See CODE_AUDIT §5.5.
    private func performRoomAction(_ action: @escaping @MainActor @Sendable () async -> Void) {
        roomActionTask?.cancel()
        roomActionTask = Task { await action() }
    }

    /// True once a stuck `viewportPanStart` has gone long enough without a follow-up
    /// `.onChanged` that its originating gesture almost certainly never delivered `.onEnded`.
    /// See CODE_AUDIT §5.10.
    private func isViewportPanStale() -> Bool {
        guard let viewportPanLastUpdate else { return false }
        return Date.now.timeIntervalSince(viewportPanLastUpdate) > Self.staleGestureTimeout
    }

    private static let staleGestureTimeout: TimeInterval = 3

    /// The leading ornament's window-controls row (row 1, alongside
    /// `GameTableSideMenu`) — toggles the floating adventure (master) or
    /// character sheet (player) window. Was `GameTableSideMenu`'s own first
    /// button when that view was still a separate trailing-side ornament;
    /// moved here (and `GameTableSideMenu` folded into the same row right
    /// after it) so every window-opening button the table volume offers —
    /// every "open a module window" button in row 1 plus the table/map
    /// toggle in row 2 — reads as one connected set of window controls
    /// instead of being split across two opposite corners. Mirrors
    /// `GameTableSideMenu`'s former gating for this one button exactly:
    /// master needs `adventureId` before it can even show; player needs an
    /// active (non-observer) game.
    @ViewBuilder
    private var windowOpenButton: some View {
        if root.gameModel.gameConfig.isMaster {
            if let adventureId = root.gameModel.gameConfig.master.adventureId {
                GameWindowMenuButtonView(isMaster: true, itemId: adventureId)
            }
        } else if root.gameModel.gameType != .observer {
            GameWindowMenuButtonView(isMaster: false, itemId: root.gameModel.selectedCharacter)
        }
    }

    public var body: some View {
        GeometryReader3D { proxy in
            if let loadedGame = game {
                RealityView { content, attachments in
                    content.add(loadedGame.renderer.root)

                    if accessibilitySubscriptions.isEmpty,
                       let gameScene = loadedGame.renderer.root.scene {
                        let subscription = gameScene.subscribe(to: AccessibilityEvents.Activate.self) { event in
                            if let pinId = event.entity.components[PinComponent.self]?.pinId {
                                loadedGame.pinTapped(pinId: pinId)
                            } else if let roomId = event.entity.components[RoomComponent.self]?.roomId {
                                performRoomAction { await loadedGame.toggleRoomVisibility(roomId) }
                            } else if let dice = event.entity.components[DiceComponent.self] {
                                loadedGame.tossDieForAccessibility(dieId: dice.dieId, sides: dice.sides)
                            }
                        }
                        accessibilitySubscriptions.append(subscription)
                        let zoomSubscription = gameScene.subscribe(to: AccessibilityEvents.CustomAction.self) { event in
                            if let pinId = event.entity.components[PinComponent.self]?.pinId {
                                loadedGame.pinDoubleTapped(pinId: pinId)
                            } else if let roomId = event.entity.components[RoomComponent.self]?.roomId {
                                performRoomAction { await loadedGame.toggleRoomFocus(roomId) }
                            }
                        }
                        accessibilitySubscriptions.append(zoomSubscription)
                    }

                    // Place the table on the actual floor of the volume. The volume is
                    // flatter than Apple's 1.5 m sample (and the system may clamp the
                    // requested size), so the fixed rootOffset would clip the scene.
                    // Depth (Z) is not derived from live geometry here — see
                    // `GameRenderer.rootOffset`'s own doc for why.
                    let volumeBounds = content.convert(proxy.frame(in: .local), from: .local, to: .scene)
                    loadedGame.renderer.placeTable(bottomY: volumeBounds.min.y)

                    if let pinMenu = attachments.entity(for: "pin-menu") {
                        loadedGame.registerPinMenuAttachment(pinMenu)
                    }

                } update: { content, _ in
                    // Re-anchor to the volume floor when the user resizes the volume.
                    let volumeBounds = content.convert(proxy.frame(in: .local), from: .local, to: .scene)
                    loadedGame.renderer.placeTable(bottomY: volumeBounds.min.y)
                    loadedGame.updatePinMenuAttachmentPosition()
                } attachments: {
                    Attachment(id: "pin-menu") {
                        GamePinActionMenu(game: loadedGame)
                    }
                }
                .tabletopGame(loadedGame.tabletopGame, parent: loadedGame.renderer.root) { _ in
                    GameInteraction(game: loadedGame)
                }
                // Chained directly onto this same, already-mounted `RealityView`/
                // `.tabletopGame(...)` view — not fired from `initializeGameIfNeeded()`'s
                // outer `.task` — so `coordinateWithSession(_:)` never races the
                // `.tabletopGame(_:parent:)` modifier's own mount. See
                // `setUpSharePlayCoordinationIfNeeded(for:)`'s own doc for why that
                // ordering matters.
                //
                // `waitForFirstRenderedFrame(of:)` closes a *further* gap this same
                // mount-order race left open: `.tabletopGame(_:parent:)`'s own
                // RealityKit-side registration runs as part of the engine's regular
                // per-frame ECS tick (`re::Scheduler::executePhase` /
                // `RCPSharedSimulationExecuteUpdate`), not synchronously during this
                // SwiftUI mount pass — so merely being chained onto the mounted view,
                // and even deferring `RPGSharePlayController`'s own coordination by a
                // full extra `Task { @MainActor }` turn, still wasn't reliably enough
                // of a wait: reproduced on-device joining an already-active session
                // ("Could not find static equipment with identifier: ...") with both of
                // those in place. Proof that a frame has actually rendered this scene is
                // a stronger signal than any fixed number of Task turns.
                .task {
                    await waitForFirstRenderedFrame(of: loadedGame)
                    setUpSharePlayCoordinationIfNeeded(for: loadedGame)
                }
                // Pin drag: the handlers guard permissions — the master moves
                // every pin, a player only its own.
                // Uses simultaneousGesture so TabletopKit's own gesture recognisers
                // do not consume the event before it reaches the pin entities.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 5)
                        .targetedToEntity(where: .has(PinComponent.self))
                        .onChanged { value in
                            withPinDragTarget(value) { parent in
                                value.convert(value.location3D, from: .local, to: parent)
                            } perform: { pinId, position in
                                loadedGame.pinDragChanged(pinId: pinId, position: position)
                            }
                        }
                        .onEnded { value in
                            withPinDragTarget(value) { parent in
                                value.convert(value.location3D, from: .local, to: parent)
                            } perform: { pinId, position in
                                loadedGame.pinDragEnded(pinId: pinId, position: position)
                            }
                        }
                )
                // Pans the zoomed viewport instead of moving anything in 3D
                // space — see `GameTableModel.panViewport(fromTableStart:toTableEnd:)`.
                // The iOS/macOS camera table already has this (`viewportPanGesture`
                // in this file's `#if os(iOS) || os(macOS)` half); visionOS's board
                // surface wasn't even hit-testable for it until `Board.init()`
                // (GameEquipment.swift) started setting `BoardSurfaceComponent`.
                // Commits once, on release, rather than re-rendering the board
                // texture on every touch-move event. See CODE_AUDIT §8.1.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 5)
                        .targetedToEntity(where: .has(BoardSurfaceComponent.self))
                        .onChanged { value in
                            guard let parent = value.entity.parent else { return }
                            if viewportPanStart == nil || isViewportPanStale() {
                                viewportPanStart = value.convert(value.location3D, from: .local, to: parent)
                                viewportPanRoomId = loadedGame.focusedRoomId
                            }
                            viewportPanLastUpdate = .now
                        }
                        .onEnded { value in
                            defer { viewportPanStart = nil; viewportPanLastUpdate = nil; viewportPanRoomId = nil }
                            guard let start = viewportPanStart, let parent = value.entity.parent else { return }
                            let end = value.convert(value.location3D, from: .local, to: parent)
                            loadedGame.panViewport(fromTableStart: start, toTableEnd: end, expectedRoomId: viewportPanRoomId)
                        }
                )
                // Double tap toggles zoom for both roles. Single tap toggles
                // highlight for a player, but opens/closes the master's
                // local action menu instead — long press is no longer used
                // for pins. Exclusivity prevents one physical interaction
                // firing two domain actions. The room cluster below is
                // exclusively *after* this one so a pin sitting over a
                // room's fog always wins the tap — its predicate simply
                // never matches when the touch lands only on the fog,
                // letting the room cluster win.
                .simultaneousGesture(
                    TapGesture(count: 2)
                        .targetedToEntity(where: .has(PinComponent.self))
                        .exclusively(
                            before: TapGesture()
                                .targetedToEntity(where: .has(PinComponent.self))
                        )
                        .exclusively(
                            before: LongPressGesture(minimumDuration: 0.45, maximumDistance: 5)
                                .targetedToEntity(where: .has(RoomComponent.self))
                                .exclusively(
                                    before: TapGesture(count: 2)
                                        .targetedToEntity(where: .has(RoomComponent.self))
                                )
                        )
                        .onEnded { value in
                            switch value {
                            case .first(.first(let doubleTap)):
                                guard let pinId = doubleTap.entity.components[PinComponent.self]?.pinId else { return }
                                loadedGame.pinDoubleTapped(pinId: pinId)
                            case .first(.second(let tap)):
                                guard let pinId = tap.entity.components[PinComponent.self]?.pinId else { return }
                                loadedGame.pinTapped(pinId: pinId)
                            case .second(.first(let roomLongPress)):
                                guard let roomId = roomLongPress.entity.components[RoomComponent.self]?.roomId else { return }
                                performRoomAction { await loadedGame.toggleRoomFocus(roomId) }
                            case .second(.second(let roomDoubleTap)):
                                guard let roomId = roomDoubleTap.entity.components[RoomComponent.self]?.roomId else { return }
                                performRoomAction { await loadedGame.toggleRoomVisibility(roomId) }
                            }
                        }
                )
            }
        }
        // Mirrors the iOS/macOS table's embedded `GameTableToolbar` overlay
        // (this file's `#if os(iOS) || os(macOS)` half) — same controls,
        // ornament instead of a view overlay since this window is volumetric.
        // Anchored to `GeometryReader3D` (the whole scene), not the nested
        // `RealityView` — attaching it inside the `if let loadedGame` branch
        // anchored to the RealityView's own subtree instead of the volume's
        // bounds.
        // `.parent(.bottomLeadingFront)`, not `.scene(.bottomLeading)`: the
        // 2D `UnitPoint` anchor has no Z, so SwiftUI picked a depth for us
        // that landed mid-volume (inside/behind the table) instead of at the
        // front face, level with the window's grab handle. `.parent(_:)`
        // takes a `UnitPoint3D` — since this ornament isn't nested inside
        // another one, its "parent" is the Scene, same anchor space as
        // `.scene(_:)`, just with the front (+z, toward the viewer) pinned
        // explicitly. Requires visionOS 26+ (this app's floor).
        // Requires `AppWindowSizeModel`, `\.networkActions`, and
        // `AppGameStateModel` on the scene, none of which a bare
        // `RealityView` gets for free — see `WindowVisionList`.
        //
        // The window-controls row (row 1) and dice action bar (row 3 — same
        // view `MasterGameScreen` ornaments at `.bottomLeading` on the flat
        // Game screen) sit alongside the map toolbar (row 2) in this one
        // stacked ornament rather than as their own separate ornaments —
        // that would leave multiple ornaments contending for anchor points
        // instead of a shared VStack giving that stacking for free. Row 1 is
        // every window-opening button the table volume offers —
        // `windowOpenButton` (the floating adventure/character window
        // toggle) plus `GameTableSideMenu` (the *other* module windows) —
        // combined into one row rather than a separate trailing-side
        // ornament this view used to have: with only `windowOpenButton`
        // moved here and `GameTableSideMenu` left as its own
        // `.bottomTrailingFront` ornament, the module-window buttons stayed
        // visually split across two corners for no real reason once one of
        // them had already moved — see `windowOpenButton`'s own doc for why
        // it moved in the first place. Placed above the map toolbar (rather
        // than below it, where it first landed) so the table's own window
        // controls read as the top of the stack. No manual Y
        // `.offset(...)` on the stack itself — an up-then-down row-height
        // estimate was tried here to compensate for the two extra rows and
        // ended up clipping the ornament against the volume's own bounds
        // on-device; removed rather than tuned further, since the
        // anchor/padding below already positions the stack correctly on its
        // own without it.
        .ornament(attachmentAnchor: .parent(.bottomLeadingFront), contentAlignment: .topLeading) {
            if let game {
                VStack(alignment: .leading, spacing: 12) {
                    // `GameTableSideMenu` is deliberately bare (no own
                    // `HStack`/`GlassEffectContainerAll`) so it and
                    // `windowOpenButton` share this one glass group instead
                    // of nesting one inside another — see that struct's own
                    // doc. No extra `.padding()` here, matching row 2
                    // (`GameTableToolbar`) and row 3 (the dice bar's own
                    // `GlassEffectContainerAll`, similarly unpadded) — this
                    // row stays flush with the others under the shared
                    // VStack's leading alignment instead of indenting itself.
                    GlassEffectContainerAll {
                        HStack(spacing: 8) {
                            windowOpenButton

                            GameTableSideMenu(root: root, isMaster: root.gameModel.gameConfig.isMaster)
                        }
                    }
                    .environment(gameScreenModel)

                    // GameTableToolbar itself keeps the table/map window
                    // toggle always visible and only hides the shared
                    // map-specific controls until a map is loaded.
                    GameTableToolbar(root: root, game: game)
                        .environment(gameScreenModel)

                    root.diceRoot.viewController.diceActionBarView(root: root.diceRoot)
                        .environment(diceDisplayModel)
                }
                .padding(.top, 12)
            }
        }
        .task {
            await initializeGameIfNeeded()
        }
        .task(id: root.mapRoot.gameControllable.gameModel.currentItemId) {
            guard let game else { return }
            await game.handleMapChange(
                isGameMaster: root.gameModel.gameConfig.isMaster
            )
        }
        // Mirrors the currently focused character-sheet dice set onto this
        // player's own seat dice — both its shape (count and type per die,
        // so switching focus without rolling still updates the table) and
        // every rolled result. Watches `focusedDiceSignature`, not
        // `focusItemIds` alone — re-rolling the already-focused dice
        // mutates `DiceModel.dice[].result` in place without the focus id
        // array itself changing, so that alone wouldn't fire this.
        .onChange(of: focusedDiceSignature, initial: false) { _, _ in
            guard let game else { return }
            applyCurrentFocusedDiceRoll(to: game)
        }
        .task {
            await scaleController.start()
        }
        .onDisappear {
            roomActionTask?.cancel()
            accessibilitySubscriptions.removeAll()
            // `game`/`renderer.root` are retained across this volumetric window
            // disappearing (see `initializeGameIfNeeded()`'s "if let game"
            // branch), but the "pin-menu" `Attachment`'s `_HostingEntity` is
            // not — detach it now rather than leaving it parented under
            // `renderer.root` as a stale, mid-teardown entity for the next
            // `RealityView` mount's `content.add(renderer.root)` to walk back
            // over. See `GameTableModel.registerPinMenuAttachment(_:)`'s doc.
            game?.detachPinMenuAttachment()
            root.gameModel.shareState.mode = .window
            root.networkStore.sharePlayStore.applyShareState()
            if root.gameModel.gameTableModel === game {
                root.gameModel.gameTableModel = nil
            }
        }
    }

    private func initializeGameIfNeeded() async {
        if let game {
            // A volumetric window can disappear without discarding its @State.
            // Re-register the retained model instead of rebuilding the complete
            // TabletopKit graph and loading its package assets again.
            root.gameModel.gameTableModel = game
            scaleController.renderer = game.renderer
            root.gameModel.shareState.mode = .tabletop
            root.networkStore.sharePlayStore.applyShareState()
            configureSessionState(for: game)
            game.applyFocusedDiceRollForLocalSeat = { [weak game] in
                guard let game else { return }
                applyCurrentFocusedDiceRoll(to: game)
            }
            await game.handleMapChange(isGameMaster: game.isGameMaster)
            applyCurrentFocusedDiceRoll(to: game)
            return
        }

        let initializedGame = GameTableModel(
            mapRoot: root.mapRoot,
            photoRoot: root.photoRoot
        )
        await initializedGame.renderer.loadAssets()
        guard !Task.isCancelled else { return }

        root.gameModel.gameTableModel = initializedGame
        game = initializedGame
        scaleController.renderer = initializedGame.renderer
        root.gameModel.shareState.mode = .tabletop
        root.networkStore.sharePlayStore.applyShareState()

        // `activityManager` (and the `coordinateWithSession(_:)` it triggers) is
        // deliberately *not* created here — setting `game` above only schedules a
        // SwiftUI re-render; it doesn't synchronously mount the `RealityView`/
        // `.tabletopGame(...)` below. See `setUpSharePlayCoordinationIfNeeded(for:)`,
        // called instead from a `.task` chained directly onto that mounted view.

        // Set before `setupSeating` claims a seat — `GameObserver.playerChangedSeats`
        // can fire as part of that claim landing, and needs this hook already in
        // place to retry a dice-focus mirror that raced the not-yet-existing seat.
        // See `GameTableModel.applyFocusedDiceRollForLocalSeat`.
        initializedGame.applyFocusedDiceRollForLocalSeat = { [weak initializedGame] in
            guard let initializedGame else { return }
            applyCurrentFocusedDiceRoll(to: initializedGame)
        }
        initializedGame.setupSeating(
            sharePlayController: root.networkStore.sharePlayStore
        )
        configureSessionState(for: initializedGame)

        // The volume can open after a map is already revealed — bring the
        // table up to date immediately instead of waiting for a mapState trip.
        await initializedGame.handleMapChange(
            isGameMaster: initializedGame.isGameMaster
        )
        guard !Task.isCancelled else { return }
        initializedGame.syncPawnsWithMapPins()

        // Same reasoning: the volume can open after the character
        // sheet's dice are already focused and rolled — the `.onChange`
        // above only fires on the *next* roll, so without this a die that
        // was already showing a result on the 2D screen would sit at its
        // default face on the table until someone rolled again.
        applyCurrentFocusedDiceRoll(to: initializedGame)
    }

    /// Creates `activityManager`, which is what actually calls
    /// `tabletopGame.coordinateWithSession(_:)` (via `GroupActivityManager.init` →
    /// `RPGSharePlayController.setup(tabletopGame:gameTableModel:)`) once a
    /// SharePlay session exists — deliberately called from a `.task` chained
    /// directly onto the already-mounted `RealityView`/`.tabletopGame(...)` view
    /// below, not from `initializeGameIfNeeded()`'s outer `.task`.
    ///
    /// `coordinateWithSession(_:)` joins this device into the SharePlay session's
    /// RealityKit *shared simulation* — a lower-level join than anything
    /// TabletopKit's own Swift API surface does. That join replays the master's
    /// already-established ECS state against this device's local scene, resolved
    /// through TabletopKit's own RealityKit `System`, which the
    /// `.tabletopGame(_:parent:)` modifier registers when it mounts. Setting the
    /// `game` `@State` (in `initializeGameIfNeeded()`) only *schedules* a SwiftUI
    /// re-render — it doesn't synchronously mount the view below — so triggering
    /// the join from that same synchronous stretch of code raced
    /// `.tabletopGame(_:parent:)`'s own mount. Losing that race left the shared-
    /// simulation replay running against a scene TabletopKit's system hadn't
    /// attached to yet, unpredictably failing to resolve one of the master's
    /// already-known equipment entities — "Could not find static equipment with
    /// identifier: ..." — inside RealityKit's own engine
    /// (`RCPSharedSimulationExecuteUpdate` → `-[MRUISharedSimulation
    /// _joinWithConnectionContext:error:]`), well below any of our own Swift-level
    /// TabletopKit calls (`claimSeat`, `setupSeating`, etc. — see their own docs
    /// for a *different*, since-fixed race that never was the actual cause here).
    /// Apple's own TabletopKit SharePlay samples never hit this because their
    /// `.tabletopGame(_:parent:)` is unconditionally present from the very first
    /// render — never gated behind an async-loaded `@State` the way `game` is
    /// here — so their own `.task { activityManager = .init(...) }`, chained on
    /// that same view, can't ever run before it.
    ///
    /// Guarded on `activityManager == nil`: this `.task` re-fires whenever the
    /// RealityView reappears (e.g. the volumetric window disappearing and
    /// reappearing while `@State` is retained — see `initializeGameIfNeeded()`'s
    /// own "if let game" branch), and re-coordinating an already-coordinated
    /// `tabletopGame` is neither needed nor safe.
    private func setUpSharePlayCoordinationIfNeeded(for game: GameTableModel) {
        guard activityManager == nil else { return }
        activityManager = .init(
            tabletopGame: game.tabletopGame,
            gameTableModel: game,
            sharePlayController: root.networkStore.sharePlayStore
        )
    }

    /// Awaits one `SceneEvents.Update` from `game`'s scene — see this
    /// method's call site (the `.task` right above the `.tabletopGame(_:
    /// parent:)` modifier) for why proof of an actual rendered frame is
    /// needed before triggering SharePlay coordination, not just being
    /// chained onto the mounted view. A no-op (returns immediately) if the
    /// scene somehow isn't attached yet, rather than hanging forever.
    private func waitForFirstRenderedFrame(of game: GameTableModel) async {
        guard let scene = game.renderer.root.scene else { return }
        await withCheckedContinuation { continuation in
            var subscription: (any Cancellable)?
            subscription = scene.subscribe(to: SceneEvents.Update.self) { _ in
                subscription?.cancel()
                continuation.resume()
            }
        }
    }

    /// Applies the locally focused dice set to `game`'s own seat, or clears
    /// that seat's table dice entirely when nothing is focused — so
    /// deselecting a dice sheet doesn't leave stale dice sitting on the
    /// table (see `GameTableModel.applyDiceRoll`'s "0 needed" case).
    private func applyCurrentFocusedDiceRoll(to game: GameTableModel) {
        guard let focusId = root.diceRoot.diceGameControllable.gameModel.focusItemIds.first,
              let diceModel = root.diceRoot.diceGameControllable.gameModel.itemData[focusId] as? DiceModel else {
            game.applyDiceRoll(.empty)
            return
        }
        game.applyDiceRoll(diceModel)
    }

    /// Everything about the currently-focused character-sheet dice set that
    /// should re-mirror it onto the 3D table: which set is focused at all
    /// (`focusId`, so deselecting is also a change), its shape — side count
    /// per die, so switching from e.g. "2d20" to "4d6" without rolling still
    /// updates the table — and every rolled result. Changes on every roll,
    /// including a re-roll of the same dice, unlike `focusItemIds` alone
    /// (which only changes when the *selection* changes).
    private var focusedDiceSignature: [Int] {
        guard let focusId = root.diceRoot.diceGameControllable.gameModel.focusItemIds.first,
              let diceModel = root.diceRoot.diceGameControllable.gameModel.itemData[focusId] as? DiceModel else {
            return []
        }
        return diceModel.dice.flatMap { [$0.die.max] + $0.result }
    }

    private func configureSessionState(for game: GameTableModel) {
        game.networkActions = root.networkActions
        game.isGameMaster = root.gameModel.gameConfig.isMaster
        game.playerPinId = game.isGameMaster ? nil : root.gameModel.gameConfig.id
    }
}

#Preview {
    GameTableView(root: .preview)
}

#endif

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
    /// Timestamp of the most recent `.onChanged` for the in-flight pan. If `.onEnded` is never
    /// delivered (system interruption, window backgrounding mid-drag), `viewportPanStart` would
    /// otherwise stay stuck non-nil forever, wedging every future pan against a stale start
    /// position. A later `.onChanged` that arrives after a long gap — meaning the previous
    /// gesture silently died — re-arms from a fresh start instead. See CODE_AUDIT §5.10.
    @State private var viewportPanLastUpdate: Date?
    /// The focused room captured when the in-flight pan started — `panViewport` discards the
    /// commit if this no longer matches the current focus by the time `.onEnded` fires. See
    /// CODE_AUDIT §5.12.
    @State private var viewportPanRoomId: UUID?
    /// The running total of table-move translation applied so far this drag (`tableMoveGesture`,
    /// or `boardDragGesture` when it's moving the table rather than panning) — `DragGesture.Value.translation`
    /// is cumulative from the gesture's start, not per-frame, so this is what lets `.onChanged`
    /// apply only the *new* delta each call. Reset on `.onEnded`.
    @State private var tableMoveLastTranslation: CGSize = .zero
    /// Timestamp of the most recent `.onChanged` for the in-flight table-move drag. Mirrors
    /// `viewportPanLastUpdate`'s own doc: if `.onEnded` is never delivered, `tableMoveLastTranslation`
    /// would otherwise stay stuck non-zero forever, applying one large, wrong jump to the table's
    /// position on the next unrelated table-move gesture. See CODE_AUDIT §5.1.
    @State private var tableMoveLastUpdate: Date?
    /// `nil` at rest; decided once per `boardDragGesture`, on its first
    /// `.onChanged` call, from whether a room was focused *then* — not
    /// re-checked on every subsequent call, so a focus change arriving
    /// mid-drag (e.g. a synced update from another participant) can't swap
    /// behavior out from under the user's finger. `true` = panning the
    /// viewport crop; `false` = moving the table.
    @State private var boardDragPansViewport: Bool?
    /// Tracks the in-flight room toggle/focus request so a rapid second tap cancels the
    /// first instead of both racing `GameTableModel`'s fog recomposite. See CODE_AUDIT §5.5.
    @State private var roomActionTask: Task<Void, Never>?

    /// Cancels any in-flight room toggle/focus request before starting a new one — mirrors
    /// `GameTableModel.fogOfWarTask`'s own cancel-then-replace pattern instead of firing
    /// detached, untracked `Task`s per tap. See CODE_AUDIT §5.5.
    private func performRoomAction(_ action: @escaping @MainActor @Sendable () async -> Void) {
        roomActionTask?.cancel()
        roomActionTask = Task { await action() }
    }

    /// True once a stuck `viewportPanStart` has gone long enough without a follow-up
    /// `.onChanged` that its originating gesture almost certainly never delivered `.onEnded`.
    /// See CODE_AUDIT §5.10.
    private func isViewportPanStale() -> Bool {
        guard let viewportPanLastUpdate else { return false }
        return Date.now.timeIntervalSince(viewportPanLastUpdate) > Self.staleGestureTimeout
    }

    /// True once a stuck `tableMoveLastTranslation` has gone long enough without a follow-up
    /// `.onChanged` that its originating gesture almost certainly never delivered `.onEnded`.
    /// See CODE_AUDIT §5.1.
    private func isTableMoveStale() -> Bool {
        guard let tableMoveLastUpdate else { return false }
        return Date.now.timeIntervalSince(tableMoveLastUpdate) > Self.staleGestureTimeout
    }

    private static let staleGestureTimeout: TimeInterval = 3

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
            roomActionTask?.cancel()
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
                    if viewportPanStart == nil || isViewportPanStale() {
                        viewportPanStart = position
                        viewportPanRoomId = game.focusedRoomId
                    }
                    viewportPanLastUpdate = .now
                } else {
                    applyTableMoveDelta(translation: value.translation)
                }
            }
            .onEnded { value in
                defer { boardDragPansViewport = nil }
                if boardDragPansViewport == true {
                    defer { viewportPanStart = nil; viewportPanLastUpdate = nil; viewportPanRoomId = nil }
                    guard let start = viewportPanStart,
                          let end = value.tablePosition(relativeTo: game.renderer.root) else { return }
                    game.panViewport(fromTableStart: start, toTableEnd: end, expectedRoomId: viewportPanRoomId)
                } else {
                    tableMoveLastTranslation = .zero
                    tableMoveLastUpdate = nil
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
                tableMoveLastUpdate = nil
            }
    }

    /// Shared by `tableMoveGesture` and `boardDragGesture` (when the latter
    /// is moving the table rather than panning) — `translation` is each
    /// gesture's own cumulative-since-start value, whatever its concrete
    /// type (`DragGesture.Value` or `EntityTargetValue<DragGesture.Value>`
    /// both expose it as `CGSize`), so only the value itself needs passing.
    private func applyTableMoveDelta(translation: CGSize) {
        if isTableMoveStale() {
            // The previous drag's `.onEnded` was likely never delivered (system
            // interruption, window backgrounding mid-drag) — re-arm from this call's
            // value instead of computing a delta against the stale one, mirroring
            // `viewportPanStart`/`isViewportPanStale()`. See CODE_AUDIT §5.1.
            tableMoveLastTranslation = translation
        }
        let delta = CGSize(
            width: translation.width - tableMoveLastTranslation.width,
            height: translation.height - tableMoveLastTranslation.height
        )
        tableMoveLastTranslation = translation
        tableMoveLastUpdate = .now
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
                    performRoomAction { await game.toggleRoomFocus(roomId) }
                case .second(let doubleTap):
                    guard let roomId = doubleTap.entity.components[RoomComponent.self]?.roomId else { return }
                    performRoomAction { await game.toggleRoomVisibility(roomId) }
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
                    performRoomAction { await game.toggleRoomVisibility(roomId) }
                }
            }
        }
        let zoom = scene.subscribe(to: AccessibilityEvents.CustomAction.self) { event in
            Task { @MainActor in
                if let pinId = event.entity.components[PinComponent.self]?.pinId {
                    game.pinDoubleTapped(pinId: pinId)
                } else if let roomId = event.entity.components[RoomComponent.self]?.roomId {
                    performRoomAction { await game.toggleRoomFocus(roomId) }
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
