// @copyright André Trettin

import CoreRPG
import Foundation
import os.log

// MARK: - Slot

/// One place in the Journal: the slot of a module, or the slot of the audio playlists.
///
/// The Journal holds one attachment per slot, and a new publication replaces the one before it.
/// An audio playlist is shown together with its first track, which would replace it before every
/// player has loaded it: a playlist has a slot of its own.
struct SharePlayJournalSlot: Hashable, Sendable {
    let module: NetworkModules
    let isPlaylist: Bool

    init(_ module: NetworkModules, isPlaylist: Bool = false) {
        self.module = module
        self.isPlaylist = isPlaylist
    }

    var token: String {
        isPlaylist ? "\(module.token) PLAYLIST" : module.token
    }
}

// MARK: - Publication policy & admission

enum SharePlayJournalPublicationPolicy: Equatable, Sendable {
    /// Every accepted publication is significant and stays in FIFO order. This
    /// is used for answers such as Audio/Weather, where dropping one item could
    /// leave a participant without the requested bytes.
    case fifo
    /// Only the newest pending presentation for a module is significant. An
    /// active publication is allowed to finish, while older pending
    /// presentations are replaced before they retain and publish stale bytes.
    case latestWins
}

enum SharePlayJournalPublicationAdmission: Equatable, Sendable {
    case enqueued
    case replacedPending
    case rejected
}

// MARK: - Publication completion bookkeeping

@MainActor
final class SharePlayJournalPublicationCompletion {
    private var isFinished = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isFinished else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func finish() {
        guard !isFinished else { return }
        isFinished = true
        let currentWaiters = waiters
        waiters = []
        currentWaiters.forEach { $0.resume() }
    }
}

// MARK: - Enqueue result

@MainActor
struct SharePlayJournalPublicationEnqueueResult {
    let admission: SharePlayJournalPublicationAdmission
    private let completion: SharePlayJournalPublicationCompletion

    init(
        admission: SharePlayJournalPublicationAdmission,
        completion: SharePlayJournalPublicationCompletion
    ) {
        self.admission = admission
        self.completion = completion
    }

    /// Test/debug synchronization for the accepted publication. Replaced,
    /// rejected, and session-cancelled operations complete immediately.
    var value: Void {
        get async {
            await completion.wait()
        }
    }
}
