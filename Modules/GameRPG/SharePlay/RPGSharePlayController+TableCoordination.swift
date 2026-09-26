// @copyright André Trettin

#if os(visionOS)
import Combine
import CoreRPG
import Foundation
import GroupActivities
import os.log

// MARK: - SharePlay Coordination Extension

extension RPGSharePlayController {
    /// Single-player seating: synchronous because there is no coordinator to race.
    @MainActor
    func setupLocalSeatAssignment(gameTableModel: GameTableModel) {
        Logger.sharePlay.debug("Setting up single-player seating")
        gameTableModel.assignSeatsForSharePlay(groupSession: nil, isMaster: gameModel?.gameConfig.isMaster ?? false)
        // See `GameObserver.canAutoClaimSeat`'s own doc.
        gameTableModel.observer.canAutoClaimSeat = true
    }

    @MainActor
    func setupSeatAssignment(gameTableModel: GameTableModel) async {
        let isMaster = gameModel?.gameConfig.isMaster ?? false
        guard let groupSession else {
            setupLocalSeatAssignment(gameTableModel: gameTableModel)
            return
        }

        Logger.sharePlay.debug("Setting up SharePlay seat assignment (isMaster: \(isMaster, privacy: .public))")
        let masterId = await masterParticipantId(in: groupSession, isMaster: isMaster)
        // The session may have been replaced while the delegate lookup suspended.
        guard self.groupSession?.id == groupSession.id else { return }
        gameTableModel.assignSeatsForSharePlay(
            groupSession: groupSession,
            isMaster: isMaster,
            masterParticipantId: masterId
        )
        // The real, coordinated claim above has now been submitted (this method only
        // ever runs after `coordinateWithSession(_:)` has attached — see both call
        // sites' own docs), so `GameObserver`'s fallback re-claim is safe from here on.
        gameTableModel.observer.canAutoClaimSeat = true

        let seatTask = Task { [weak self] in
            for await _ in groupSession.$activeParticipants.values {
                guard let self else { return }
                let isMaster = self.gameModel?.gameConfig.isMaster ?? false
                let masterId = await self.masterParticipantId(in: groupSession, isMaster: isMaster)
                guard !Task.isCancelled, self.groupSession?.id == groupSession.id else { return }
                gameTableModel.updateSeatsForParticipantChange(
                    groupSession: self.groupSession,
                    isMaster: isMaster,
                    masterParticipantId: masterId
                )
            }
        }
        trackSessionTask(seatTask, key: Self.seatObservationTaskKey)
    }

    /// The game master's participant id: this device's own on the master, or the participant a
    /// player device has pinned as master (`nil` until the master's first broadcast binds it).
    private func masterParticipantId(
        in groupSession: GroupSession<RPGActivity>,
        isMaster: Bool
    ) async -> UUID? {
        if isMaster { return groupSession.localParticipant.id }
        return await delegate?.pinnedMasterParticipantId(
            among: groupSession.activeParticipants.map(\.id)
        )
    }
}

private extension RPGSharePlayController {
    static let seatObservationTaskKey = UUID()
}

#endif
