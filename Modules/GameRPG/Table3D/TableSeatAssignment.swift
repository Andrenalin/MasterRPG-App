// @copyright André Trettin

import Foundation

/// Deterministic mapping from SharePlay participants to table seats. Pure value logic with no
/// TabletopKit dependency, so it is unit-testable on every platform.
///
/// Seat 0 always belongs to the game master; players share seats `1...playerSeatCount`.
enum TableSeatAssignment {
    struct Result: Equatable {
        /// Table seat index (`1...playerSeatCount`) for a player.
        let seatIndex: Int
        /// The party has more players than seats (or may have — see `masterParticipantId`), so this
        /// seat and its dice may be shared with another player.
        let isSharedSeat: Bool
        /// Total players in the party as far as this device can tell; `nil` when `isSharedSeat` is false.
        let sharedPlayerCount: Int?
    }

    /// - Parameters:
    ///   - localParticipantId: This device's participant id.
    ///   - participantIds: Every active participant, master included, in any order.
    ///   - masterParticipantId: The master's participant id when known. When it is `nil` the master
    ///     still occupies a rank, so any party larger than `playerSeatCount` participants *may*
    ///     collide and is reported as shared rather than silently assumed safe.
    ///   - playerSeatCount: The number of non-master seats at the table.
    /// - Returns: `nil` when this device is not one of `participantIds`.
    static func seat(
        localParticipantId: UUID,
        participantIds: [UUID],
        masterParticipantId: UUID?,
        playerSeatCount: Int
    ) -> Result? {
        guard playerSeatCount > 0 else { return nil }
        // Players rank by id so every device computes the same order.
        let players = participantIds
            .filter { $0 != masterParticipantId }
            .sorted { $0.uuidString < $1.uuidString }
        guard let rank = players.firstIndex(of: localParticipantId) else { return nil }

        let seatIndex = (rank % playerSeatCount) + 1
        let mayShare = masterParticipantId == nil
            ? participantIds.count > playerSeatCount
            : players.count > playerSeatCount
        return Result(
            seatIndex: seatIndex,
            isSharedSeat: mayShare,
            sharedPlayerCount: mayShare ? players.count : nil
        )
    }

    /// The seat index of every participant, as each of them computes it for itself: 0 for the
    /// master, `seat(localParticipantId:...)`'s for a player. Lets a device tell who sits where.
    static func seats(
        participantIds: [UUID],
        masterParticipantId: UUID?,
        playerSeatCount: Int
    ) -> [UUID: Int] {
        var seats: [UUID: Int] = [:]
        for participantId in participantIds {
            if participantId == masterParticipantId {
                seats[participantId] = 0
            } else if let assignment = seat(
                localParticipantId: participantId,
                participantIds: participantIds,
                masterParticipantId: masterParticipantId,
                playerSeatCount: playerSeatCount
            ) {
                seats[participantId] = assignment.seatIndex
            }
        }
        return seats
    }
}
