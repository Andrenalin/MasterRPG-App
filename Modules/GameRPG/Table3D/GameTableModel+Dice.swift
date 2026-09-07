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
import TabletopKit
#endif

#if os(visionOS)
extension GameTableModel {
    // MARK: - Dice

    /// Mirrors the locally focused character-sheet dice set onto the local
    /// player's own seat — showing exactly as many `Die20`/`Die` (d6) slots
    /// as the set needs of each type, typed and positioned to match (a mix
    /// of both is fine), and parking every other slot in this seat's pool
    /// back off-table at `.parkedDicePose` with the hidden `0` sentinel.
    /// Reuses DiceRPG's existing focus-dice mechanism as the trigger (see
    /// `GameTableView`'s observer) rather than building a new, separate
    /// notion of "selected dice" for the table. `TabletopGame.addAction`
    /// syncs every change — including which slots are active — to every
    /// other participant automatically, the same way a physical toss
    /// already does, so every device ends up showing the same shape for
    /// this seat.
    ///
    /// Only d20 and d6 are backed by a table mesh, and each seat only has
    /// `GameSetup.maxDicePerType` slots per type; a set with dice of any
    /// other side count, or more than that many of one type (a homebrew
    /// "roll 8d6", or a GM batch-rolling for multiple NPCs at once), has the
    /// extras dropped rather than mirrored. See CODE_AUDIT §5.1 — this is
    /// surfaced via `diceOverflowCount` and a log, rather than silently
    /// discarded as before.
    func applyDiceRoll(_ diceModel: DiceModel) {
        guard let seat = localSeat,
              let d20Ids = setup.playerD20Ids[seat],
              let d6Ids = setup.playerD6Ids[seat],
              let seatPose = setup.seats.first(where: { $0.id == seat })?.initialState.pose
        else { return }

        // Compare the *resolved* side count (`RawDie.max`, public), not the
        // `Sides` enum case directly — a die authored through the sheet's
        // own UI can end up as `.number(20)` instead of the dedicated
        // `.twenty` case, and those don't compare equal to each other
        // despite meaning the same die.
        let d20Dice = diceModel.dice.filter { $0.die.max == 20 }
        let d6Dice = diceModel.dice.filter { $0.die.max == 6 }
        let usedD20Count = min(d20Dice.count, d20Ids.count)
        let usedD6Count = min(d6Dice.count, d6Ids.count)
        let layout = PlayerSeat.diceLayout(inFrontOf: seatPose, count: usedD20Count + usedD6Count)

        for (index, dieId) in d20Ids.enumerated() {
            guard let equipment = tabletopGame.equipment(of: Die20.self, matching: dieId) else { continue }
            if index < usedD20Count {
                let result = d20Dice[index].result.last ?? 1
                tabletopGame.addAction(
                    .updateEquipment(equipment, value: result, seatControl: nil, pose: layout[index], boundingBox: nil, context: 0)
                )
            } else {
                // Parks this slot off-table via its synced pose instead of
                // leaving `pose: nil` (no-op) and relying on a separate,
                // local-only `Entity.isEnabled` toggle — see the doc where
                // `updateDiceVisibility(using:)` used to live, just above
                // `applyDiceRoll`, for why.
                tabletopGame.addAction(
                    .updateEquipment(equipment, value: 0, seatControl: nil, pose: .parkedDicePose, boundingBox: nil, context: 0)
                )
            }
        }

        for (index, dieId) in d6Ids.enumerated() {
            guard let equipment = tabletopGame.equipment(of: Die.self, matching: dieId) else { continue }
            if index < usedD6Count {
                let result = d6Dice[index].result.last ?? 1
                tabletopGame.addAction(
                    .updateEquipment(equipment, value: result, seatControl: nil, pose: layout[usedD20Count + index], boundingBox: nil, context: 0)
                )
            } else {
                tabletopGame.addAction(
                    .updateEquipment(equipment, value: 0, seatControl: nil, pose: .parkedDicePose, boundingBox: nil, context: 0)
                )
            }
        }

        let overflowCount = diceModel.dice.count - usedD20Count - usedD6Count
        diceOverflowCount = overflowCount > 0 ? overflowCount : nil
        if overflowCount > 0 {
            Logger.gameTable.warning(
                "Focused dice set had \(overflowCount, privacy: .public) dice this table couldn't represent (unsupported sides, or more than \(GameSetup.maxDicePerType, privacy: .public) of one type at this seat); those results were not mirrored onto the table"
            )
        }
    }

    /// VoiceOver's "activate" gesture on a die entity (see `DiceComponent`,
    /// wired in `GameTableView`'s accessibility subscription) — the direct
    /// on-table toss gesture otherwise has no accessible equivalent. Picks a
    /// random result and applies it through the same `TabletopGame.addAction`
    /// path a physical toss uses — `GameObserver.actionIsPending` already
    /// plays the toss sound for any `Die20` update, the same as it does for
    /// `applyDiceRoll`'s. See CODE_AUDIT §8.2.
    func tossDieForAccessibility(dieId: EquipmentIdentifier, sides: Int) {
        let result = Int.random(in: 1...sides)
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

#endif
