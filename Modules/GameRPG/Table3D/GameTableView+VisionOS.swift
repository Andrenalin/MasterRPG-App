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
    /// Backs `WindowOpenButton` and `GameTableSideMenu` (the game seat panel,
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
                    if let diceBag = attachments.entity(for: GameDiceBagPopover.attachmentId) {
                        loadedGame.registerDiceBag(diceBag)
                    }
                    for index in 0 ..< GameTableModel.maxRemovePopovers {
                        if let remove = attachments.entity(for: GameDiceRemovePopover.attachmentId(at: index)) {
                            loadedGame.registerDiceRemove(remove, at: index)
                        }
                    }
                    for panel in TableSeatPanel.allCases {
                        if let seatPanel = attachments.entity(for: panel.attachmentId) {
                            loadedGame.registerSeatPanel(seatPanel, for: panel)
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
                    loadedGame.updateSeatPanelPositions()
                } attachments: {
                    Attachment(id: TableSeatPanel.dock.attachmentId) {
                        GameSeatDockPanel(game: loadedGame)
                            .environment(gameScreenModel)
                    }
                    ForEach(TableSeatGroup.allCases, id: \.self) { group in
                        Attachment(id: group.panel.attachmentId) {
                            GameSeatGroupPanel(root: root, game: loadedGame, group: group, gameScreenModel: gameScreenModel)
                        }
                    }
                    Attachment(id: GameDiceBagPopover.attachmentId) {
                        GameDiceBagPopover(
                            root: root,
                            game: loadedGame,
                            diceDisplayModel: diceDisplayModel,
                            appGameStateModel: appGameStateModel,
                            networkActions: networkActions
                        )
                    }
                    ForEach(0 ..< GameTableModel.maxRemovePopovers, id: \.self) { index in
                        Attachment(id: GameDiceRemovePopover.attachmentId(at: index)) {
                            GameDiceRemovePopover(
                                root: root,
                                game: loadedGame,
                                diceDisplayModel: diceDisplayModel,
                                appGameStateModel: appGameStateModel,
                                index: index
                            )
                        }
                    }
                    Attachment(id: TableSeatPanel.mapDock.attachmentId) {
                        GameSeatMapDockPanel(root: root, game: loadedGame)
                    }
                    Attachment(id: TableSeatPanel.map.attachmentId) {
                        GameSeatMapPanel(root: root, game: loadedGame, gameScreenModel: gameScreenModel)
                    }
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
        // The dice edit mode: the dice bag and the remove popovers stand over the seat's dice.
        .onChange(of: diceDisplayModel.isEditing, initial: true) { _, isEditing in
            game?.setDiceEditing(isEditing)
        }
        .onChange(of: focusedDice, initial: false) { _, _ in
            guard let game else { return }
            applyCurrentFocusedDiceRoll(to: game)
        }
        // The players without a table — the game master too, when not on Vision Pro — have no
        // dice of their own here: their shared rolls are shown at the guest seat. See `GameTableModel.applyGuestRolls(_:)`.
        .onChange(of: guestRolls, initial: false) { _, rolls in
            game?.applyGuestRolls(rolls)
        }
        // The dice keep the color their set has, on every seat: see `GameTableModel.dieColors`.
        .onChange(of: dieColors, initial: false) { _, colors in
            game?.applyDieColors(colors)
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
            game?.detachSeatPanels()
            game?.detachDiceEditing()
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
            game.applyDieColors(dieColors)
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
        initializedGame.applyDieColors(dieColors)
    }

    /// Creates `activityManager`, which calls `tabletopGame.coordinateWithSession(_:)` once a
    /// SharePlay session exists.
    ///
    /// Called from a `.task` chained onto the already-mounted `RealityView`/`.tabletopGame(...)`
    /// view, not from `initializeGameIfNeeded()`: the join replays the master's equipment against
    /// the scene TabletopKit's system attaches on mount, and joining before that mount failed with
    /// "Could not find static equipment with identifier: ...". `game` is set asynchronously, so
    /// the mount is not guaranteed to have happened when it is set.
    ///
    /// Guarded on `activityManager == nil`: the `.task` re-fires when the RealityView reappears,
    /// and coordinating an already-coordinated game is neither needed nor safe.
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
    /// included, as the dice overlay has it, reduced to the dice the table has: d20, d12, d10, d8, d6, d4 and d3.
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
                    guard let kind = TableDieKind(sides: die.die.max),
                          let value = die.result.last else { return nil }
                    return .init(kind: kind, value: value, colorCode: die.colorCode)
                },
                isGameMaster: root.gameModel.isTableGuestMaster(senderId: senderId),
                senderId: senderId
            )
        }
    }

    /// The d6 color of every pool slot, as the sets this device knows have it.
    private var dieColors: TableDieColors {
        guard let game else { return TableDieColors() }
        let diceRoot = root.diceRoot.diceGameControllable
        let focused = diceRoot.gameModel.focusItemIds.first
            .flatMap { diceRoot.gameModel.itemData[$0] as? DiceModel }
        return game.dieColors(focused: focused, shared: diceRoot.sharedPlayerDice)
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
