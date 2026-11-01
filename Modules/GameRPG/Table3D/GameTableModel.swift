// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import CoreRPG
import Foundation
import MapRPG
import PhotoRPG
import RealityKit
import SwiftUI
import os.log

#if os(visionOS)
import Combine
import DiceRPG
import TabletopKit
#endif

// The table's scene types: the TabletopKit volume on visionOS, the camera-based table on iOS and
// macOS. Distinct class names, so a cross-platform edit can't confuse the two.
// See CODE_AUDIT_19 §9.9.
#if os(visionOS)
typealias TableGameSetup = GameSetup
typealias TableGameRenderer = GameRenderer
#else
typealias TableGameSetup = PortableGameSetup
typealias TableGameRenderer = PortableGameRenderer
#endif

@Observable @MainActor
final class GameTableModel: Sendable {
    let renderer: TableGameRenderer
    let setup: TableGameSetup

#if os(visionOS)
    let tabletopGame: TabletopGame
    let observer: GameObserver
    /// The `(session, seat)` pair most recently submitted via `claimSeat` in
    /// `assignSeatsForSharePlay` — see that method's own `claimSeatIfNeeded`
    /// helper for why a redundant identical claim needs to be suppressed,
    /// not just deduplicated for its own sake: `GroupSession.
    /// $activeParticipants` replays its *current* roster immediately when
    /// `setupSeatAssignment`'s own participant-change observation loop
    /// starts, firing `updateSeatsForParticipantChange` again right after the
    /// initial claim even though nothing actually changed. Resubmitting
    /// `claimSeat` for the same seat before the first request has been
    /// reconciled through TabletopKit's SharePlay sync layer corrupts the
    /// shared-simulation role/template negotiation and crashes with "Could
    /// not find static equipment with identifier: ...".
    var lastRequestedSeatAssignment: (sessionId: UUID, seatId: TableSeatIdentifier)?

    // State backing the visionOS-only extensions in GameTableModel+RenderingReadiness.swift,
    // GameTableModel+Seating.swift and GameTableModel+Dice.swift. Kept here — rather than in
    // those extensions — because Swift extensions cannot declare stored properties.

    /// Pending continuation and RealityKit subscription from `waitForFirstRenderedFrame()`.
    /// Torn down either by the scene's own next `SceneEvents.Update` or by cancellation of the
    /// awaiting `Task` — an uncancellable wait here would otherwise leak the subscription and
    /// hang forever if the view is dismissed before any frame renders.
    @ObservationIgnored
    var pendingRenderWaitContinuation: CheckedContinuation<Void, Never>?
    @ObservationIgnored
    var pendingRenderWaitSubscription: (any Cancellable)?

    /// The number of focused dice `applyDiceRoll` could not mirror onto the table: more of a type
    /// than a seat has slots for (`GameSetup.maxDicePerType`), or a type with no mesh (only d20 and
    /// d6 exist). `nil` when the whole set mirrored. Surfaced by `GameTableView`.
    var diceOverflowCount: Int?

    /// The dice groups — a seat's dice, or one guest's — that have been rolled and lie still, so
    /// their result popover is up. This device's own seat is among them before a roll, too. Kept up to date by `updateDiceResults(snapshot:visualState:)`
    /// on every frame.
    var shownDiceGroups: Set<TableDiceGroup> = []
    /// The dice of the players without a table, at the guest seat: who has which dice of that
    /// seat's pool. Every device derives it from the rolls it knows (`applyGuestRolls(_:)`).
    var guestGroups: [TableGuestDice.Group] = []
    /// The players sitting at each seat, by the name their game messages carry; the dice
    /// overlay lists a player's shared dice under the same name. Learned from SharePlay (see
    /// `RPGSharePlayController.refreshSeatPlayerNames()`); several players can share a seat.
    var seatPlayerNames: [TableSeatIdentifier: [String]] = [:]
    /// Where each dice group's result popover stands.
    @ObservationIgnored
    var diceResultPopovers: [TableDiceGroup: TablePopoverAnchor] = [:]
    /// Since when each group's dice have been lying still with the same values.
    @ObservationIgnored
    var diceRestingSince: [TableDiceGroup: (values: [Int], start: ContinuousClock.Instant)] = [:]
    /// The dice sheet `applyDiceRoll` last mirrored onto the local seat, and which of its dice
    /// each table die stands for, so a die tossed by hand can be rolled by its sheet.
    @ObservationIgnored
    var mirroredSheet: (diceId: UUID, dieIds: [EquipmentIdentifier: UUID])?
    /// The value the sheet gave each die tossed by hand. `applyDiceRoll` leaves such a die to
    /// its toss for as long as the sheet still has that value, instead of lining it up again.
    @ObservationIgnored
    var handTossedDice: [EquipmentIdentifier: Int] = [:]
    /// The dice module, which rolls a die tossed by hand.
    @ObservationIgnored
    weak var diceRoot: DiceRootModel?

