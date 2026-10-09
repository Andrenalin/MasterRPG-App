// @copyright André Trettin

#if (os(iOS) || os(macOS) || os(visionOS)) && canImport(Testing)
import CoreRPG
import DiceRPG
import Foundation
import Spatial
import Testing

@testable import GameRPG

@Suite("Dice result popovers on the 3D table")
struct TableDiceResultTests {
    @Test("A parked or unrolled die is not rolled; an unrolled die lies with its 1 up")
    func dieValueEncoding() {
        #expect(!TableDieValue.isRolled(TableDieValue.parked))
        #expect(!TableDieValue.isRolled(TableDieValue.unrolled))
        #expect(TableDieValue.isRolled(1))
        #expect(TableDieValue.isRolled(20))
        #expect(TableDieValue.face(TableDieValue.unrolled) == 1)
        #expect(TableDieValue.face(17) == 17)
        #expect(TableDieValue.face(TableDieValue.parked) == 0)
    }

    @Test("Own dice get a popover before they are rolled; another seat's only with a rolled face")
    func popoverForDice() {
        let unrolled = [TableDieValue.unrolled, TableDieValue.unrolled]
        let partlyRolled = [TableDieValue.unrolled, 4]

        #expect(TableDieValue.hasPopover(unrolled, isLocalSeat: true))
        #expect(TableDieValue.hasPopover(partlyRolled, isLocalSeat: true))
        #expect(!TableDieValue.hasPopover([], isLocalSeat: true))
        #expect(!TableDieValue.hasPopover(unrolled, isLocalSeat: false))
        #expect(TableDieValue.hasPopover(partlyRolled, isLocalSeat: false))
        #expect(!TableDieValue.hasPopover([], isLocalSeat: false))
    }

    @Test("The focused dice change with a roll, with their number and with a copy taking their place")
    @MainActor
    func focusedDice() {
        let first = DieModel(id: UUID(), die: RawDie(.twenty), result: [17])
        let second = DieModel(id: UUID(), die: RawDie(.twenty))
        let dice = DiceModel(id: UUID(), dice: [first, second])
        let mirrored = TableFocusedDice(dice)

        #expect(mirrored == TableFocusedDice(dice))
        #expect(mirrored.faces == [20, 17, 20])

        // What the popover's compare value editor focuses: the same dice under a new id.
        #expect(mirrored != TableFocusedDice(dice.copy(withId: UUID())))

        dice.dice[1] = DieModel(id: second.id, die: second.die, result: [3])
        #expect(mirrored != TableFocusedDice(dice))

        dice.dice.append(DieModel(id: UUID(), die: RawDie(.six)))
        #expect(TableFocusedDice(dice).faces == [20, 17, 20, 3, 6])
    }

    @Test("A die is at rest only close to its goal in both position and orientation")
    func rest() {
        let goal = Pose3D(
            position: Point3D(x: 0.1, y: 0.04, z: 0.9),
            rotation: Rotation3D(angle: .degrees(90), axis: .z)
        )
        let nearby = Pose3D(
            position: Point3D(x: 0.1005, y: 0.04, z: 0.9005),
            rotation: Rotation3D(angle: .degrees(90.5), axis: .z)
        )
        let lifted = Pose3D(position: Point3D(x: 0.1, y: 0.06, z: 0.9), rotation: goal.rotation)
        let turning = Pose3D(position: goal.position, rotation: Rotation3D(angle: .degrees(60), axis: .z))
        // The same orientation, written as the negated quaternion.
        let negated = Pose3D(
            position: goal.position,
            rotation: Rotation3D(simd_quatd(vector: -goal.rotation.quaternion.vector))
        )

        #expect(TableDiceRest.isAtRest(pose: goal, goal: goal))
        #expect(TableDiceRest.isAtRest(pose: nearby, goal: goal))
        #expect(!TableDiceRest.isAtRest(pose: lifted, goal: goal))
        #expect(!TableDiceRest.isAtRest(pose: turning, goal: goal))
        #expect(TableDiceRest.isAtRest(pose: negated, goal: goal))
    }

    @Test("Every participant's seat: the master's is 0, players get the seat they compute for themselves")
    func participantSeats() throws {
        let master = try #require(UUID(uuidString: "00000000-0000-0000-0000-00000000000F"))
        let first = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let second = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let participants = [second, master, first]

        let seats = TableSeatAssignment.seats(
            participantIds: participants, masterParticipantId: master, playerSeatCount: 5
        )

        #expect(seats == [master: 0, first: 1, second: 2])
        for player in [first, second] {
            #expect(seats[player] == TableSeatAssignment.seat(
                localParticipantId: player, participantIds: participants,
                masterParticipantId: master, playerSeatCount: 5
            )?.seatIndex)
        }
        // Before the master is known it ranks as a player, like on the devices themselves.
        #expect(TableSeatAssignment.seats(
            participantIds: participants, masterParticipantId: nil, playerSeatCount: 5
        ) == [first: 1, second: 2, master: 3])
    }

    @Test("Own dice and the master's view are always visible; other seats follow the sharing options")
    func visibility() {
        let shared = GameFeatureModel(diceMaster: true, dicePlayers: true)
        let playersHidden = GameFeatureModel(diceMaster: true, dicePlayers: false)
        let masterHidden = GameFeatureModel(diceMaster: false, dicePlayers: true)

        func visible(local: Bool, master: Bool, masterSeat: Bool, _ features: GameFeatureModel) -> Bool {
            TableDiceResultVisibility.isVisible(
                isLocalSeat: local, isGameMaster: master, isMasterSeat: masterSeat, features: features
            )
        }

        // Own seat, whatever the options.
        #expect(visible(local: true, master: false, masterSeat: false, playersHidden))
        // The game master sees every seat.
        #expect(visible(local: false, master: true, masterSeat: false, playersHidden))
        // A player looking at another player's dice.
        #expect(visible(local: false, master: false, masterSeat: false, shared))
        #expect(!visible(local: false, master: false, masterSeat: false, playersHidden))
        #expect(visible(local: false, master: false, masterSeat: false, masterHidden))
        // A player looking at the master's dice.
        #expect(visible(local: false, master: false, masterSeat: true, playersHidden))
        #expect(!visible(local: false, master: false, masterSeat: true, masterHidden))
    }
}
#endif
