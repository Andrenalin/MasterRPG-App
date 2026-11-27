// @copyright André Trettin

import AudioRPG
import CoreRPG
import Foundation
import os.log

@MainActor
final class MasterController {
    // Strong on purpose: an intentional, temporary cycle GameRoot → GameModel →
    // MasterController → GameRoot that stopGame() breaks by dropping the controllers.
    // `unowned` crashed here when in-flight controller tasks outlived
    // stopGame()/teardown. A strong reference keeps GameRoot alive until the
    // last task finishes.
    let root: GameRoot
    let gameModel: MasterControllerModel
    let asProxy: Bool
    let messagePipeline = GameMessagePipeline()

    /// Chains every `resetPlayers()` call onto the previous one so only a
    /// single broadcast sequence is ever in flight, regardless of which of
    /// `resetPlayers()`'s independent call sites triggered it — the
    /// `messagePipeline`-drained network path, `lostPlayer(for:)` (called
    /// directly on connection loss, bypassing `messagePipeline`), and
    /// `GameRoot.sharingControlActions`'s own, separately-serialized
    /// `scheduleNetworkAction` chain. Without this, `resetPlayers()`'s
    /// several internal `await`s let two independently triggered calls
    /// interleave and each broadcast its own stale roster/map snapshot. See
    /// CODE_AUDIT_10 §3.1.
    ///
    /// Declared here (not `private`) because it is read and written only from
    /// `MasterController+Control.swift`'s `resetPlayers()`/`stop()`, a
    /// different file from this declaration.
    var resetPlayersTask: Task<Void, Never>?
    /// Every `resetPlayers` task that has not finished, so `stop()` cancels the whole chain and not
    /// only the newest link. See CODE_AUDIT_26 §3.7.
    var queuedResetPlayersTasks: [UUID: Task<Void, Never>] = [:]

    /// Bounded per-item retry after `deliverPendingAudio` fails to
    /// prepare a missing player's copy (e.g. a transient export error).
    /// Without this, nothing schedules another attempt unless an unrelated
    /// event (another player's ack, a roster reset) happens to call
    /// `startCompletePendingAudioPlays()` again, and the queued play could
    /// otherwise never reach that player for the rest of the session.
    /// Declared here (not `private`) because it is read and written only
    /// from `MasterController+AudioMessages.swift`, a different file from
    /// this declaration — same rationale as `resetPlayersTask`. See
    /// CODE_AUDIT_Network §5.13.
    var audioPlayRetryTasks: [UUID: Task<Void, Never>] = [:]
    /// Identifies the retry task registered per item, so a finished retry forgets only itself.
    var audioPlayRetryTokens: [UUID: UUID] = [:]
    /// Incremented by every new play, pause and game end (`clearPendingAudioPlays`). A play that
    /// suspended compares it before storing itself as pending. See CODE_AUDIT_29 §3.2.
    var audioPlayGeneration = 0

    /// The audio exports that run, per item, so a second delivery of the same file waits for
    /// the first. Declared here for the same reason as `audioPlayRetryTasks`.
    let audioPackages = SharedWorkCoalescer<UUID, NetworkCodableDataType>()

    /// The delivery of what the pending audio play lacks, and the look-ahead that sends the next
    /// track: both outside the game master's action chain. Declared here for the same reason as
    /// `audioPlayRetryTasks`. See CODE_AUDIT_Audio2 §7.4.
    var audioDeliveryTask: Task<Void, Never>?
    /// The deliveries a joining player's list and a failed import ask for. Each runs in a task of
    /// its own, so an export never holds the serial message pipeline, and none replaces the
    /// delivery of the pending play. See CODE_AUDIT_26 §7.8.
    var audioJoinDeliveryTasks: [UUID: Task<Void, Never>] = [:]
    var audioPrefetchTask: Task<Void, Never>?
    /// The look-ahead that waits for the players still loading the current track, and the task
    /// that lets it go on after `audioPrefetchHold`. See CODE_AUDIT_Game_Photo_Audio §5.1.
    var heldAudioPrefetch: (rootId: UUID, trackId: UUID)?
    var audioPrefetchHoldTask: Task<Void, Never>?

    /// How long a pending audio play waits for the players' receipts before it starts for the
    /// players that are ready. See CODE_AUDIT_Game_Shareplay §5.7.
    var audioPlayDeadline: Duration = .seconds(20)
    /// How long a pending play waits before it is exported and sent again after its delivery
    /// failed. See CODE_AUDIT_17 §3.6.
    var audioPlayRetryDelay: Duration = .seconds(5)
    /// The deadline of each pending play, cancelled with the play.
    var audioPlayDeadlineTasks: [UUID: Task<Void, Never>] = [:]
    /// The play command that is running for the table now, so a player whose file arrives after
    /// the deadline can join it. `nil` after a pause and at the end of the game.
    var runningAudioPlay: NetworkCodableDataType?
    /// The players the running play started without.
    var lateAudioPlayers: Set<UUID> = []

    init(root: GameRoot, asProxy: Bool) {
        self.root = root
        self.asProxy = asProxy
        self.gameModel = MasterControllerModel()

        if asProxy {
            root.networkProxyStore.model.setProxyMasterDelegate(self)
        } else {
            root.networkStore.model.setMasterDelegate(self)
            root.networkStore.model.isAudioPlaylist = { [weak root] id in
                root?.audioRoot.audioGameControllable.isPlaylist(id: id) ?? false
            }
        }
        Logger.networking.debug("MasterController: Init")
    }

    deinit {
        Logger.networking.debug("MasterController: Deinit")
    }
}

// Empty conformance declaration kept in the same file as the class itself — Swift requires a
// class's `Sendable` conformance (inherited here via `MasterNetworkStoreDelegate: Sendable`) to
// be declared alongside the class, even though the actual protocol requirements are implemented
// in `MasterController+NetworkStoreDelegate.swift`.
// DO NOT MOVE OR REMOVE THIS IN A CODE AUDIT: moving it into the other file compiles but warns
// ("Conformance to 'Sendable' must occur in the same source file", an error in a future Swift
// language mode). It looks redundant and is not. (CODE_AUDIT_28 §3.5 got this wrong once.)
extension MasterController: MasterNetworkStoreDelegate {}
