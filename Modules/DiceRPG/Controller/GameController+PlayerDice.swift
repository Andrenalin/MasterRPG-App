// @copyright André Trettin

import CoreRPG
import AVFoundation
import Foundation
import Synchronization
import Observation
import os.log
import RPGResources

// Split out of GameController.swift — see CODE_AUDIT_19 §9.23.

// MARK: - Player Dice

extension GameController {
    @MainActor
    func canEditDice(itemId: UUID, isGameMode: Bool) -> Bool {
        !isGameMode || gameItem(for: itemId).category != .table
    }
    
    @MainActor
    func hasResults(itemId: UUID) -> Bool {
        !gameItem(for: itemId).dice.flatMap { $0.result }.isEmpty
    }
    
    @MainActor
    func isFocusedDice(itemId: UUID) -> Bool {
        gameModel.focusItemIds.contains(itemId)
    }
    
    @MainActor
    func isPlayerDice(itemId: UUID) -> Bool {
        gameModel.focusItemIds.isEmpty && gameModel.items.contains(where: { $0 == itemId })
    }
    
    @MainActor
    func isPlayerHidden(playerId: UUID) -> Bool {
        let name = gameItem(for: playerId).name
        return diceGameModel.hiddenPlayers.contains { $0 == name }
    }

    @MainActor
    func supporterTier(playerId: UUID) -> SupporterTier {
        diceGameModel.playerSupporterTiers[playerId] ?? .none
    }
    
    @MainActor
    func toggleHidden(playerId: UUID) async {
        let name = gameItem(for: playerId).name
        if let hiddenIndex = diceGameModel.hiddenPlayers.firstIndex(where: { $0 == name }) {
            diceGameModel.hiddenPlayers.remove(at: hiddenIndex)
        } else {
            diceGameModel.hiddenPlayers.append(name)
        }
    }
}

extension GameController {
    /// Brief pause before an unsynced (`rollSynced == false`) roll actually fires, giving any
    /// roll-triggering UI (e.g. a shake/tap animation) a moment to reset first.
    /// See CODE_AUDIT §9.14.
    private static let localRollStartDelay: Duration = .seconds(0.1)

    /// Playback volume for the physical dice-roll sound effect.
    /// See CODE_AUDIT_Game §9.14.
    static let diceSoundVolume: Float = 0.33

    @MainActor
    func resetCompareValue(of itemId: UUID, value: Int) async {
        let source = gameItem(for: itemId)
        guard source.compareValue != Double(value) else { return }
        let item = source.copy(withId: UUID())
        item.compareValue = Double(value)
        setGame(item: item, itemId: item.id)
        await focus(on: [item.id])
    }
    
    @MainActor
    func remove(die: DieModel, from itemId: UUID) {
        let item = gameItem(for: itemId)
        guard let index = item.dice.firstIndex(where: { $0.id == die.id }) else { return }
        item.dice.remove(at: index)
    }
    
    @MainActor
    func rollDice(itemId: UUID, networkActions: NetworkActions? = nil, resultCategory: ResultCategory? = nil, rollSynced: Bool = false) {
        reset(for: itemId)
        
        let rollFunction = {
            roll(die: nil, for: itemId)
            
            if let networkActions {
                Task {
                    let sendedResult = resultCategory ?? gameItem(for: itemId).resultCategory ?? ResultCategory(id: itemId, module: itemController.config.module)
                    let result = await createDiceResult(for: itemId, resultCategory: sendedResult)
                    networkActions.game(result, .generic, nil)
                }
            }
        }
        
        if rollSynced {
            rollFunction()
        } else {
            Task { @MainActor in
                // `try?` previously swallowed cancellation and rolled
                // anyway — a roll issued during teardown (or any other
                // cancellation of this task) must not still fire.
                // See CODE_AUDIT_Game §3.7.
                do {
                    try await Task.sleep(for: Self.localRollStartDelay)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                rollFunction()
            }
        }
    }
    
    /// The 9 single-die roll-sound variants, indexed 0-8. Kept as one array
    /// (raw values, not the `Resources.Dice` cases themselves — the enum
    /// isn't `Sendable`) so the sound count and the selection range
    /// (`RawDie.roll(.number(...))`) can never drift apart the way two
    /// independently-maintained switch arms could. See CODE_AUDIT_Game §9.14.
    private static let singleDieSounds: [String] = [
        RPGResources.Resources.Dice.d20_1.rawValue, RPGResources.Resources.Dice.d20_2.rawValue,
        RPGResources.Resources.Dice.d20_3.rawValue, RPGResources.Resources.Dice.d20_4.rawValue,
        RPGResources.Resources.Dice.d20_5.rawValue, RPGResources.Resources.Dice.d20_6.rawValue,
        RPGResources.Resources.Dice.d20_7.rawValue, RPGResources.Resources.Dice.d20_8.rawValue,
        RPGResources.Resources.Dice.d20_9.rawValue
    ]

    /// The 6 multi-die roll-sound variants, indexed 0-5. See CODE_AUDIT_Game §9.14.
    private static let multiDieSounds: [String] = [
        RPGResources.Resources.Dice.TwoD20_1.rawValue, RPGResources.Resources.Dice.TwoD20_2.rawValue,
        RPGResources.Resources.Dice.TwoD20_3.rawValue, RPGResources.Resources.Dice.TwoD20_4.rawValue,
        RPGResources.Resources.Dice.TwoD20_5.rawValue, RPGResources.Resources.Dice.TwoD20_6.rawValue
    ]

    @MainActor
    func diceName(for itemId: UUID, isOne: Bool) -> String {
        if isOne || gameItem(for: itemId).dice.count == 1 {
            let sounds = Self.singleDieSounds
            let index = RawDie.roll(.number(sounds.count)) - 1
            return sounds[max(0, min(index, sounds.count - 1))]
        }
        let sounds = Self.multiDieSounds
        let index = RawDie.roll(.number(sounds.count)) - 1
        return sounds[max(0, min(index, sounds.count - 1))]
    }
}
