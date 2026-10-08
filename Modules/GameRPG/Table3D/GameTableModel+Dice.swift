// @copyright André Trettin

#if os(visionOS)
import CoreRPG
import DiceRPG
import Foundation
import Spatial
import TabletopKit
import os.log

extension GameTableModel {
    // MARK: - Dice

    /// Mirrors the locally focused character-sheet dice set onto the local player's own seat:
    /// shows exactly as many `Die20`/`Die` (d6) slots as the set needs of each type, positioned to
    /// match, and parks every other slot in this seat's pool off-table at `.parkedDicePose` with the
    /// `0` sentinel. Reuses DiceRPG's focus-dice mechanism as the trigger rather than a separate
    /// notion of "selected dice" for the table. `TabletopGame.addAction` syncs every change to every
    /// other participant, so every device shows the same shape for this seat.
    ///
    /// Only d20 and d6 are backed by a table mesh, and each seat only has
    /// `GameSetup.maxDicePerType` slots per type. Extras (a homebrew "roll 8d6", or a GM
    /// batch-rolling for several NPCs) are dropped rather than mirrored, and reported through
    /// `diceOverflowCount`.
    ///
    /// Only slots whose synced value or pose actually changes are submitted: each `addAction` is a
    /// SharePlay message and plays the toss sound, so re-parking already-parked dice was pure noise.
    ///
    /// A die the sheet has not rolled yet is mirrored as `TableDieValue.unrolled`, so no device
    /// shows a result for it. A die tossed by hand got its value from the sheet already (see
    /// `rollTossedDie(_:)`) and stays where it landed until the sheet gives it another one.
    func applyDiceRoll(_ diceModel: DiceModel) {
        mirroredSheet = nil
        guard let seat = localSeat,
              let d20Ids = setup.playerD20Ids[seat],
              let d6Ids = setup.playerD6Ids[seat],
              let seatPose = setup.seats.first(where: { $0.id == seat })?.initialState.pose
        else { return }
        var sheetDieIds: [EquipmentIdentifier: UUID] = [:]

        // Compare the *resolved* side count (`RawDie.max`), not the `Sides` enum case: a die
        // authored through the sheet's UI can end up as `.number(20)` instead of `.twenty`, and
        // those don't compare equal despite meaning the same die.
        let d20Dice = diceModel.dice.filter { $0.die.max == 20 }
        let d6Dice = diceModel.dice.filter { $0.die.max == 6 }
        let usedD20Count = min(d20Dice.count, d20Ids.count)
        let usedD6Count = min(d6Dice.count, d6Ids.count)
        let layout = PlayerSeat.diceLayout(inFrontOf: seatPose, count: usedD20Count + usedD6Count)

        for (index, dieId) in d20Ids.enumerated() {
            guard let equipment = tabletopGame.equipment(of: Die20.self, matching: dieId) else { continue }
            let target = index < usedD20Count
                ? (value: d20Dice[index].result.last ?? TableDieValue.unrolled, pose: layout[index])
                : (value: TableDieValue.parked, pose: .parkedDicePose)
            updateDieSlot(equipment, target: target)
            if index < usedD20Count { sheetDieIds[dieId] = d20Dice[index].id }
        }

        for (index, dieId) in d6Ids.enumerated() {
            guard let equipment = tabletopGame.equipment(of: Die.self, matching: dieId) else { continue }
            let target = index < usedD6Count
                ? (value: d6Dice[index].result.last ?? TableDieValue.unrolled, pose: layout[usedD20Count + index])
                : (value: TableDieValue.parked, pose: .parkedDicePose)
            updateDieSlot(equipment, target: target)
            if index < usedD6Count { sheetDieIds[dieId] = d6Dice[index].id }
        }
        mirroredSheet = (diceModel.id, sheetDieIds)

        let overflowCount = diceModel.dice.count - usedD20Count - usedD6Count
        diceOverflowCount = overflowCount > 0 ? overflowCount : nil
        if overflowCount > 0 {
            Logger.gameTable.warning(
                "Focused dice set had \(overflowCount, privacy: .public) dice this table couldn't represent (unsupported sides, or more than \(GameSetup.maxDicePerType, privacy: .public) of one type at this seat); those results were not mirrored onto the table"
            )
        }
    }

