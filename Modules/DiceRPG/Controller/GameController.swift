// @copyright André Trettin

import CoreRPG
import AVFoundation
import Foundation
import Synchronization
import Observation
import os.log
import RPGResources

@MainActor @Observable
final class DiceGameModel {
    init() {}
    
    let audioPlayer: AVPlayer = AVPlayer()
    var hiddenPlayers: [String] = []
    var playerDice: [DiceModel] = []
    var playerSupporterTiers: [UUID: SupporterTier] = [:]
    var masterDiceName: String?

    /// Cancelled and replaced on every roll so a rapid sequence of rolls can't queue up
    /// out-of-order widget updates. See CODE_AUDIT §3.3.
    @ObservationIgnored
    fileprivate var diceUpdateWidgetTask: Task<Void, Never>?

    func reset() {
        hiddenPlayers = []
        playerDice = []
        playerSupporterTiers = [:]
        masterDiceName = nil
    }
}

public protocol DiceGameStorable: Sendable {
    @MainActor func addGameDiceResult(
        data: NetworkCodableDataType,
        name: String,
        supporterTier: SupporterTier,
        isGameMaster: Bool
    ) -> (String?, ResultCategory?)
    func createGameData(for itemId: UUID, resultCategory: ResultCategory?) async throws -> NetworkCodableDataType
    func createVirtualGameData(
        numberOfSides: Int,
        name: String,
        resultCategory: ResultCategory
    ) async throws -> NetworkCodableDataType
    @MainActor func createGameDice(for diceId: UUID, gameDiceId: UUID?) -> UUID
    @MainActor func setFocusDice(on diceId: UUID?) async
    func updateGame(data: NetworkCodableDataType, hide: Bool, focus: Bool) async throws
    
    @MainActor func number(for diceId: UUID, result: String) -> Int
    @MainActor func validateForValue(diceId: UUID, compareValue: Int?)
    @MainActor func resetPlayerDice(to playerIds: [String])
}

struct GameController: Sendable {
    @MainActor init(itemController: ItemController, exportController: ExportController) {
        self.itemController = itemController
        self.exportController = exportController

        self.gameModel = ItemGameModel(itemDataModel: itemController.itemDataModel)
        self.diceGameModel = DiceGameModel()
    }

    let itemController: ItemController
    let exportController: ExportController

    let gameModel: ItemGameModel
    let diceGameModel: DiceGameModel
    
}

// gameItem(for:)/setGame(item:itemId:)/currentItem() come from
// ModuleGameControllable's default implementations — including
// currentItem(), which this bespoke copy previously omitted entirely.
// See CODE_AUDIT_Game §9.1.
extension GameController: ModuleGameControllable {}

extension GameController: GameControllable {
    var itemControllable: any ItemControllable { itemController as (any ItemControllable) }
    var exportControllable: any ExportControllable { exportController as ExportControllable }

    @MainActor func resetGameState() {
        diceGameModel.reset()
    }
}

extension GameController: DiceGameStorable {
    @discardableResult @MainActor
    func addGameDiceResult(
        data: NetworkCodableDataType,
        name: String,
        supporterTier: SupporterTier,
        isGameMaster: Bool
    ) -> (String?, ResultCategory?) {
        guard let diceResult = DiceResultModel.decodeData(of: data.data) else { return (nil, nil) }
        let dice = diceResult.diceModel.makeModel(withId: UUID())
        dice.name = name
        dice.applyResult(text: diceResult.values)
        
        if let index = diceGameModel.playerDice.firstIndex(where: { $0.id == dice.id || $0.name == name }) {
            let replacedId = diceGameModel.playerDice[index].id
            diceGameModel.playerSupporterTiers[replacedId] = nil
            diceGameModel.playerDice[index] = dice
        } else {
            diceGameModel.playerDice.insert(dice, at: 0)
        }
        diceGameModel.playerSupporterTiers[dice.id] = supporterTier
        if let index = gameModel.items.firstIndex(where: { $0 == dice.id || (gameModel.itemData[$0] as? DiceModel)?.name == name }) {
            gameModel.items.remove(at: index)
        }
        gameModel.items.insert(dice.id, at: 0)
        gameModel.itemData[dice.id] = dice
        if isGameMaster {
            diceGameModel.masterDiceName = name
        }
        return (diceResult.values, dice.resultCategory)
    }
    
