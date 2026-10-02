// @copyright André Trettin

#if os(visionOS)
import Combine
import CoreRPG
import Foundation
import GroupActivities
import TabletopKit
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
        seatingGameTableModel = gameTableModel
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
        applySeatPlayerNames(to: gameTableModel, groupSession: groupSession, masterParticipantId: masterId)

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
                self.applySeatPlayerNames(
                    to: gameTableModel,
                    groupSession: groupSession,
                    masterParticipantId: masterId
                )
            }
        }
        trackSessionTask(seatTask, key: Self.seatObservationTaskKey)
    }

    /// A player learned (or re-learned) which participant is the master. Players rank each other
    /// without the master once it is known, but with it still in the list before that, and seats
    /// were only recomputed on roster changes — so two players could compute the same seat, one
    /// before and one after learning the master. Recompute now. See CODE_AUDIT_18 §5.11.
    @MainActor
    func masterParticipantDidChange() {
        guard let groupSession, let gameTableModel = seatingGameTableModel else { return }
        let sessionId = groupSession.id
        let task = Task { [weak self] in
            guard let self else { return }
            let isMaster = self.gameModel?.gameConfig.isMaster ?? false
            let masterId = await self.masterParticipantId(in: groupSession, isMaster: isMaster)
            guard !Task.isCancelled, self.groupSession?.id == sessionId else { return }
            gameTableModel.updateSeatsForParticipantChange(
                groupSession: groupSession,
                isMaster: isMaster,
                masterParticipantId: masterId
            )
            self.applySeatPlayerNames(
                to: gameTableModel,
                groupSession: groupSession,
                masterParticipantId: masterId
            )
        }
        trackSessionTask(task, key: Self.masterPinSeatTaskKey)
    }

    /// A participant's player became known (or left): tell the table who sits where again.
    @MainActor
    func refreshSeatPlayerNames() {
        guard let groupSession, let gameTableModel = seatingGameTableModel else { return }
        let sessionId = groupSession.id
        let task = Task { [weak self] in
            guard let self else { return }
            let isMaster = self.gameModel?.gameConfig.isMaster ?? false
            let masterId = await self.masterParticipantId(in: groupSession, isMaster: isMaster)
            guard !Task.isCancelled, self.groupSession?.id == sessionId else { return }
            self.applySeatPlayerNames(
                to: gameTableModel,
                groupSession: groupSession,
                masterParticipantId: masterId
            )
        }
        trackSessionTask(task, key: Self.seatPlayerNamesTaskKey)
    }

    /// Every device seats the participants the same way (`TableSeatAssignment`), so the seat of
    /// each participant whose player is known gives that seat its player. The master's seat
    /// carries the master's name; a player's, the name learned from their own messages. A
    /// participant without a table is ranked like the others but sits nowhere: their dice are
    /// shown at the guest seat.
    @MainActor
    private func applySeatPlayerNames(
        to gameTableModel: GameTableModel,
        groupSession: GroupSession<RPGActivity>,
        masterParticipantId: UUID?
    ) {
        let seats = TableSeatAssignment.seats(
            participantIds: groupSession.activeParticipants.map(\.id),
            masterParticipantId: masterParticipantId,
            playerSeatCount: PlayerSeat.playerSeatCount
        )
        var names: [TableSeatIdentifier: [String]] = [:]
        for (participantId, seatIndex) in seats {
            let name: String?
            if participantId == masterParticipantId {
                name = gameModel?.gameConfig.master.name
            } else if let player = participantPlayers[participantId], player.hasTable {
                name = player.name
            } else {
                name = nil
            }
            guard let name, !name.isEmpty else { continue }
            names[TableSeatIdentifier(seatIndex), default: []].append(name)
        }
        names = names.mapValues { $0.sorted() }
        if gameTableModel.seatPlayerNames != names {
            gameTableModel.seatPlayerNames = names
        }
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
    static let masterPinSeatTaskKey = UUID()
    static let seatPlayerNamesTaskKey = UUID()
}

#endif
