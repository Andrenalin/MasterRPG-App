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
    /// Backs the trailing-side window menu ornament's `MasterGameWindowButtonView`/
    /// `PlayerGameWindowButtonView` — mirrors `MasterGameScreen`/`PlayerGameScreen`'s
    /// own `gameScreenModel`, likewise owned per-screen rather than shared
    /// through `GameRoot`.
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
                // Pin drag: the handlers guard permissions — the master moves
                // every pin, a player only its own.
                // Uses simultaneousGesture so TabletopKit's own gesture recognisers
                // do not consume the event before it reaches the pin entities.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 5)
                        .targetedToEntity(where: .has(PinComponent.self))
                        .onChanged { value in
                            guard let pinId = value.entity.components[PinComponent.self]?.pinId,
                                  let parent = value.entity.parent else { return }
                            let position = value.convert(value.location3D, from: .local, to: parent)
                            loadedGame.pinDragChanged(pinId: pinId, position: position)
                        }
                        .onEnded { value in
                            guard let pinId = value.entity.components[PinComponent.self]?.pinId,
                                  let parent = value.entity.parent else { return }
                            let position = value.convert(value.location3D, from: .local, to: parent)
                            loadedGame.pinDragEnded(pinId: pinId, position: position)
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
                // Double tap toggles zoom, single tap toggles highlight, and a
                // stationary long press opens the master's local action menu.
                // Exclusivity prevents one physical interaction firing two
                // domain actions. The room cluster below is exclusively
                // *after* this one so a pin sitting over a room's fog always
                // wins the tap — its predicate simply never matches when the
                // touch lands only on the fog, letting the room cluster win.
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.45, maximumDistance: 5)
                        .targetedToEntity(where: .has(PinComponent.self))
                        .exclusively(
                            before: TapGesture(count: 2)
                                .targetedToEntity(where: .has(PinComponent.self))
                                .exclusively(
                                    before: TapGesture()
                                        .targetedToEntity(where: .has(PinComponent.self))
                                )
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
                            case .first(.first(let longPress)):
                                guard let pinId = longPress.entity.components[PinComponent.self]?.pinId else { return }
                                loadedGame.pinLongPressed(pinId: pinId)
                            case .first(.second(.first(let doubleTap))):
                                guard let pinId = doubleTap.entity.components[PinComponent.self]?.pinId else { return }
                                loadedGame.pinDoubleTapped(pinId: pinId)
                            case .first(.second(.second(let tap))):
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
        // The dice action bar (same view `MasterGameScreen` ornaments at
        // `.bottomLeading` on the flat Game screen) sits under the map
        // toolbar in this one stacked ornament rather than as its own
        // separate ornament at the same corner — that would leave two
        // ornaments contending for the identical anchor point instead of
        // the map toolbar simply sitting higher to make room, which a
        // shared VStack gives for free.
        .ornament(attachmentAnchor: .parent(.bottomLeadingFront), contentAlignment: .topLeading) {
            if let game {
                VStack(alignment: .leading, spacing: 12) {
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
        // Companion to the leading map-toolbar/dice-bar ornament above: the
        // window menu (`GameTableSideMenu`) letting the master/player open
        // other module windows without leaving the table volume — same
        // buttons as the flat 2D game screens' own trailing ornament
        // (`MasterSideMenu`/`PlayerSideMenu`), just laid out as a row
        // instead of a column. `.parent(.bottomTrailingFront)` for the same
        // reason `.bottomLeadingFront` is used above rather than
        // `.scene(.trailing)` (what the flat screens use): the 2D
        // `UnitPoint` anchor has no Z, so SwiftUI would pick a depth that
        // lands mid-volume instead of the front face.
        .ornament(attachmentAnchor: .parent(.bottomTrailingFront), contentAlignment: .topTrailing) {
            GameTableSideMenu(
                root: root,
                isMaster: root.gameModel.gameConfig.isMaster,
                adventureId: root.gameModel.gameConfig.master.adventureId
            )
            .environment(gameScreenModel)
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

        activityManager = .init(
            tabletopGame: initializedGame.tabletopGame,
            sharePlayController: root.networkStore.sharePlayStore
        )
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

    /// Captured on `viewportPanGesture`'s first `.onChanged` call, cleared on
    /// `.onEnded` — the pan commits once, in a single step, rather than
    /// re-rendering the board texture on every touch-move event.
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
        // default. Instead, pinDragGesture below wins priority over the drag
        // component only for touches that start on a pin, leaving zoom/rotate
        // untouched and every other drag orbiting the table as usual.
        .realityViewCameraControls(.orbit)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            game.renderer.updateCamera(for: size)
        }
        .highPriorityGesture(pinDragGesture)
        // Wins over `.orbit`'s bundled one-finger drag (see the comment
        // above) only for touches starting on the map surface itself, so a
        // room, once focused/zoomed, can be panned within its own crop by
        // dragging it — like the 2D map's viewport, not by moving anything
        // in 3D space (see `GameTableModel.manualViewportOffset`). Distinct
        // from `BoardSurfaceComponent`'s hit-test volume: pins and room fog
        // sit closer to the camera and keep winning ties, so this never
        // steals from `pinDragGesture` or `roomTapGesture` below.
        .highPriorityGesture(viewportPanGesture)
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
                guard let pinId = value.entity.components[PinComponent.self]?.pinId,
                      let parent = value.entity.parent,
                      let position = value.tablePosition(relativeTo: parent) else { return }
                game.pinDragChanged(pinId: pinId, position: position)
            }
            .onEnded { value in
                guard let pinId = value.entity.components[PinComponent.self]?.pinId,
                      let parent = value.entity.parent,
                      let position = value.tablePosition(relativeTo: parent) else { return }
                game.pinDragEnded(pinId: pinId, position: position)
            }
    }

    /// Pans the zoomed viewport instead of moving a pin or the table itself —
    /// see `GameTableModel.panViewport(fromTableStart:toTableEnd:)`. Commits
    /// once, on release, rather than re-rendering the board texture (an
    /// `ImageRenderer` pass, not cheap) on every touch-move event.
    private var viewportPanGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .targetedToEntity(where: .has(BoardSurfaceComponent.self))
            .onChanged { value in
                guard let position = value.tablePosition(relativeTo: game.renderer.root) else { return }
                if viewportPanStart == nil || isViewportPanStale() {
                    viewportPanStart = position
                    viewportPanRoomId = game.focusedRoomId
                }
                viewportPanLastUpdate = .now
            }
            .onEnded { value in
                defer { viewportPanStart = nil; viewportPanLastUpdate = nil; viewportPanRoomId = nil }
                guard let start = viewportPanStart,
                      let end = value.tablePosition(relativeTo: game.renderer.root) else { return }
                game.panViewport(fromTableStart: start, toTableEnd: end, expectedRoomId: viewportPanRoomId)
            }
    }

    private var pinTapGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.45, maximumDistance: 5)
            .targetedToEntity(where: .has(PinComponent.self))
            .exclusively(
                before: TapGesture(count: 2)
                    .targetedToEntity(where: .has(PinComponent.self))
                    .exclusively(
                        before: TapGesture()
                            .targetedToEntity(where: .has(PinComponent.self))
                    )
            )
            .onEnded { value in
                switch value {
                case .first(let longPress):
                    guard let pinId = longPress.entity.components[PinComponent.self]?.pinId else { return }
                    game.pinLongPressed(pinId: pinId)
                case .second(.first(let doubleTap)):
                    guard let pinId = doubleTap.entity.components[PinComponent.self]?.pinId else { return }
                    game.pinDoubleTapped(pinId: pinId)
                case .second(.second(let tap)):
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