    @MainActor
    func createDiceResult(for itemId: UUID, resultCategory: ResultCategory? = nil) async -> NetworkCodableDataType {
        if gameModel.itemData[itemId] == nil, let model = await itemControllable.item(for: itemId) {
            gameModel.itemData[model.id] = model
            gameModel.items.insert(model.id, at: 0)
        }
        let item = gameItem(for: itemId)
        item.resultCategory = resultCategory
        let diceResult = result(itemId: itemId)
        return NetworkCodableDataType(id: itemId, type: .dice, version: 0, data: diceResult.encodeData())
    }
    
    func createGameData(for itemId: UUID, resultCategory: ResultCategory?) async throws -> NetworkCodableDataType {
        let oldResultCategory = await applyResultCategory(resultCategory, for: itemId)
        let result = try await createGameData(for: itemId)
        await applyResultCategory(oldResultCategory, for: itemId)
        return result
    }

    @MainActor
    @discardableResult
    private func applyResultCategory(_ resultCategory: ResultCategory?, for itemId: UUID) -> ResultCategory? {
        guard let model = itemController.itemSync(for: itemId) else { return nil }
        let oldResultCategory = model.resultCategory
        model.resultCategory = resultCategory
        return oldResultCategory
    }

    func createVirtualGameData(
        numberOfSides: Int,
        name: String,
        resultCategory: ResultCategory
    ) async throws -> NetworkCodableDataType {
        let itemId = UUID()
        await createVirtualDiceModel(itemId: itemId, numberOfSides: numberOfSides, name: name, resultCategory: resultCategory)
        return try await createGameData(
            for: itemId,
            resultCategory: resultCategory
        )
    }

    @MainActor
    private func createVirtualDiceModel(itemId: UUID, numberOfSides: Int, name: String, resultCategory: ResultCategory) {
        let dice = DiceModel(
            id: itemId,
            name: name,
            category: .value,
            dice: [
                DieModel(
                    id: UUID(),
                    die: RawDie(.number(max(numberOfSides, 1)))
                )
            ],
            resultCategory: resultCategory
        )
        itemController.replaceForGame(
            model: dice,
            isInsert: true,
            policy: .memoryOnly
        )
    }
    
    @MainActor
    func createGameDice(for diceId: UUID, gameDiceId: UUID?) -> UUID {
        if let gameDiceId, gameModel.itemData[gameDiceId] != nil {
            return gameDiceId
        }
        let dice = itemController.itemOrEmpty(for: diceId).copy(withId: gameDiceId ?? UUID())
        dice.category = .value
        setGame(item: dice, itemId: dice.id)
        return dice.id
    }
    
    @MainActor func setFocusDice(on diceId: UUID?) async {
        if let diceId {
            await focus(on: diceId)
        } else {
            let gameDice = DiceModel.empty(UUID())
            gameDice.dice.append(DieModel.die20)
            setGame(item: gameDice, itemId: gameDice.id)
            await focus(on: gameDice.id)
        }
    }
    
    func updateGame(data: NetworkCodableDataType, hide: Bool, focus: Bool) async throws {
        try await updateGame(data: data, hide: hide, deep: false)
        if focus {
            await refocus(on: data.id)
        }
    }

    @MainActor
    private func refocus(on itemId: UUID) {
        if let index = gameModel.focusItemIds.firstIndex(where: { $0 == itemId }) {
            gameModel.focusItemIds.remove(at: index)
        }
        reset(for: itemId)
        gameModel.focusItemIds.insert(itemId, at: 0)
    }
    
    @MainActor
    func number(for diceId: UUID, result: String) -> Int {
        let dice = gameItem(for: diceId)
        dice.applyResult(text: result)
        setGame(item: dice, itemId: dice.id)
        return sumResult(itemId: diceId)
    }
    
