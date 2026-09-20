// @copyright André Trettin

#if os(visionOS)
import CoreRPG
import Foundation
@preconcurrency import GroupActivities
import TabletopKit
import os.log

extension GameTableModel {
    // MARK: - Seating & Space Setup

    /// Called when the 3D table view appears to set up seating.
    ///
    /// When a SharePlay session is active, the seat claim is deliberately *not* made here: it is
    /// made by `RPGSharePlayController.setup(tabletopGame:gameTableModel:)`, chained after
    /// `tabletopGame.coordinateWithSession(_:)`. `claimSeat`/`claimAnySeat` are synchronized
    /// TabletopKit actions, and submitting one before the network coordinator is attached leaves a
    /// joining player's claim unsynced against the master's running session, which crashes with
    /// "Could not find static equipment with identifier: ...". Only the no-session case claims a
    /// seat directly here; see `GameObserver.canAutoClaimSeat` for the matching guard.
    func setupSeating(sharePlayController: RPGSharePlayController) {
        let isMaster = sharePlayController.gameModel?.gameConfig.isMaster ?? false
        observer.isMaster = isMaster
        if sharePlayController.isActive, sharePlayController.groupSession != nil {
            Logger.sharePlay.debug("Setting up seating with SharePlay — seat claim deferred until coordinateWithSession(_:) attaches")
        } else {
            Logger.sharePlay.debug("Setting up seating for single-player")
            observer.canAutoClaimSeat = true
            tabletopGame.claimAnySeat()
        }
    }

    /// This device's own seat, however it was claimed. Read from TabletopKit's synchronized seat
    /// state so it stays correct even if seating changes later.
    var localSeat: TableSeatIdentifier? {
        var result: TableSeatIdentifier?
        tabletopGame.withCurrentSnapshot { snapshot in
            result = snapshot.seat(of: PlayerSeat.self, for: tabletopGame.localPlayer)?.0.id
        }
        return result
    }
}

// MARK: - SharePlay Seat Assignment

extension GameTableModel {
    /// Submits `claimSeat` only if this exact `(session, seat)` pair hasn't been requested yet.
    /// `GroupSession.$activeParticipants` replays its current roster when the observation loop
    /// starts, and resubmitting `claimSeat` for the same seat before the first request has
    /// reconciled through TabletopKit's SharePlay sync corrupts its role/template negotiation.
    private func claimSeatIfNeeded(_ seatId: TableSeatIdentifier, sessionId: UUID) {
        guard lastRequestedSeatAssignment?.sessionId != sessionId
            || lastRequestedSeatAssignment?.seatId != seatId
        else { return }
        lastRequestedSeatAssignment = (sessionId, seatId)
        tabletopGame.claimSeat(matching: seatId)
    }

    /// Assigns seats to SharePlay participants. The master always gets seat 0; players fill
    /// seats `1...playerSeatCount` in `TableSeatAssignment`'s deterministic order.
    ///
    /// The table has `PlayerSeat.seatPoses.count - 1` player seats, so a larger party shares
    /// seats (and their dice pools). That is reported through `sharedSeatPlayerCount`. When
    /// `masterParticipantId` is unknown the master still occupies a rank, so a party larger than
    /// the seat count is treated as possibly shared.
    func assignSeatsForSharePlay(
        groupSession: GroupSession<RPGActivity>?,
        isMaster: Bool,
        masterParticipantId: UUID? = nil
    ) {
        guard let groupSession else {
            Logger.sharePlay.debug("No active GroupSession — claiming any seat for single player")
            sharedSeatPlayerCount = nil
            lastRequestedSeatAssignment = nil
            tabletopGame.claimAnySeat()
            return
        }

        Logger.sharePlay.debug("SharePlay seat assignment for \(groupSession.activeParticipants.count, privacy: .public) participants (isMaster: \(isMaster, privacy: .public))")

        if isMaster {
            claimSeatIfNeeded(TableSeatIdentifier(0), sessionId: groupSession.id)
            sharedSeatPlayerCount = nil
            Logger.sharePlay.debug("Assigned seat 0 (master)")
            return
        }

        let playerSeatCount = PlayerSeat.seatPoses.count - 1
        guard let assignment = TableSeatAssignment.seat(
            localParticipantId: groupSession.localParticipant.id,
            participantIds: groupSession.activeParticipants.map(\.id),
            masterParticipantId: masterParticipantId,
            playerSeatCount: playerSeatCount
        ) else {
            Logger.sharePlay.debug("Could not find local participant — claiming any seat")
            sharedSeatPlayerCount = nil
            lastRequestedSeatAssignment = nil
            tabletopGame.claimAnySeat()
            return
        }

        sharedSeatPlayerCount = assignment.sharedPlayerCount
        if assignment.isSharedSeat {
            Logger.sharePlay.warning(
                "Party may exceed the \(playerSeatCount, privacy: .public) table seats — seat \(assignment.seatIndex, privacy: .public) (and its dice) may be shared with another player"
            )
        }
        Logger.sharePlay.debug("Assigned seat \(assignment.seatIndex, privacy: .public) to player")
        claimSeatIfNeeded(TableSeatIdentifier(assignment.seatIndex), sessionId: groupSession.id)
    }

    func updateSeatsForParticipantChange(
        groupSession: GroupSession<RPGActivity>?,
        isMaster: Bool,
        masterParticipantId: UUID? = nil
    ) {
        guard groupSession != nil else { return }
        Logger.sharePlay.debug("Participants changed — reassigning seats")
        assignSeatsForSharePlay(
            groupSession: groupSession,
            isMaster: isMaster,
            masterParticipantId: masterParticipantId
        )
    }
}

#endif
