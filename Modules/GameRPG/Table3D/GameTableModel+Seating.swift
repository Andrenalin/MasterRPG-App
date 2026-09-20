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
@preconcurrency import GroupActivities
import TabletopKit
#endif

#if os(visionOS)
extension GameTableModel {
    // MARK: - Seating & Space Setup

    /// Called when the 3D table view appears to set up seating.
    ///
    /// When a SharePlay session is active, the actual seat claim is
    /// deliberately *not* made here — it's made by
    /// `RPGSharePlayController.setup(tabletopGame:gameTableModel:)`, chained
    /// after `tabletopGame.coordinateWithSession(_:)` there instead. `claimSeat`/
    /// `claimAnySeat` are themselves TabletopKit-synchronized actions:
    /// submitting one before this game's network coordinator is attached to
    /// the group session left a joining player's claim unsynced against the
    /// master's already-running session, and TabletopKit's internal
    /// reconciliation could then no longer resolve a later synced update
    /// against the mismatched local state — crashing every joining player
    /// with "Could not find static equipment with identifier: ...". Only the
    /// no-session (local/single-player) case claims a seat directly here,
    /// since there's no coordinator to race — see `GameObserver.canAutoClaimSeat`'s
    /// own doc for the matching guard on its fallback re-claim.
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

    /// Removed 2026-08-23: this used to derive local dice visibility from
    /// `Entity.isEnabled` (occupied seat + a nonzero synced value ⇒
    /// enabled), called from `GameObserver.playerChangedSeats`/
    /// `actionWasConfirmed` and from `setupSeating` via a snapshot read.
    /// `Entity.isEnabled` is a purely local, unsynced RealityKit property —
    /// none of Apple's own TabletopKit samples (dice, cards, the
    /// coin-collecting mini-game) ever set it on equipment; every hide/park
    /// they show goes through the equipment's own *synced* pose/parentID
    /// instead (e.g. the card sample's off-table `poseOffTable`, or the
    /// mini-game's `ResetPlayer` moving a piece to `.bankID(for:)`). A
    /// permanently-disabled die (every pool slot, from creation, until its
    /// owning seat actually rolls) was never enabled on a joining player's
    /// own device — and so, it turned out, never registered as "static
    /// equipment" for TabletopKit's own RealityKit-level shared-simulation
    /// join there either. The very first snapshot read touching one of
    /// those still-disabled dice (this method, scanning every seat's pool)
    /// crashed with "Could not find static equipment with identifier: ...".
    /// `Die20`/`Die.init` and `GameTableModel.applyDiceRoll` now park an
    /// unused die off-table via its synced pose (`.parkedDicePose`) instead,
    /// and leave every die's entity permanently enabled — visibility is
    /// entirely a function of synced state now, so no local re-derivation
    /// is needed. Known gap: a seat that becomes unoccupied after being
    /// claimed doesn't re-park its dice (this app doesn't otherwise support
    /// leaving a claimed seat mid-session, so this hasn't been worth solving
    /// yet — flagged here rather than silently dropped).

    /// This device's own seat, however it was claimed (SharePlay assignment
    /// or `claimAnySeat()` for local/single-player) — queried directly from
    /// TabletopKit's synchronized seat state rather than tracked separately
    /// during assignment, so it stays correct even if seating changes later.
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
    /// Assigns seats to SharePlay participants. Master always gets seat 0; players fill seats 1+.
    ///
    /// The table only has `PlayerSeat.seatPoses.count - 1` physical player
    /// seats (currently 5 — see `PlayerSeat.seatPoses`). A party larger than
    /// that therefore always has multiple players share a seat — and with
    /// it, the seat's dice pools from `GameSetup.playerD20Ids`/
    /// `playerD6Ids`, so a character-sheet roll from one of those players
    /// moves the dice the other(s) also treat as their own.
    /// This can't be eliminated purely by reindexing (there are only 5
    /// buckets for larger parties), but it's now deterministic — every
    /// device computes the same sorted `activeParticipants` list — and
    /// surfaced via `sharedSeatPlayerCount` and a log instead of being
    /// silent. See CODE_AUDIT §5.2.
    /// Submits `claimSeat` only if this exact `(session, seat)` pair hasn't
    /// already been requested — see `GameTableModel.lastRequestedSeatAssignment`'s
    /// own doc for why a redundant identical claim is unsafe, not just
    /// wasteful.
    @MainActor
    private func claimSeatIfNeeded(_ seatId: TableSeatIdentifier, sessionId: UUID) {
        guard lastRequestedSeatAssignment?.sessionId != sessionId
            || lastRequestedSeatAssignment?.seatId != seatId
        else { return }
        lastRequestedSeatAssignment = (sessionId, seatId)
        tabletopGame.claimSeat(matching: seatId)
    }

    @MainActor
    func assignSeatsForSharePlay(groupSession: GroupSession<RPGActivity>?, isMaster: Bool) {
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

        // Players sort by ID for consistent assignment; seat 0 is reserved
        // for master. `activeParticipants` carries no host/role marker, so
        // the master's own participant can't be excluded from this ranking
        // — it simply occupies one rank alongside everyone else and is
        // handled entirely by the `isMaster` branch above.
        let localParticipant = groupSession.localParticipant
        let sortedParticipants = groupSession.activeParticipants
            .sorted { $0.id.uuidString < $1.id.uuidString }

        guard let localIndex = sortedParticipants.firstIndex(where: { $0.id == localParticipant.id }) else {
            Logger.sharePlay.debug("Could not find local participant — claiming any seat")
            sharedSeatPlayerCount = nil
            lastRequestedSeatAssignment = nil
            tabletopGame.claimAnySeat()
            return
        }

        // Seat 0 is master; player seats start at 1 and wrap within available slots
        let playerSeatCount = PlayerSeat.seatPoses.count - 1
        let seatIndex = (localIndex % playerSeatCount) + 1
        // `sortedParticipants` includes the master (there's no way to
        // exclude them specifically — see the doc comment above), so this
        // slightly overcounts the true player count by one. Harmless here:
        // it only feeds the ">" oversubscription check and the logged
        // number, not the seat math itself.
        let playerCount = sortedParticipants.count - 1
        if playerCount > playerSeatCount {
            sharedSeatPlayerCount = playerCount
            Logger.sharePlay.warning(
                "\(playerCount, privacy: .public) players but only \(playerSeatCount, privacy: .public) table seats — seat \(seatIndex, privacy: .public) (and its dice) may be shared with another player"
            )
        } else {
            sharedSeatPlayerCount = nil
        }
        Logger.sharePlay.debug("Assigned seat \(seatIndex, privacy: .public) to player (index \(localIndex, privacy: .public))")
        claimSeatIfNeeded(TableSeatIdentifier(seatIndex), sessionId: groupSession.id)
    }

    @MainActor
    func updateSeatsForParticipantChange(groupSession: GroupSession<RPGActivity>?, isMaster: Bool) {
        guard groupSession != nil else { return }
        Logger.sharePlay.debug("Participants changed — reassigning seats")
        assignSeatsForSharePlay(groupSession: groupSession, isMaster: isMaster)
    }
}

#endif

#endif
