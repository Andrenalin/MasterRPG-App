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

    /// How far the front ornament is lifted clear of the window's grab handle.
    private static let handleClearance: CGFloat = 16

    /// Handed on to the dice result attachments, which host the dice overlay's own views.
    @Environment(AppGameStateModel.self) private var appGameStateModel: AppGameStateModel?
    @Environment(\.networkActions) private var networkActions

    @State private var game: GameTableModel?
    @State private var activityManager: GroupActivityManager?
    @State private var scaleController = TableScaleGestureController()
    @State private var accessibilitySubscriptions: [any Cancellable] = []
    /// Screen-local dice UI state (editing/player-dice toggles) for the
    /// dice result attachments — mirrors `MasterGameScreen`'s own
    /// `diceShowOptionModel`, which is likewise owned per-screen rather than
    /// shared through `GameRoot`.
    @State private var diceDisplayModel = DiceDisplayModel()
    /// Backs `WindowOpenButton` and `GameTableSideMenu` (front ornament,
    /// row 1) — mirrors `MasterGameScreen`/
    /// `PlayerGameScreen`'s own `gameScreenModel`, likewise owned per-screen
    /// rather than shared through `GameRoot`.
    @State private var gameScreenModel = GameScreenModel()
    /// Tracks the in-flight room toggle/focus request so a rapid second tap cancels the
    /// first instead of both racing `GameTableModel`'s fog recomposite.
    @State private var roomActionCoordinator = RoomActionCoordinator()

    public init(root: GameRoot) {
        self.root = root
    }

    public var body: some View {
        GeometryReader3D { proxy in
            if let loadedGame = game {
                RealityView { content, attachments in
                    content.add(loadedGame.renderer.root)

                    if accessibilitySubscriptions.isEmpty,
                       let gameScene = loadedGame.renderer.root.scene {
                        // Captured directly so the event closures don't hold this view value.
                        let coordinator = roomActionCoordinator
                        let subscription = gameScene.subscribe(to: AccessibilityEvents.Activate.self) { event in
                            if let pinId = event.entity.components[PinComponent.self]?.pinId {
                                loadedGame.pinTapped(pinId: pinId)
                            } else if let roomId = event.entity.components[RoomComponent.self]?.roomId {
                                coordinator.perform { await loadedGame.toggleRoomVisibility(roomId) }
                            } else if let dice = event.entity.components[DiceComponent.self] {
                                loadedGame.tossDieForAccessibility(dieId: dice.dieId, sides: dice.sides)
                            }
                        }
                        accessibilitySubscriptions.append(subscription)
                        let zoomSubscription = gameScene.subscribe(to: AccessibilityEvents.CustomAction.self) { event in
                            if let pinId = event.entity.components[PinComponent.self]?.pinId {
                                loadedGame.pinDoubleTapped(pinId: pinId)
                            } else if let roomId = event.entity.components[RoomComponent.self]?.roomId {
                                coordinator.perform { await loadedGame.toggleRoomFocus(roomId) }
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

                    for kind in TablePopoverKind.allCases {
                        if let popover = attachments.entity(for: kind.attachmentId) {
                            loadedGame.registerAttachment(popover, for: kind)
                        }
                    }
                    for group in loadedGame.diceResultGroups {
                        if let diceResult = attachments.entity(for: GameDiceResultPopover.attachmentId(for: group)) {
                            loadedGame.registerDiceResultAttachment(diceResult, for: group)
                        }
                    }

                } update: { content, _ in
                    // Re-anchor to the volume floor when the user resizes the volume.
                    let volumeBounds = content.convert(proxy.frame(in: .local), from: .local, to: .scene)
                    loadedGame.renderer.placeTable(bottomY: volumeBounds.min.y)
                    loadedGame.updateAttachmentPositions()
                } attachments: {
                    Attachment(id: TablePopoverKind.pinMenu.attachmentId) {
                        GamePinActionMenu(game: loadedGame)
                    }
                    Attachment(id: TablePopoverKind.pinPhoto.attachmentId) {
                        GamePinPhotoPopover(game: loadedGame)
                    }
                    Attachment(id: TablePopoverKind.mapPhoto.attachmentId) {
                        GameMapPhotoPopover(game: loadedGame)
                    }
                    // One per dice group: every seat's dice, and every guest's at the guest
                    // seat, can show a result at the same time.
                    ForEach(loadedGame.diceResultGroups, id: \.self) { group in
                        Attachment(id: GameDiceResultPopover.attachmentId(for: group)) {
                            GameDiceResultPopover(
                                root: root,
                                game: loadedGame,
                                group: group,
                                diceDisplayModel: diceDisplayModel,
                                appGameStateModel: appGameStateModel,
                                networkActions: networkActions
                            )
                        }
                    }
                }
                .tabletopGame(loadedGame.tabletopGame, parent: loadedGame.renderer.root) { _ in
                    GameInteraction(game: loadedGame)
                }
                // Chained onto this already-mounted `RealityView`/`.tabletopGame(...)` view, not fired
                // from `initializeGameIfNeeded()`, so `coordinateWithSession(_:)` never races the
                // modifier's own mount. TabletopKit registers with RealityKit as part of the engine's
                // per-frame tick, so waiting for one rendered frame is a stronger guarantee than any
                // fixed number of Task turns. See `setUpSharePlayCoordinationIfNeeded(for:)`.
                .task {
                    await loadedGame.waitForFirstRenderedFrame()
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
                // Double tap opens the pin's photo popover for both roles. Single tap toggles
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
                                roomActionCoordinator.perform { await loadedGame.toggleRoomFocus(roomId) }
                            case .second(.second(let roomDoubleTap)):
                                guard let roomId = roomDoubleTap.entity.components[RoomComponent.self]?.roomId else { return }
                                roomActionCoordinator.perform { await loadedGame.toggleRoomVisibility(roomId) }
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
        // `.parent(.bottomFront)`, not `.scene(.bottom)`: the
        // 2D `UnitPoint` anchor has no Z, so SwiftUI picked a depth for us
        // that landed mid-volume (inside/behind the table) instead of at the
        // front face, level with the window's grab handle. `.parent(_:)`
        // takes a `UnitPoint3D` — since this ornament isn't nested inside
        // another one, its "parent" is the Scene, same anchor space as
        // `.scene(_:)`, just with the front (+z, toward the viewer) pinned
        // explicitly. Requires visionOS 26+ (this app's floor).
        // Horizontally centered on that front face (with `.top` content
        // alignment, so the stack hangs centered below the volume's front
        // edge) rather than at its leading corner, where it sat off to the
        // side of the user's own seat.
        // Requires `AppWindowSizeModel`, `\.networkActions`, and
        // `AppGameStateModel` on the scene, none of which a bare
        // `RealityView` gets for free — see `WindowVisionList`.
        //
        // The window-controls row (row 1) sits alongside the map toolbar
        // (row 2) in this one stacked ornament rather than as its own
        // separate ornament — that would leave multiple ornaments contending
        // for anchor points instead of a shared VStack giving that stacking
        // for free. The stack as a whole is centered on the front face, but
        // its rows are leading-aligned to each other, so the map toolbar
        // starts under the window controls' own first button. No dice action
        // bar here (the flat Game screen's `.bottomLeading` ornament has
        // one): the table shows the dice themselves and their result
        // attachments, so the edit/overlay toggles aren't needed. Row 1 is
        // every window-opening button the table volume offers —
        // `WindowOpenButton` (the floating adventure/character window
        // toggle) plus `GameTableSideMenu` (the *other* module windows) —
        // combined into one row rather than a separate trailing-side
        // ornament this view used to have: with only `WindowOpenButton`
        // moved here and `GameTableSideMenu` left as its own
        // `.bottomTrailingFront` ornament, the module-window buttons stayed
        // visually split across two places for no real reason once one of
        // them had already moved — see `WindowOpenButton`'s own doc for why
        // it moved in the first place. Placed above the map toolbar (rather
        // than below it, where it first landed) so the table's own window
        // controls read as the top of the stack. No manual Y
        // `.offset(...)` on the stack itself — an up-then-down row-height
        // estimate was tried here to compensate for the extra rows and
        // ended up clipping the ornament against the volume's own bounds
        // on-device; removed rather than tuned further, since the
        // anchor/padding below already positions the stack correctly on its
        // own without it.
        .ornament(attachmentAnchor: .parent(.bottomFront), contentAlignment: .top) {
            if let game {
                VStack(alignment: .leading) {
                    // `GameTableSideMenu` is deliberately bare (no own
                    // `HStack`/`GlassEffectContainerAll`) so it and
                    // `WindowOpenButton` share this one glass group instead
                    // of nesting one inside another — see that struct's own
                    // doc. No extra `.padding()` here, matching row 2
                    // (`GameTableToolbar`) — this row stays flush with it
                    // under the shared VStack's leading alignment instead of
                    // indenting itself.
                    GlassEffectContainerAll {
                        HStack {
                            WindowOpenButton(root: root)

                            GameTableSideMenu(root: root, isMaster: root.gameModel.gameConfig.isMaster)

                            // The last button of row 1, after the dice. The map toolbar (and
                            // the game master's extra map buttons) stay in row 2.
                            GameTableWindowButton(root: root, isMaster: root.gameModel.gameConfig.isMaster)
                        }
                    }
                    .environment(gameScreenModel)

                    // GameTableToolbar itself keeps the table/map window
                    // toggle always visible and only hides the shared
                    // map-specific controls until a map is loaded.
                    GameTableToolbar(root: root, game: game)
                        .environment(gameScreenModel)

                    GameTableNoticesView(game: game)
                }
                .padding(.top)
                // Lifts the whole stack off the window's grab handle, which sits at the
                // front edge just below it; row 1 keeps a fixed position whether or not row 2
                // (the map toolbar) is shown, because the stack hangs from its top.
                .offset(y: -Self.handleClearance)
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
        // The game master's weather, in 3D over the map.
        .modifier(GameTableWeatherSync(root: root, game: game))
        // Mirrors the currently focused character-sheet dice set onto this
        // player's own seat dice — both its shape (count and type per die,
        // so switching focus without rolling still updates the table) and
        // every rolled result. Watches `focusedDice`, not
        // `focusItemIds` alone — re-rolling the already-focused dice
        // mutates `DiceModel.dice[].result` in place without the focus id
        // array itself changing, so that alone wouldn't fire this.
        .onChange(of: focusedDice, initial: false) { _, _ in
            guard let game else { return }
            applyCurrentFocusedDiceRoll(to: game)
        }
        // The players without a table — the game master too, when not on Vision Pro — have no
        // dice of their own here: their shared rolls are shown at the guest seat. See `GameTableModel.applyGuestRolls(_:)`.
        .onChange(of: guestRolls, initial: false) { _, rolls in
            game?.applyGuestRolls(rolls)
        }
        // The photo the game master shows on the map stands at its anchor on the table.
        .onChange(of: root.mapRoot.photoPopover.photo) {
            game?.updateMapPhotoAnchor()
        }
        .task {
            await scaleController.start()
        }
        .onDisappear {
            roomActionCoordinator.cancel()
            accessibilitySubscriptions.removeAll()
            // `game`/`renderer.root` are retained across this volumetric window
            // disappearing (see `initializeGameIfNeeded()`'s "if let game"
            // branch), but the "pin-menu" `Attachment`'s `_HostingEntity` is
            // not — detach it now rather than leaving it parented under
            // `renderer.root` as a stale, mid-teardown entity for the next
            // `RealityView` mount's `content.add(renderer.root)` to walk back
            // over. See `TablePopoverAnchor.register(_:in:)`'s doc.
            game?.detachAttachments()
            game?.detachDiceResultAttachments()
            root.gameModel.shareState.mode = .window
            root.networkStore.sharePlayStore.applyShareState()
            if root.gameModel.gameTableModel === game {
                root.gameModel.gameTableModel = nil
            }
            if root.spaceRoot.tablePlacementReference === game?.renderer.tableTopEntity {
                root.spaceRoot.tablePlacementReference = nil
            }
        }
    }

    private func initializeGameIfNeeded() async {
        if let game {
            // A volumetric window can disappear without discarding its @State.
            // Re-register the retained model instead of rebuilding the complete
            // TabletopKit graph and loading its package assets again.
            root.gameModel.gameTableModel = game
            root.spaceRoot.tablePlacementReference = game.renderer.tableTopEntity
            scaleController.renderer = game.renderer
            root.gameModel.shareState.mode = .tabletop
            root.networkStore.sharePlayStore.applyShareState()
            game.configureSession(from: root)
            game.applyFocusedDiceRollForLocalSeat = Self.focusedDiceHandler(for: game, diceRoot: root.diceRoot)
            await game.handleMapChange(isGameMaster: game.isGameMaster)
            applyCurrentFocusedDiceRoll(to: game)
            game.applyGuestRolls(guestRolls)
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
        root.spaceRoot.tablePlacementReference = initializedGame.renderer.tableTopEntity
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
        initializedGame.applyFocusedDiceRollForLocalSeat = Self.focusedDiceHandler(for: initializedGame, diceRoot: root.diceRoot)
        initializedGame.setupSeating(
            sharePlayController: root.networkStore.sharePlayStore
        )
        initializedGame.configureSession(from: root)

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
        initializedGame.applyGuestRolls(guestRolls)
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

    /// Applies the locally focused dice set to `game`'s own seat, or clears
    /// that seat's table dice entirely when nothing is focused — so
    /// deselecting a dice sheet doesn't leave stale dice sitting on the
    /// table (see `GameTableModel.applyDiceRoll`'s "0 needed" case).
    private func applyCurrentFocusedDiceRoll(to game: GameTableModel) {
        Self.applyFocusedDice(from: root.diceRoot, to: game)
    }

    private static func applyFocusedDice(from diceRoot: DiceRootModel, to game: GameTableModel) {
        guard let focusId = diceRoot.diceGameControllable.gameModel.focusItemIds.first,
              let diceModel = diceRoot.diceGameControllable.gameModel.itemData[focusId] as? DiceModel else {
            game.applyDiceRoll(.empty)
            return
        }
        game.applyDiceRoll(diceModel)
    }

    /// The closure the model stores for `applyFocusedDiceRollForLocalSeat`. Static and capturing
    /// only `game` (weakly) and `diceRoot`: an instance method would capture this view value, whose
    /// `@State` storage holds `game`, closing a retain cycle model → closure → view → state → model.
    private static func focusedDiceHandler(for game: GameTableModel, diceRoot: DiceRootModel) -> () -> Void {
        { [weak game] in
            guard let game else { return }
            applyFocusedDice(from: diceRoot, to: game)
        }
    }

    /// The last shared roll of every player who is not on Vision Pro, the game master's
    /// included, as the dice overlay has it, reduced to the dice the table has: d20 and d6.
    private var guestRolls: [TableGuestRoll] {
        let diceRoot = root.diceRoot.diceGameControllable
        // By the sender's id, not the display name: a player named like the game master is no
        // game master, and two guests with one name keep their own dice.
        return diceRoot.sharedPlayerDice.compactMap { dice -> TableGuestRoll? in
            guard let senderId = diceRoot.playerDiceSenderId(for: dice.id),
                  root.gameModel.isTableGuest(senderId: senderId) else { return nil }
            return TableGuestRoll(
                name: dice.name,
                dice: dice.dice.compactMap { die in
                    guard let isD20 = TableSeatDice.isD20(sides: die.die.max),
                          let value = die.result.last else { return nil }
                    return .init(isD20: isD20, value: value)
                },
                isGameMaster: root.gameModel.isTableGuestMaster(senderId: senderId)
            )
        }
    }

    /// Everything about the currently-focused character-sheet dice set that
    /// should re-mirror it onto the 3D table: which set is focused at all
    /// (so deselecting is also a change, and so is a copy taking its place:
    /// the popover's compare value editor focuses one), its shape — side
    /// count per die, so switching from e.g. "2d20" to "4d6" without rolling
    /// still updates the table — and every rolled result. Changes on every
    /// roll, including a re-roll of the same dice, unlike `focusItemIds`
    /// alone (which only changes when the *selection* changes).
    private var focusedDice: TableFocusedDice? {
        guard let focusId = root.diceRoot.diceGameControllable.gameModel.focusItemIds.first,
              let diceModel = root.diceRoot.diceGameControllable.gameModel.itemData[focusId] as? DiceModel else {
            return nil
        }
        return TableFocusedDice(diceModel)
    }

}

#Preview {
    GameTableView(root: .preview)
}

#endif
