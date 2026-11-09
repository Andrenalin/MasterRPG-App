// @copyright André Trettin

import CoreRPG
import Foundation
import GroupActivities
import os.log

enum SharePlayConnectionState: Equatable, Sendable {
    case inactive
    case waiting
    case joined
    case disconnected
}

/// Tracks transport participants independently of in-game player identities.
///
/// `Participant.id` is the address used by `GroupSessionMessenger`; it is not
/// the UUID a player announces later in `GameSenderModel`. Keeping those two
/// identities separate lets the master physically target an initial replay
/// before the player's normal join handshake has completed.
struct SharePlayParticipantTracker: Sendable {
    struct Change: Equatable, Sendable {
        let added: Set<UUID>
        let removed: Set<UUID>
    }

    private var activeRemoteParticipantIds: Set<UUID> = []
    private var replayedParticipantIds: Set<UUID> = []

    mutating func sessionDidJoin(
        activeParticipantIds: Set<UUID>,
        localParticipantId: UUID
    ) -> Set<UUID> {
        let remoteParticipantIds = activeParticipantIds.subtracting([localParticipantId])
        activeRemoteParticipantIds = remoteParticipantIds
        replayedParticipantIds.formIntersection(remoteParticipantIds)

        let added = remoteParticipantIds.subtracting(replayedParticipantIds)
        replayedParticipantIds.formUnion(added)
        return added
    }

    mutating func participantsChanged(
        activeParticipantIds: Set<UUID>,
        localParticipantId: UUID,
        sessionIsJoined: Bool
    ) -> Change {
        let remoteParticipantIds = activeParticipantIds.subtracting([localParticipantId])
        let removed = activeRemoteParticipantIds.subtracting(remoteParticipantIds)
        activeRemoteParticipantIds = remoteParticipantIds
        replayedParticipantIds.subtract(removed)

        guard sessionIsJoined else {
            return Change(added: [], removed: removed)
        }

        let added = remoteParticipantIds.subtracting(replayedParticipantIds)
        replayedParticipantIds.formUnion(added)
        return Change(added: added, removed: removed)
    }

    /// Captures every old transport participant before a session reset clears
    /// the tracker. The connection event is deliberately last so participant-
    /// scoped availability is removed before the player performs its complete
    /// lost-master reset.
    mutating func drainSessionTeardownEvents() -> [SharePlaySessionTeardownEvent] {
        let participantEvents = activeRemoteParticipantIds
            .sorted(by: { $0.uuidString < $1.uuidString })
            .map(SharePlaySessionTeardownEvent.lostParticipant)
        reset()
        return participantEvents + [.lostConnection]
    }

    mutating func reset() {
        activeRemoteParticipantIds = []
        replayedParticipantIds = []
    }
}
