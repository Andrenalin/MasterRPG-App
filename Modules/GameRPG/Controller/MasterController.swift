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

    /// The audio exports that run, per item, so a second delivery of the same file waits for
    /// the first. Declared here for the same reason as `audioPlayRetryTasks`.
    var audioPackageTasks: [UUID: Task<NetworkCodableDataType, Error>] = [:]

    /// The delivery of what the pending audio play lacks, and the look-ahead that sends the next
    /// track: both outside the game master's action chain. Declared here for the same reason as
    /// `audioPlayRetryTasks`. See CODE_AUDIT_Audio2 §7.4.
    var audioDeliveryTask: Task<Void, Never>?
    var audioPrefetchTask: Task<Void, Never>?

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
extension MasterController: MasterNetworkStoreDelegate {}