    /// Re-mirrors the focused dice set once the local player's seat claim lands. A claim is a
    /// synced TabletopKit action that is only confirmed asynchronously, so `applyDiceRoll` can
    /// find no `localSeat` when `GameTableView` first calls it; `GameObserver.playerChangedSeats`
    /// runs this afterwards. The model owns this closure, so it must never capture the view (a
    /// SwiftUI view value holds `@State` storage that holds this model — a retain cycle).
    var applyFocusedDiceRollForLocalSeat: (() -> Void)?
#endif

    // References to root models for accessing game controllers.
    let mapRoot: MapRootModel
    let photoRoot: PhotoRootModel

    var currentMapId: UUID?
    var currentMapImage: AKImage?
    var currentMapDegrees: Double = 0
    var networkActions: NetworkActions?
    var isGameMaster = false

    // MARK: - Shared toolbar state (`GameToolBarSession`)

    /// The hex scale the toolbar's slider shows while it is dragged; applied to the map by
    /// `commitHexScale()` when the slider is released. See CODE_AUDIT_21 §5.19.
    var pendingHexScale: Double?

    /// The game toolbar's "Share Map" state, shared with the 2D map through the map root, so
    /// pausing broadcasting of toolbar-driven edits (added pins, pointer moves) in one mode
    /// pauses it in the other. On by default.
    var isStreaming: Bool {
        get { mapRoot.rootModel.isMapStreaming }
        set { mapRoot.rootModel.isMapStreaming = newValue }
    }
    /// Local GM preview of how the board reads in another role, same as the
    /// 2D map's display mode. Purely a rendering lens — it never changes
    /// what's actually shared; see `renderIsGameMaster`.
    var displayMode: MapDisplayMode = .master {
        didSet {
            guard oldValue != displayMode else { return }
            if isGameMaster {
                // Kept on the map root so a 2D↔3D toggle keeps it. See CODE_AUDIT_19 §5.17.
                mapRoot.rootModel.gameDisplayMode = displayMode
            }
            replaceFogOfWarTask()
        }
    }
    var lastPinScale: CGFloat = 1
    var lastHexScale: Double = 0
    var lastIsHexMap: Bool = false

