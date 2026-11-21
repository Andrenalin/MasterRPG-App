// @copyright André Trettin

import CoreRPG
import AVFoundation
import Foundation
import Synchronization
import Observation
import os.log
import RPGResources

// Split out of GameController.swift — see CODE_AUDIT_19 §9.23.

// MARK: - Dice Result

extension GameController {
    @MainActor
    func calculate(itemId: UUID) -> DiceResultModel {
        let item = gameItem(for: itemId)
        var result = DiceResultModel(diceModel: DiceSnapshot(item))
        guard item.dice.reduce(0, { $0 + $1.result.count }) > 0 else { return result }
        
        result.result = .rolled
        let text = item.dice.compactMap {
            guard !$0.result.isEmpty else { return nil }
            return $0.result.map { "\($0)" }.joined(separator: ",")
        }.joined(separator: "|")
        result.values = text
        
        let succeed = !fumble(for: itemId)
        guard succeed else {
            result.result = .fumble
            return result
        }
        let sumResult = sumResult(itemId: itemId)
        result.sum = sumResult

        result.checked = isChecked(item: item, sum: sumResult)

        if coup(for: itemId) {
            result.result = .coup
        }
        
        return result
    }
    
    /// Whether a roll with this `sum` counts as a success. With "Add dice" on, the compare value is
    /// spent per die (`maxValuePerDice`) and a sum above 0 is a success. Otherwise a "Check for"
    /// option compares the sum with the value; without one any positive sum succeeds.
    /// See CODE_AUDIT_26 §5.5.
    @MainActor
    func isChecked(item: DiceModel, sum: Int) -> Bool {
        guard item.sumUp, item.addDiceEvery == 0, item.compareOption != .off else { return sum > 0 }
        return item.compareOption.check(value: Double(sum), against: item.compareValue)
    }

    @MainActor
    func sumResult(itemId: UUID) -> Int {
        sumResult(of: gameItem(for: itemId))
    }

    /// The sum of the rolled dice of `item`: reroll overrides, percent dice, the per-die maximum
    /// and the modifier. Works on any dice model, so a roll that is not a game item (a table's
    /// dice) is counted by the same rules as a player's. See CODE_AUDIT_22 §5.7.
    @MainActor
    func sumResult(of item: DiceModel) -> Int {
        let orderedDice = reorder(item)
        var result = 0
        if item.sumUp {
            if item.canPercentDice, item.percentDice {
                // The tens and the ones die go through the same reroll overrides and per-die
                // maximum as any other die; the modifier is added and the result stays a
                // percentage (1…100). See CODE_AUDIT §5.16.
                let ten = percentDigit(of: orderedDice[0], index: 1, item: item)
                let one = percentDigit(of: orderedDice[1], index: 2, item: item)
                var percent = ten * 10 + one
                if percent == 0 {
                    percent = 100
                }
                result = min(100, max(1, percent.saturatingSum(item.modifier.saturatingInt)))
            } else {
                orderedDice.enumerated().forEach { index, die in
                    let maxValue = maxValuePerDice(for: index + 1, item: item)
                    die.result.forEach { diceValue in
                        // Saturating: a decoded reroll value can be any `Int`. See CODE_AUDIT_21 §6.7.
                        result = result.saturatingSum(resolvedDiceValue(for: diceValue, maxValue: maxValue, rerollOptions: item.rerollOptions))
                    }
                }
                result = result.saturatingSum(item.modifier.saturatingInt)
            }
        }
        return result
    }
    
    /// One digit (0…9) of a percent roll: the die's last rolled value after the reroll overrides
    /// and the per-die maximum, with a 10 standing for 0.
    @MainActor
    private func percentDigit(of die: DieModel, index: Int, item: DiceModel) -> Int {
        let rolled = die.result.last ?? 0
        let maxValue = maxValuePerDice(for: index, item: item)
        let resolved = resolvedDiceValue(for: rolled, maxValue: maxValue, rerollOptions: item.rerollOptions)
        return min(9, max(0, resolved == 10 ? 0 : resolved))
    }

    /// Whether a percent die counts as a success: its value was not dropped by the per-die maximum.
    @MainActor
    private func percentDieCounts(_ die: DieModel, index: Int, item: DiceModel) -> Bool {
        let rolled = die.result.last ?? 0
        let maxValue = maxValuePerDice(for: index, item: item)
        return resolvedDiceValue(for: rolled, maxValue: maxValue, rerollOptions: item.rerollOptions) > 0
    }