    /// Submits a slot update only if it differs from the synced state.
    func updateDieSlot<Equip: Equipment>(
        _ equipment: Equip,
        target: (value: Int, pose: TableVisualState.Pose2D)
    ) where Equip.State == DieState {
        if handTossedDice[equipment.id] == target.value {
            // The toss put this value on the table and decides where the die lies.
            return
        }
        handTossedDice[equipment.id] = nil
        var current: DieState?
        tabletopGame.withCurrentSnapshot { snapshot in
            current = snapshot.equipment(of: Equip.self, matching: equipment.id)?.1
        }
        if let current,
           current.value == target.value,
           Self.isSamePose(current.pose, target.pose) {
            return
        }
        tabletopGame.addAction(
            .updateEquipment(equipment, value: target.value, seatControl: nil, pose: target.pose, boundingBox: nil, context: 0)
        )
    }

    private static func isSamePose(_ lhs: TableVisualState.Pose2D, _ rhs: TableVisualState.Pose2D) -> Bool {
        let tolerance = 0.000_1
        return abs(lhs.position.x - rhs.position.x) < tolerance
            && abs(lhs.position.z - rhs.position.z) < tolerance
            && abs(lhs.rotation.radians - rhs.rotation.radians) < tolerance
    }

    /// The value of a die tossed by hand. The local player's own die is rolled by its sheet,
    /// so the toss is a roll like any other: it shows in the dice overlay and is shared with
    /// the game. `nil` for any other die — the master tossing a player's die cannot roll that
    /// player's sheet — which then gets a value from the table alone.
    func rollTossedDie(_ dieId: EquipmentIdentifier) -> Int? {
        guard let mirroredSheet,
              let sheetDieId = mirroredSheet.dieIds[dieId],
              let value = diceRoot?.diceGameControllable.rollDie(
                  sheetDieId,
                  of: mirroredSheet.diceId,
                  networkActions: networkActions
              ) else { return nil }
        handTossedDice[dieId] = value
        return value
    }

    /// Whether `dieId` belongs to the pool of the guest seat.
    func isGuestDie(_ dieId: EquipmentIdentifier) -> Bool {
        setup.playerD20Ids[PlayerSeat.guestSeat]?.contains(dieId) == true
            || setup.playerD6Ids[PlayerSeat.guestSeat]?.contains(dieId) == true
    }

    /// Whether `dieId` belongs to one of the table's dice pools.
    func isDie(_ dieId: EquipmentIdentifier) -> Bool {
        tabletopGame.equipment(of: Die20.self, matching: dieId) != nil
            || tabletopGame.equipment(of: Die.self, matching: dieId) != nil
    }

    /// The game master may handle any die; a player only the dice in their own seat's pool.
    /// Nobody handles the guest seat's dice: they mirror the rolls of players without a table,
    /// and a toss gave such a die a value of the table's own, which no longer matched that
    /// player's roll and hid their result on every table. See CODE_AUDIT_21 §5.11.
    func canControlDie(_ dieId: EquipmentIdentifier) -> Bool {
        guard !isGuestDie(dieId) else { return false }
        if isGameMaster { return true }
        guard let seat = localSeat else { return false }
        return setup.playerD20Ids[seat]?.contains(dieId) == true
            || setup.playerD6Ids[seat]?.contains(dieId) == true
    }

    /// VoiceOver's "activate" gesture on a die entity (see `DiceComponent`, wired in `GameTableView`'s
    /// accessibility subscription) — the direct on-table toss gesture otherwise has no accessible
    /// equivalent. Picks a random result and applies it through the same `TabletopGame.addAction`
    /// path a physical toss uses.
    func tossDieForAccessibility(dieId: EquipmentIdentifier, sides: Int) {
        guard canControlDie(dieId) else { return }
        let result = rollTossedDie(dieId) ?? Int.random(in: 1...sides)
        if let equipment = tabletopGame.equipment(of: Die20.self, matching: dieId) {
            tabletopGame.addAction(
                .updateEquipment(equipment, value: result, seatControl: nil, pose: nil, boundingBox: nil, context: 0)
            )
        } else if let equipment = tabletopGame.equipment(of: Die.self, matching: dieId) {
            tabletopGame.addAction(
                .updateEquipment(equipment, value: result, seatControl: nil, pose: nil, boundingBox: nil, context: 0)
            )
        }
    }
}
#endif