    /// The local player's own pin id (== the player's game id); nil on the master.
    var playerPinId: UUID?
    /// Set by `assignSeatsForSharePlay` to the party's player count whenever there are (or may be)
    /// more players than the table's non-master seats (`PlayerSeat.playerSeatCount`), meaning
    /// this device's seat, and that seat's dice pool, may be shared with another player. `nil` when
    /// every player has an exclusive seat. Surfaced by `GameTableView`.
    var sharedSeatPlayerCount: Int?
    /// The game master's local menu selection. Highlighting is intentionally
    /// not represented here because multiple shared pins may be highlighted.
    var selectedPinId: UUID?
    var selectedPin: MapPinModel?
    /// Where the pin action popover stands as a RealityKit attachment, on visionOS.
    let pinMenuPopover = TablePopoverAnchor(name: "PinMenuAnchor")
#if !os(visionOS)
    /// The selected pin's frame in the table view, which the pin action popover points at.
    /// Recomputed every rendered frame, because the system's camera controls move the camera
    /// without telling SwiftUI.
    var pinMenuSource: TablePinMenuSource?
#endif
    /// The pin whose photo popover is open on this table, and that pin's state. Local
    /// presentation state, like the pin menu selection: a double tap opens it on this device
    /// only, the game master's shared flag (`isZoom`) opens it on every device.
    var photoPinId: UUID?
    var photoPin: MapPinModel?
    /// Pins whose photo the game master was showing at the last sync, so that only a change of
    /// the flag opens or closes the popover. See `MapPinPhotoSharing`.
    var sharedPhotoPinIds: Set<UUID> = []
    /// Where the photo popover stands as a RealityKit attachment, on visionOS.
    let pinPhotoPopover = TablePopoverAnchor(name: "PinPhotoAnchor")
#if !os(visionOS)
    /// The photo pin's frame in the table view, which the photo popover points at.
    var pinPhotoSource: TablePinMenuSource?
#endif
    /// Resolved once per drag gesture by `pinDragChanged(pinId:position:)` and cleared by
    /// `pinDragEnded(pinId:position:)`, so the per-tick drag path doesn't re-scan `pinPawns`.
    var cachedDragPawn: (pinId: UUID, pawn: PinPawn)?
    var currentPhotoId: UUID?
    var currentPhotoVersion: Int?
    /// The photo each pin is currently loading a thumbnail for.
    var pendingPinPhotoIds: [UUID: UUID] = [:]
    /// The photo whose thumbnail load last failed for a pin; not retried until the pin's photo changes.
    var failedPinPhotoIds: [UUID: UUID] = [:]
    /// Tracks the `Task` spawned per pin by `syncPawnsWithMapPins()` so a pin whose photo load is
    /// superseded (or the whole model torn down) can have its in-flight load cancelled.
    var pendingThumbnailTasks: [UUID: Task<Void?, Never>] = [:]
    /// Tracks the in-flight `updateFogOfWar` `Task`, created and replaced only through
    /// `replaceFogOfWarTask(isGameMaster:)` so every fog-affecting entry point — `displayMode`'s
    /// `didSet`, room toggle/focus, "show/hide all", a map change, a remote map update — shares one
    /// cancel-then-replace point instead of racing each other.
    var fogOfWarTask: Task<Void, Never>?
    /// Tracks the in-flight `performMapChange` `Task`, created and replaced only through
    /// `replaceMapChangeTask(isGameMaster:)`. The view's initial-appear `.task` and its
    /// `.task(id:)` map-selection watcher are independent Task hierarchies on this model, so
    /// SwiftUI's automatic cancel-on-id-change only protects re-entrant calls within one of them;
    /// this choke point protects across both.
    var mapChangeTask: Task<Void, Never>?
    /// The number of content updates (`sendMapContent(for:force:)`, ordered on the map root's
    /// shared chain) still pending per map. While one is pending for a map, plain state
    /// broadcasts for it are left to the chain, which ends with a live map state, so they can no
    /// longer overtake the content update. See CODE_AUDIT_19 §3.12.
    @ObservationIgnored
    var pendingMapContentBroadcasts: [UUID: Int] = [:]
    /// Signature of every value that affects the rendered board texture.
    /// Pin-only mapState messages can then skip a full fog recomposite.
    var fogSignature: Int?
    /// Bumped whenever a board render starts or the board is cleared, so a slow off-main render
    /// that a newer request has superseded is discarded instead of applied.
    var boardRenderGeneration = 0

    init(mapRoot: MapRootModel, photoRoot: PhotoRootModel) {
        self.mapRoot = mapRoot
        self.photoRoot = photoRoot

        renderer = TableGameRenderer()
        setup = TableGameSetup(root: renderer.root)

#if os(visionOS)
        tabletopGame = TabletopGame(tableSetup: setup.setup)
        observer = GameObserver(tabletop: tabletopGame, renderer: renderer)
        tabletopGame.addObserver(observer)
        tabletopGame.addRenderDelegate(renderer)
#endif

        renderer.game = self
        resetGame()
    }

    isolated deinit {
        pendingThumbnailTasks.values.forEach { $0.cancel() }
        fogOfWarTask?.cancel()
        mapChangeTask?.cancel()
#if os(visionOS)
        tabletopGame.removeObserver(observer)
        tabletopGame.removeRenderDelegate(renderer)
#endif
    }
}

#if os(visionOS)
/// A set of dice on the table with a result popover of its own.
enum TableDiceGroup: Hashable {
    /// A seat's own dice.
    case seat(TableSeatIdentifier)
    /// The dice of one guest at the guest seat: an index into `GameTableModel.guestGroups`.
    case guest(Int)
}
#endif

extension Logger {
    static let gameTable = Logger(subsystem: subsystem, category: "GameTable")
}

#endif