    @MainActor
    func validateForValue(diceId: UUID, compareValue: Int?) {
        guard let compareValue, compareValue > 0 else { return }
        let validatedCompareValue = Double(compareValue)
        let model = gameItem(for: diceId)
        guard model.category == .value, model.compareValue != validatedCompareValue else { return }
        model.compareValue = validatedCompareValue
    }
    
    @MainActor
    func resetPlayerDice(to playerNames: [String]) {
        diceGameModel.playerDice = playerNames.compactMap { name in
            diceGameModel.playerDice.first { $0.name == name }
        }
        let activeDiceIDs = Set(diceGameModel.playerDice.map(\.id))
        diceGameModel.playerSupporterTiers = diceGameModel.playerSupporterTiers.filter {
            activeDiceIDs.contains($0.key)
        }
    }
}

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
    private static let diceSoundVolume: Float = 0.33

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
    private func diceName(for itemId: UUID, isOne: Bool) -> String {
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

        result.checked = sumResult > 0

        if coup(for: itemId) {
            result.result = .coup
        }
        
        return result
    }
    
    @MainActor
    func sumResult(itemId: UUID) -> Int {
        let item = gameItem(for: itemId)
        let orderedDice = reorder(for: itemId)
        var result = 0
        if item.sumUp {
            if item.canPercentDice, item.percentDice {
                var ten = orderedDice[0].result.last ?? 0
                var one = orderedDice[1].result.last ?? 0
                ten = ten == 10 ? 0 : ten
                one = one == 10 ? 0 : one
                result = ten * 10 + one
                if result == 0 {
                    result = 100
                }
            } else {
                orderedDice.enumerated().forEach { index, die in
                    let maxValue = maxValuePerDice(for: index + 1, itemId: itemId)
                    die.result.forEach { diceValue in
                        result += resolvedDiceValue(for: diceValue, maxValue: maxValue, rerollOptions: item.rerollOptions)
                    }
                }
                result = result.saturatingSum(item.modifier.saturatingInt)
            }
        }
        return result
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
            return orderedDice.map { ($0.id, [true]) }
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
        let result = allResults.reduce(0) { $0 + $1 }
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
        let item = gameItem(for: itemId)
        let maxDieValue = item.dice.first?.die.max ?? 1
        guard item.addDiceEvery > 0 else { return maxDieValue }
        let maxValue = item.compareValue.saturatingInt
        return max(0, min((maxValue + maxDieValue) - item.addDiceEvery * index, maxDieValue))
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
        let item = gameItem(for: itemId)
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
        gameItem(for: itemId).dice = gameItem(for: itemId).dice.map { die in
            die.resetResults()
        }
    }
    
    @MainActor
    func roll(die: DieModel?, for itemId: UUID) {
        if let diceUrl = Resources.bundle.url(forResource: diceName(for: itemId, isOne: die != nil), withExtension: "m4a") {
            let item = AVPlayerItem(url: diceUrl)
            diceGameModel.audioPlayer.replaceCurrentItem(with: item)
            diceGameModel.audioPlayer.play()
            diceGameModel.audioPlayer.volume = Self.diceSoundVolume
        }

        let item = gameItem(for: itemId)
        if let die, let index = item.dice.firstIndex(where: { $0.id == die.id }) {
            gameItem(for: itemId).dice[index] = die.roll(rerollOptions: item.rerollOptions)
        } else {
            gameItem(for: itemId).dice = gameItem(for: itemId).dice.map { die in
                die.roll(rerollOptions: item.rerollOptions)
            }
        }
        // `Task { }` (unlike `.detached`) inherits the caller's isolation —
        // since this call is made from @MainActor `roll(die:for:)`,
        // `nonisolated` alone was not actually keeping this off the main
        // actor (see CODE_AUDIT_Game §3.1's mechanism). `.detached` gives it
        // a genuine off-main starting point for the UserDefaults JSON I/O;
        // `diceResult` is computed here on the main actor (result(itemId:)
        // is itself @MainActor) and handed in by value.
        // See CODE_AUDIT_Game §3.6.
        let diceResult = result(itemId: itemId)
        diceGameModel.diceUpdateWidgetTask?.cancel()
        diceGameModel.diceUpdateWidgetTask = Task.detached(priority: .utility) { [self] in
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
