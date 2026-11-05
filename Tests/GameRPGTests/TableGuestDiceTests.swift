// @copyright André Trettin

#if (os(iOS) || os(macOS) || os(visionOS)) && canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import GameRPG

@Suite("Dice of the players without a table")
struct TableGuestDiceTests {
    @Test("Guests get the guest seat's dice in the order of their names")
    func groupsFollowNames() {
        let groups = TableGuestDice.groups(
            for: [
                TableGuestRoll(name: "Cleo", dice: [.init(isD20: false, value: 2), .init(isD20: false, value: 5)]),
                TableGuestRoll(name: "Anna", dice: [.init(isD20: true, value: 17), .init(isD20: true, value: 4), .init(isD20: false, value: 6)]),
                TableGuestRoll(name: "Ben", dice: [.init(isD20: true, value: 11)])
            ],
            poolSize: 6
        )

        #expect(groups.map(\.name) == ["Anna", "Ben", "Cleo"])
        #expect(groups[0].dice == [
            .init(isD20: true, slot: 0, value: 17),
            .init(isD20: true, slot: 1, value: 4),
            .init(isD20: false, slot: 0, value: 6)
        ])
        #expect(groups[1].dice == [.init(isD20: true, slot: 2, value: 11)])
        #expect(groups[2].dice == [
            .init(isD20: false, slot: 1, value: 2),
            .init(isD20: false, slot: 2, value: 5)
        ])
    }

    @Test("A guest's dice keep the order of the roll, d20 and d6 mixed")
    func groupsFollowTheRoll() {
        let groups = TableGuestDice.groups(
            for: [
                TableGuestRoll(name: "Anna", dice: [
                    .init(isD20: false, value: 3),
                    .init(isD20: true, value: 11),
                    .init(isD20: false, value: 5)
                ])
            ],
            poolSize: 6
        )

        #expect(groups[0].dice == [
            .init(isD20: false, slot: 0, value: 3),
            .init(isD20: true, slot: 0, value: 11),
            .init(isD20: false, slot: 1, value: 5)
        ])
    }

    @Test("The game master's roll keeps its mark on its group")
    func masterGroup() {
        let groups = TableGuestDice.groups(
            for: [
                TableGuestRoll(name: "Master", dice: [.init(isD20: true, value: 9)], isGameMaster: true),
                TableGuestRoll(name: "Anna", dice: [.init(isD20: true, value: 12)])
            ],
            poolSize: 6
        )

        #expect(groups.map(\.name) == ["Anna", "Master"])
        #expect(groups.map(\.isGameMaster) == [false, true])
        #expect(groups[1].dice == [.init(isD20: true, slot: 1, value: 9)])
    }

    @Test("Dice beyond the pool are left out, and so is a guest without any die on the table")
    func poolLimit() {
        let groups = TableGuestDice.groups(
            for: [
                TableGuestRoll(name: "Anna", dice: [.init(isD20: true, value: 1), .init(isD20: true, value: 2), .init(isD20: true, value: 3)]),
                TableGuestRoll(name: "Ben", dice: [.init(isD20: true, value: 4), .init(isD20: true, value: 5), .init(isD20: false, value: 6)]),
                TableGuestRoll(name: "Cleo", dice: [.init(isD20: true, value: 7)]),
                TableGuestRoll(name: "Dora", dice: [])
            ],
            poolSize: 4
        )

        #expect(groups.map(\.name) == ["Anna", "Ben"])
        #expect(groups[1].dice.map(\.value) == [4, 6])
    }

    @Test("Groups lie side by side on the guest seat's edge, apart from each other, inside the table")
    func positionsOnOneRow() {
        let positions = TableGuestDice.positions(groupSizes: [3, 1, 2])
        let all = positions.flatMap { $0 }
        let edge = -(Double(GameMetrics.tableLength) / 2 - Double(GameMetrics.diceEdgeInset))

        #expect(positions.map(\.count) == [3, 1, 2])
        #expect(all.allSatisfy { abs($0.z - edge) < 0.000_1 })
        #expect(all.allSatisfy { abs($0.x) < Double(GameMetrics.tableWidth) / 2 - Double(GameMetrics.diceEdgeInset) })
        // In order across the table, every die at least a die's spacing from the next.
        let xs = all.map(\.x)
        #expect(xs == xs.sorted())
        #expect(zip(xs, xs.dropFirst()).allSatisfy { $1 - $0 >= TableGuestDice.spacing - 0.000_1 })
        // Two groups are further apart than two dice of one group.
        #expect(positions[1][0].x - positions[0][2].x > TableGuestDice.spacing + 0.000_1)
        // The row is spread over the whole width: as much room left as right.
        #expect(abs(xs[0] + xs[xs.count - 1]) < 0.000_1)
    }

    @Test("Groups that do not fit continue on a row further into the table")
    func positionsWrap() {
        let capacity = TableGuestDice.rowCapacity
        let positions = TableGuestDice.positions(groupSizes: [capacity - 1, 2, capacity + 2])
        let rows = positions.map { Set($0.map { ($0.z * 1000).rounded() }) }

        #expect(positions.map(\.count) == [capacity - 1, 2, capacity + 2])
        #expect(rows[0].count == 1)
        #expect(rows[1].count == 1)
        #expect(rows[0] != rows[1])
        // A group longer than a row is broken over two.
        #expect(rows[2].count == 2)
        #expect(TableGuestDice.positions(groupSizes: []).isEmpty)
    }

    @Test("A message carries its sender's platform; an unknown or missing one decodes as none")
    func senderPlatformCoding() throws {
        let message = GameNetworkModel(
            counter: 1,
            proxyCounter: 0,
            type: .update,
            subType: .generic,
            masterId: UUID(),
            sender: GameSenderModel(id: UUID(), role: .player, name: "Anna", characterId: nil),
            senderPlatform: .visionOS,
            data: NetworkCodableDataType(id: UUID(), type: .dice, version: 0)
        )
        let data = try JSONEncoder().encode(message)
        #expect(try JSONDecoder().decode(GameNetworkModel.self, from: data).senderPlatform == .visionOS)

        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["senderPlatform"] = "watchOS"
        let unknown = try JSONSerialization.data(withJSONObject: json)
        #expect(try JSONDecoder().decode(GameNetworkModel.self, from: unknown).senderPlatform == nil)
        json["senderPlatform"] = nil
        let missing = try JSONSerialization.data(withJSONObject: json)
        #expect(try JSONDecoder().decode(GameNetworkModel.self, from: missing).senderPlatform == nil)
    }

    @MainActor
    @Test("A roll from any device but Vision Pro makes its player a table guest, the master's too")
    func guestNames() throws {
        let model = GameRootModel()
        var ids: [String: UUID] = [:]
        func roll(_ name: String, role: GameType = .player, platform: GamePlatform?, player: String? = nil) -> GameNetworkModel {
            let id = ids[player ?? name, default: UUID()]
            ids[player ?? name] = id
            return GameNetworkModel(
                counter: 1, proxyCounter: 0, type: .update, subType: .generic, masterId: UUID(),
                sender: GameSenderModel(id: id, role: role, name: name, characterId: nil),
                senderPlatform: platform,
                data: NetworkCodableDataType(id: UUID(), type: .dice, version: 0)
            )
        }

        model.noteDiceRollSender(of: roll("Anna", platform: .iOS))
        model.noteDiceRollSender(of: roll("Ben", platform: nil))
        model.noteDiceRollSender(of: roll("Vera", platform: .visionOS))
        #expect(model.tableGuestNames == ["Anna", "Ben"])
        #expect(model.tableGuestMasterName == nil)

        // A master without a Vision Pro has no seat at a player's table: their dice lie at the
        // guest seat like a player's.
        model.noteDiceRollSender(of: roll("Master", role: .master, platform: .macOS))
        #expect(model.tableGuestNames == ["Anna", "Ben", "Master"])
        #expect(model.tableGuestMasterName == "Master")

        // On a Vision Pro the master rolls at seat 0 again.
        model.noteDiceRollSender(of: roll("Master", role: .master, platform: .visionOS))
        #expect(model.tableGuestNames == ["Anna", "Ben"])
        #expect(model.tableGuestMasterName == nil)

        // Anna moves to a Vision Pro.
        model.noteDiceRollSender(of: roll("Anna", platform: .visionOS))
        #expect(model.tableGuestNames == ["Ben"])

        // CODE_AUDIT_21 §5.12: a second player named Ben on a Vision Pro is another player, and
        // does not take the first Ben's guest seat away.
        model.noteDiceRollSender(of: roll("Ben", platform: .visionOS, player: "Ben at the table"))
        #expect(model.tableGuestNames == ["Ben"])

        // A guest who leaves the game is no guest any more.
        _ = model.remove(playerId: try #require(ids["Ben"]))
        #expect(model.tableGuestNames.isEmpty)
    }
}
#endif
