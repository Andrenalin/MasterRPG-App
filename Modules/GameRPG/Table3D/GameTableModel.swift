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
    /// hang forever if the view is dismissed before any frame renders. See CODE_AUDIT §3.1.
    @ObservationIgnored
    var pendingRenderWaitContinuation: CheckedContinuation<Void, Never>?
    @ObservationIgnored
    var pendingRenderWaitSubscription: (any Cancellable)?

    /// Set by `applyDiceRoll` whenever the locally focused dice set has more
    /// dice of a type than this seat has table slots for (currently
    /// `GameSetup.maxDicePerType`, 6, per type — see `playerD20Ids`/
    /// `playerD6Ids`), or dice of a type the table has no mesh for at all
    /// (only d20 and d6 are supported); `nil` when the last set mirrored
    /// entirely. The count of dice that could not be mirrored onto the
    /// table, so `GameTableView` can surface a "N results not shown on
    /// table" notice instead of the drop being silent. See CODE_AUDIT §5.1.
    var diceOverflowCount: Int?

    /// Set by `GameTableView` to its own `applyCurrentFocusedDiceRoll(to:)`, so
    /// `GameObserver.playerChangedSeats` can re-run it once the local player's own
    /// seat claim actually lands. A player's seat claim (`claimSeat`/`claimAnySeat`)
    /// is itself a synced TabletopKit action — in a SharePlay session it's only
    /// confirmed into the snapshot asynchronously, same as any other equipment
    /// update — so `applyDiceRoll`'s `localSeat` lookup can still read `nil` at the
    /// moment `GameTableView` first calls it (right after `setupSeating`). Without a
    /// later retry, that seat's dice would then never get placed or shown at all
    /// until the next roll or focus change happened to call `applyDiceRoll` again.
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

    /// Defaults to true: the volumetric table is inherently already shared
    /// once it's open (unlike the 2D map, there's no private-editing mode to
    /// opt out of), but the game master can still pause broadcasting
    /// toolbar-driven edits (added pins, pointer moves) if they want to.
    var isStreaming = true
    /// Local GM preview of how the board reads in another role, same as the
    /// 2D map's display mode. Purely a rendering lens — it never changes
    /// what's actually shared; see `renderIsGameMaster`.
    var displayMode: MapDisplayMode = .master {
        didSet {
            guard oldValue != displayMode else { return }
            replaceFogOfWarTask(isGameMaster: isGameMaster)
        }
    }
    var lastPinScale: CGFloat = 1
    var lastHexScale: Double = 0
    var lastIsHexMap: Bool = false

    /// The local player's own pin id (== the player's game id); nil on the master.
    var playerPinId: UUID?
    /// Set by `assignSeatsForSharePlay` (see `GameEquipment.swift`) to the
    /// total player count whenever the party has more players than the
    /// table has non-master seats (currently 2; the 4th table side is
    /// reserved for the shared die/deck, not a seat) — meaning this device's
    /// seat, and the seat's 2 `Die20` equipment ids, may be shared with
    /// another player. `nil` when every player has an exclusive seat.
    /// Deliberately not a precise "shared with N others" count: which
    /// specific players share a seat can't be determined locally (SharePlay
    /// participants carry no host/role marker to exclude the master from
    /// the ranking — see the method's doc comment), only that sharing is
    /// happening somewhere. See CODE_AUDIT §5.2.
    var sharedSeatPlayerCount: Int?
    /// The game master's local menu selection. Highlighting is intentionally
    /// not represented here because multiple shared pins may be highlighted.
    var selectedPinId: UUID?
    var selectedPin: MapPinModel?
    var pinMenuAttachment: Entity?
    /// Resolved once per drag gesture by `pinDragChanged(pinId:position:)` and cleared by
    /// `pinDragEnded(pinId:position:)`, so the per-tick drag path doesn't re-scan `pinPawns` on
    /// every delta. See CODE_AUDIT §7.3.
    var cachedDragPawn: (pinId: UUID, pawn: PinPawn)?
    var currentPhotoId: UUID?
    var currentPhotoVersion: Int?
    var pendingPinPhotoIds: [UUID: UUID] = [:]
    /// Tracks the `Task` spawned per pin by `syncPawnsWithMapPins()` so a
    /// pin whose photo load is superseded (or the whole model torn down) can
    /// have its in-flight load cancelled instead of running to completion
    /// with no one left to apply the result. See CODE_AUDIT §3.5.
    var pendingThumbnailTasks: [UUID: Task<Void?, Never>] = [:]
    /// Tracks the in-flight `updateFogOfWar` `Task`, created and replaced only through
    /// `replaceFogOfWarTask(isGameMaster:)` so every fog-affecting entry point — a
    /// continuous drag (`panViewport(by:)`), `displayMode`'s `didSet`, room toggle/focus,
    /// "show/hide all", and a map change — shares one cancel-then-replace point instead of
    /// racing each other with independently-awaited direct calls. See CODE_AUDIT §5.5/§3.3.
    var fogOfWarTask: Task<Void, Never>?
    /// Tracks the in-flight `performMapChange` `Task`, created and replaced only through
    /// `replaceMapChangeTask(isGameMaster:)`. The view's initial-appear `.task` and its
    /// `.task(id:)` map-selection watcher are two *independent* Task hierarchies on this
    /// same model instance, so SwiftUI's automatic cancel-on-id-change only protects
    /// re-entrant calls within one of them — this choke point protects across both,
    /// mirroring `fogOfWarTask` above. See CODE_AUDIT_9 §3.2.
    var mapChangeTask: Task<Void, Never>?
    /// Signature of every value that affects the rendered board texture.
    /// Pin-only mapState messages can then skip a full fog recomposite.
    var fogSignature: Int?

    /// A local, per-client pan gesture value (dragging the map surface while
    /// a room is focused — see `GameTableView.viewportPanGesture`) that
    /// `boardFocusRect` no longer applies to anything: the 3D board never
    /// crops/zooms into a focused room (only the 2D map does), so this stays
    /// at whatever the gesture last wrote but has no rendering effect. Kept
    /// so the gesture itself doesn't need touching. Not networked.
    var manualViewportOffset: CGPoint = .zero
    /// The room id `manualViewportOffset` was last computed against, used
    /// only to detect a focus change mid-drag (see `panViewport(fromTableStart:toTableEnd:expectedRoomId:)`).
    var lastFocusedRoomId: UUID?

    @MainActor
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
