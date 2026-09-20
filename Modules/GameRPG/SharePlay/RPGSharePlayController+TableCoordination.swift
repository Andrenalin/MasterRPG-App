// @copyright André Trettin

#if os(visionOS)
import Combine
import Foundation
@preconcurrency import GroupActivities
import os.log

// MARK: - SharePlay Coordination Extension

extension RPGSharePlayController {
    @MainActor
    func setupSeatAssignment(gameTableModel: GameTableModel) {
        let isMaster = gameModel?.gameConfig.isMaster ?? false
        guard let groupSession else {
            Logger.sharePlay.debug("Setting up single-player seating")
            gameTableModel.assignSeatsForSharePlay(groupSession: nil, isMaster: isMaster)
            // No coordinator to race here — see `GameObserver.canAutoClaimSeat`'s own doc.
            gameTableModel.observer.canAutoClaimSeat = true
            return
        }

        Logger.sharePlay.debug("Setting up SharePlay seat assignment (isMaster: \(isMaster, privacy: .public))")
        gameTableModel.assignSeatsForSharePlay(groupSession: groupSession, isMaster: isMaster)
        // The real, coordinated claim above has now been submitted (this method only
        // ever runs after `coordinateWithSession(_:)` has attached — see both call
        // sites' own docs), so `GameObserver`'s fallback re-claim is safe from here on.
        gameTableModel.observer.canAutoClaimSeat = true

        let seatTask = Task { [weak self] in
            for await _ in groupSession.$activeParticipants.values {
                guard let self else { return }
                let isMaster = self.gameModel?.gameConfig.isMaster ?? false
                gameTableModel.updateSeatsForParticipantChange(groupSession: self.groupSession, isMaster: isMaster)
            }
        }
        trackSessionTask(seatTask, key: Self.seatObservationTaskKey)
    }
}

private extension RPGSharePlayController {
    static let seatObservationTaskKey = UUID()
}

#endif
