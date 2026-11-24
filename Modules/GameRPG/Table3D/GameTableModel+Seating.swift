// @copyright André Trettin

#if os(visionOS)
import CoreRPG
import Foundation
import GroupActivities
import Spatial
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
            claimLocalSeat(isMaster: isMaster)
        }
    }

    /// The seat of a device with no SharePlay seat assignment (the local network, a solo table):
    /// the game master's own seat 0 for the master, the first player seat for a player. Never
    /// `claimAnySeat()`, which hands out seat 0: a player there would sit at the master's seat,
    /// the table would not turn toward them, and the dice of a master without a table (which
    /// lie at seat 0) would have no place. Nothing is synced between devices without a
    /// session, so every device has its own table and its own player seat.
    func claimLocalSeat(isMaster: Bool) {
        tabletopGame.claimSeat(matching: isMaster ? TableSeatIdentifier(0) : PlayerSeat.firstPlayerSeat)
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

extension GameTableModel {
    /// Called every frame with the seat TabletopKit's snapshot gives the local player: turns the
    /// table when that seat changes. It does not wait for `GameObserver.playerChangedSeats`, which
    /// was never seen to run on a Vision Pro in a SharePlay session with a second Vision Pro (the
    /// table stayed as it opened, the player's seat to the side). The turn itself is deferred:
    /// this runs inside TabletopKit's frame callback.
    func turnTableWhenLocalSeatChanged(to seat: TableSeatIdentifier?) {
        guard seat != lastSnapshotLocalSeat else { return }
        lastSnapshotLocalSeat = seat
        guard let seat else { return }
        Task { @MainActor [weak self] in
            self?.orientTableToLocalSeat(seat: seat)
        }
    }

    /// Turns the table so the local seat is in front of the viewer, unless the system already
    /// does (`isLocalSeatPlacedBySystem`). Seat 0 (the master, and every player without a seat
    /// yet) leaves the table as it is. See `GameRenderer.orientTable(toSeatRotation:)`.
    ///
    /// - Parameter seat: the seat just claimed, straight from `GameObserver.playerChangedSeats`;
    ///   a snapshot read right after a claim can still miss it. Without it the seat of the
    ///   current snapshot is used.
    func orientTableToLocalSeat(seat: TableSeatIdentifier? = nil) {
        if let seat { lastOrientedSeat = seat }
        let seatId = seat ?? lastOrientedSeat ?? localSeat
        let pose = seatId.flatMap { id in setup.seats.first(where: { $0.id == id })?.initialState.pose }
            ?? PlayerSeat.seatPoses[0]
        let isPlacedBySystem = systemSeatPlacement?() ?? isLocalSeatPlacedBySystem
        let radians = isPlacedBySystem ? 0 : pose.rotation.radians
        Logger.sharePlay.debug("Orienting the table: seat \(seatId.map { String(describing: $0) } ?? "none", privacy: .public), placed by system: \(isPlacedBySystem, privacy: .public), turn: \(radians, privacy: .public) rad")
        renderer.orientTable(toSeatRotation: radians)
        // The panels stand beside the local seat's dice, so they move with the seat.
        updateSeatPanelPositions()
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
    /// The table has `PlayerSeat.playerSeatCount` player seats (the seat opposite the master is
    /// kept for the players without a table, see `PlayerSeat.guestSeat`), so a larger party shares
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
            claimLocalSeat(isMaster: isMaster)
            return
        }

        Logger.sharePlay.debug("SharePlay seat assignment for \(groupSession.activeParticipants.count, privacy: .public) participants (isMaster: \(isMaster, privacy: .public))")

        if isMaster {
            claimSeatIfNeeded(TableSeatIdentifier(0), sessionId: groupSession.id)
            sharedSeatPlayerCount = nil
            Logger.sharePlay.debug("Assigned seat 0 (master)")
            return
        }

        let playerSeatCount = PlayerSeat.playerSeatCount
        guard let assignment = TableSeatAssignment.seat(
            localParticipantId: groupSession.localParticipant.id,
            participantIds: groupSession.activeParticipants.map(\.id),
            masterParticipantId: masterParticipantId,
            playerSeatCount: playerSeatCount
        ) else {
            Logger.sharePlay.debug("Could not find local participant — claiming any seat")
            sharedSeatPlayerCount = nil
            lastRequestedSeatAssignment = nil
            claimLocalSeat(isMaster: false)
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
