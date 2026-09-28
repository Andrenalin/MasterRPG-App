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

@Observable @MainActor
final class GameTableModel: Sendable {
    let renderer: GameRenderer
    let setup: GameSetup

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
            replaceFogOfWarTask()
        }
    }
    var lastPinScale: CGFloat = 1
    var lastHexScale: Double = 0
    var lastIsHexMap: Bool = false

    /// The local player's own pin id (== the player's game id); nil on the master.
    var playerPinId: UUID?
    /// Set by `assignSeatsForSharePlay` to the party's player count whenever there are (or may be)
    /// more players than the table's non-master seats (`PlayerSeat.seatPoses.count - 1`), meaning
    /// this device's seat, and that seat's dice pool, may be shared with another player. `nil` when
    /// every player has an exclusive seat. Surfaced by `GameTableView`.
    var sharedSeatPlayerCount: Int?
    /// The game master's local menu selection. Highlighting is intentionally
    /// not represented here because multiple shared pins may be highlighted.
    var selectedPinId: UUID?
    var selectedPin: MapPinModel?
    var pinMenuAttachment: Entity?
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
    /// Signature of every value that affects the rendered board texture.
    /// Pin-only mapState messages can then skip a full fog recomposite.
    var fogSignature: Int?
    /// Bumped whenever a board render starts or the board is cleared, so a slow off-main render
    /// that a newer request has superseded is discarded instead of applied.
    var boardRenderGeneration = 0

    init(mapRoot: MapRootModel, photoRoot: PhotoRootModel) {
        self.mapRoot = mapRoot
        self.photoRoot = photoRoot

        renderer = GameRenderer()
        setup = GameSetup(root: renderer.root)

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

extension Logger {
    static let gameTable = Logger(subsystem: subsystem, category: "GameTable")
}

#endif