    @MainActor
    func coup(for itemId: UUID) -> Bool {
        let item = gameItem(for: itemId)
        return matchesSpecialValue(onlyFirstDie: item.coupOnlyOnFirstDie, values: item.coupValues, dice: item.dice)
    }

    // Shared by `DiceRoll`/`DicePlayer`, which previously each implemented
    // this identical lookup themselves. See CODE_AUDIT §9.5.
    @MainActor
    func resultColor(for dieId: UUID, itemId: UUID) -> [Bool] {
        diceSuccess(for: itemId).first(where: { $0.0 == dieId })?.1 ?? []
    }

    @MainActor
    func diceSuccess(for itemId: UUID) -> [(UUID, [Bool])] {
        let item = gameItem(for: itemId)
        guard item.dice.reduce(0, { $0 + $1.result.count }) > 0,
              !fumble(for: itemId),
              item.sumUp else { return [] }
        let orderedDice = reorder(for: itemId)
        if item.canPercentDice, item.percentDice {
            return orderedDice.enumerated().map { index, die in
                (die.id, [percentDieCounts(die, index: index + 1, item: item)])
            }
        }
        return orderedDice.enumerated().map { index, die in
            let maxValue = maxValuePerDice(for: index + 1, itemId: itemId)
            let dieResult = die.result.map { diceValue in
                resolvedDiceValue(for: diceValue, maxValue: maxValue, rerollOptions: item.rerollOptions) > 0
            }
            return (die.id, dieResult)
        }
    }

    @MainActor
    func fumble(for itemId: UUID) -> Bool {
        let item = gameItem(for: itemId)
        return matchesSpecialValue(onlyFirstDie: item.fumbleOnlyOnFirstDie, values: item.fumbleValues, dice: item.dice)
    }

    /// Shared by `coup(for:)`/`fumble(for:)`: both check whether the rolled dice match a
    /// special value, either on an individual die (respecting `onlyFirstDie`) or on their sum.
    @MainActor
    private func matchesSpecialValue(onlyFirstDie: Bool, values: [DiceModel.CoupFumbleOption], dice: [DieModel]) -> Bool {
        let allResults = onlyFirstDie ? [dice.first?.result.first ?? 0] : dice.compactMap { $0.result.first }
        let matchesDiceValue = allResults.contains(where: { value in values.contains(where: { $0.isDiceValue(value) }) })
        if matchesDiceValue { return true }
        let result = allResults.reduce(0) { $0.saturatingSum($1) }
        return values.contains(where: { $0.isResultValue(result) })
    }

    /// Shared by `sumResult(itemId:)`/`diceSuccess(for:)`: a rolled die value counts as its
    /// reroll-option override when one applies, otherwise itself if within `maxValue`, else 0.
    @MainActor
    private func resolvedDiceValue(for diceValue: Int, maxValue: Int, rerollOptions: [DiceModel.RerollOption]) -> Int {
        if let rerollOption = rerollOptions.first(where: { $0.number == diceValue }) {
            return rerollOption.maxDiceValue ? maxValue : rerollOption.value
        }
        return diceValue <= maxValue ? diceValue : 0
    }
    
    @MainActor
    func maxValuePerDice(for index: Int, itemId: UUID) -> Int {
        maxValuePerDice(for: index, item: gameItem(for: itemId))
    }

    @MainActor
    func maxValuePerDice(for index: Int, item: DiceModel) -> Int {
        let maxDieValue = item.dice.first?.die.max ?? 1
        guard item.addDiceEvery > 0 else { return maxDieValue }
        let maxValue = item.compareValue.saturatingInt
        // `addDiceEvery` is decoded as it comes. See CODE_AUDIT_21 §6.7.
        let reduction = item.addDiceEvery.saturatingProduct(index)
        return max(0, min(maxValue.saturatingSum(maxDieValue).saturatingSum(reduction == .min ? .max : -reduction), maxDieValue))
    }
    
    @MainActor
    func result(itemId: UUID) -> DiceResultModel {
        calculate(itemId: itemId)
    }
    
