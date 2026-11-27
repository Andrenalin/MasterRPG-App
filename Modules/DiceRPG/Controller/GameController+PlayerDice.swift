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
        diceGameModel.hiddenPlayers.contains(hiddenKey(for: playerId))
    }

    @MainActor
    private func hiddenKey(for playerId: UUID) -> UUID {
        diceGameModel.playerDiceSenders[playerId] ?? playerId
    }

    @MainActor
    func supporterTier(playerId: UUID) -> SupporterTier {
        diceGameModel.playerSupporterTiers[playerId] ?? .none
    }
    
    @MainActor
    func toggleHidden(playerId: UUID) {
        let key = hiddenKey(for: playerId)
        if diceGameModel.hiddenPlayers.contains(key) {
            diceGameModel.hiddenPlayers.remove(key)
        } else {
            diceGameModel.hiddenPlayers.insert(key)
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
            shareRoll(of: itemId, networkActions: networkActions, resultCategory: resultCategory)
        }
        
        diceGameModel.pendingRollTasks[itemId]?.cancel()
        diceGameModel.pendingRollTasks[itemId] = nil
        if rollSynced {
            rollFunction()
        } else {
            diceGameModel.pendingRollTasks[itemId] = Task { @MainActor in
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
                diceGameModel.pendingRollTasks[itemId] = nil
                rollFunction()
            }
        }
    }
    
    /// Sends a dice set's current result to the game, as every roll does.
    @MainActor
    func shareRoll(of itemId: UUID, networkActions: NetworkActions?, resultCategory: ResultCategory? = nil) {
        guard let networkActions else { return }
        Task {
            let sendedResult = resultCategory ?? gameItem(for: itemId).resultCategory ?? ResultCategory(id: itemId, module: itemController.config.module)
            let result = await createDiceResult(for: itemId, resultCategory: sendedResult)
            networkActions.game(result, .generic, nil)
        }
    }

    @MainActor
    func rollDie(_ dieId: UUID, of diceId: UUID, networkActions: NetworkActions?) -> Int? {
        guard gameModel.itemData[diceId] is DiceModel,
              let die = gameItem(for: diceId).dice.first(where: { $0.id == dieId }) else { return nil }
        roll(die: die.resetResults(), for: diceId, playsSound: false)
        shareRoll(of: diceId, networkActions: networkActions)
        return gameItem(for: diceId).dice.first(where: { $0.id == dieId })?.result.last
    }

    @MainActor
    func showsResult(for diceId: UUID) -> Bool {
        guard gameModel.itemData[diceId] is DiceModel else { return false }
        let item = gameItem(for: diceId)
        return item.sumUp || item.compareOption != .off
    }

    @MainActor
    func playerDiceId(named playerName: String) -> UUID? {
        playerDiceId(senderId: nil, named: playerName)
    }

    /// The visible dice the player last shared: found by the sending device when it is known, and
    /// by the name only among dice whose sender is not known, so two players with the same name
    /// never get each other's dice. See CODE_AUDIT_29 §5.7.
    @MainActor
    func playerDiceId(senderId: UUID?, named playerName: String) -> UUID? {
        guard let dice = playerDice(senderId: senderId, named: playerName),
              !isPlayerHidden(playerId: dice.id) else { return nil }
        return dice.id
    }

    /// `playerDiceId(senderId:named:)` without the hidden-player filter.
    @MainActor
    func playerDice(senderId: UUID?, named playerName: String) -> DiceModel? {
        let senders = diceGameModel.playerDiceSenders
        if let senderId, let dice = diceGameModel.playerDice.first(where: { senders[$0.id] == senderId }) {
            return dice
        }
        return diceGameModel.playerDice.first { $0.name == playerName && senders[$0.id] == nil }
    }

    @MainActor
    var sharedPlayerDice: [DiceModel] {
        diceGameModel.playerDice
    }

    @MainActor
    func playerDiceSenderId(for diceId: UUID) -> UUID? {
        diceGameModel.playerDiceSenders[diceId]
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
