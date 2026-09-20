// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import GameRPG

@Suite("Table seat assignment")
struct TableSeatAssignmentTests {
    private let seatCount = 5

    @Test("A full party gets unique seats wherever the master ranks")
    func fullPartyGetsUniqueSeatsForEveryMasterRank() throws {
        // Given six participants (a master and five players), in every possible master position.
        let ids = (1...6).map { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0))! }
        for masterIndex in ids.indices {
            let master = ids[masterIndex]
            let players = ids.filter { $0 != master }

            // When
            let results = try players.map { player in
                try #require(TableSeatAssignment.seat(
                    localParticipantId: player,
                    participantIds: ids,
                    masterParticipantId: master,
                    playerSeatCount: seatCount
                ))
            }

            // Then
            #expect(Set(results.map(\.seatIndex)) == Set(1...seatCount))
            #expect(results.allSatisfy { !$0.isSharedSeat })
        }
    }

    @Test("Input order does not change the assignment")
    func assignmentIsIndependentOfInputOrder() throws {
        let ids = (0..<4).map { _ in UUID() }
        let local = ids[2]
        let forward = TableSeatAssignment.seat(
            localParticipantId: local, participantIds: ids, masterParticipantId: ids[0], playerSeatCount: seatCount
        )
        let reversed = TableSeatAssignment.seat(
            localParticipantId: local, participantIds: ids.reversed(), masterParticipantId: ids[0], playerSeatCount: seatCount
        )
        #expect(forward == reversed)
    }

    @Test("More players than seats is reported as shared")
    func oversubscribedPartyIsShared() throws {
        let ids = (0..<8).map { _ in UUID() }
        let result = try #require(TableSeatAssignment.seat(
            localParticipantId: ids[3], participantIds: ids, masterParticipantId: ids[0], playerSeatCount: seatCount
        ))
        #expect(result.isSharedSeat)
        #expect(result.sharedPlayerCount == 7)
        #expect((1...seatCount).contains(result.seatIndex))
    }

    @Test("Without a known master a possibly colliding party is reported, not silently assumed safe")
    func unknownMasterFlagsAPossibleCollision() throws {
        let ids = (0..<6).map { _ in UUID() }
        let result = try #require(TableSeatAssignment.seat(
            localParticipantId: ids[1], participantIds: ids, masterParticipantId: nil, playerSeatCount: seatCount
        ))
        #expect(result.isSharedSeat)

        let small = try #require(TableSeatAssignment.seat(
            localParticipantId: ids[1], participantIds: Array(ids.prefix(5)), masterParticipantId: nil, playerSeatCount: seatCount
        ))
        #expect(!small.isSharedSeat)
    }

    @Test("A device that is not in the participant list gets no seat")
    func unknownLocalParticipantGetsNoSeat() {
        let ids = (0..<3).map { _ in UUID() }
        #expect(TableSeatAssignment.seat(
            localParticipantId: UUID(), participantIds: ids, masterParticipantId: nil, playerSeatCount: seatCount
        ) == nil)
    }
}
#endif