    @MainActor
    func resultText(itemId: UUID) -> String {
        let diceResult = result(itemId: itemId)
        guard diceResult.result != .notRolled else {
            return String(localized: diceResult.result.localizedTitle)
        }
        let item = gameItem(for: itemId)
        var compareText = ""
        if item.compareOption != .off {
            compareText = "\(item.compareOption.rawText)\(item.compareValue.saturatingInt)"
        }
        var text = "\(diceResult.values)\(compareText)"
        var specialText = ""
        if diceResult.result == .coup || diceResult.result == .fumble {
            specialText = " \(String(localized: diceResult.result.localizedTitle))"
        }
        if diceResult.result == .fumble {
            text += specialText
        } else {
            text += " ∑\(diceResult.sum)\(specialText)"
        }
        if item.compareOption != .off {
            text.append("\(diceResult.checked ? "✅" : "❌")")
        }
        return text
    }
    
    @MainActor
    func reorder(for itemId: UUID) -> [DieModel] {
        reorder(gameItem(for: itemId))
    }

    @MainActor
    func reorder(_ item: DiceModel) -> [DieModel] {
        guard item.reorderDice else { return item.dice }
        let dice = item.dice.sorted {
            var first = $0.result.first ?? 0
            var second = $1.result.first ?? 0
            if let firstReroll = item.rerollOptions.first(where: { $0.number == first }) {
                if firstReroll.maxDiceValue {
                    first = $0.die.max + 1
                } else {
                    first = firstReroll.value
                }
            }
            if let secondReroll = item.rerollOptions.first(where: { $0.number == second }) {
                if secondReroll.maxDiceValue {
                    // The second die's own maximum. See CODE_AUDIT_19 §5.15.
                    second = $1.die.max + 1
                } else {
                    second = secondReroll.value
                }
            }
            return first > second
        }
        return dice
    }
    
    @MainActor
    func reset(for itemId: UUID) {
        let item = gameItem(for: itemId)
        item.setRolledDice(item.dice.map { die in
            die.resetResults()
        })
    }
    
    /// `playsSound` is off for a die tossed on the 3D table, which makes its own sound there.
    @MainActor
    func roll(die: DieModel?, for itemId: UUID, playsSound: Bool = true) {
        if playsSound, let diceUrl = RPGResources.Resources.bundle.url(forResource: diceName(for: itemId, isOne: die != nil), withExtension: "m4a") {
            let item = AVPlayerItem(url: diceUrl)
            diceGameModel.audioPlayer.replaceCurrentItem(with: item)
            diceGameModel.audioPlayer.play()
            diceGameModel.audioPlayer.volume = Self.diceSoundVolume
        }

        let item = gameItem(for: itemId)
        // Rolled state does not move the update marker (also for a library set rolled outside a
        // game, which is the stored model itself). See CODE_AUDIT_26 §5.35.
        var rolledDice = item.dice
        if let die, let index = rolledDice.firstIndex(where: { $0.id == die.id }) {
            rolledDice[index] = die.roll(rerollOptions: item.rerollOptions)
        } else {
            rolledDice = rolledDice.map { die in
                die.roll(rerollOptions: item.rerollOptions)
            }
        }
        item.setRolledDice(rolledDice)
        // A plain `Task { }` inherits the caller's isolation —
        // since this call is made from @MainActor `roll(die:for:)`,
        // `nonisolated` alone was not actually keeping this off the main
        // actor (see CODE_AUDIT_Game §3.1's mechanism). `@concurrent` gives it
        // a genuine off-main starting point for the UserDefaults JSON I/O;
        // `diceResult` is computed here on the main actor (result(itemId:)
        // is itself @MainActor) and handed in by value.
        // See CODE_AUDIT_Game §3.6.
        let diceResult = result(itemId: itemId)
        diceGameModel.diceUpdateWidgetTask?.cancel()
        diceGameModel.diceUpdateWidgetTask = Task(priority: .utility) { @concurrent [self] in
            await diceUpdateWidget(diceResult: diceResult)
        }
    }

    nonisolated private func diceUpdateWidget(diceResult: DiceResultModel) async {
#if !os(tvOS)
        // A newer roll's task cancels the previous one (see the call site),
        // but without this check the previous roll's write below would still
        // run to completion and could overwrite the newer roll's saved
        // result, leaving the Home Screen/Lock Screen widget showing a stale
        // dice result. See CODE_AUDIT_13 §3.2.
        guard !Task.isCancelled else { return }

        // Update widget. Two overlapping tasks (the cancel above only stops one that has not
        // started yet) must not interleave their read-modify-write, and an older roll must
        // never overwrite a newer one. See CODE_AUDIT_15 §3.14.
        guard DiceConfiguration.recordLastRoll(diceResult) else { return }

        // Reload widgets
        DiceWidgetReloader.reloadDiceWidgets()

#endif
    }
}
