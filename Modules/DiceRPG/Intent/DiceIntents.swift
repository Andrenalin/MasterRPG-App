// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import Foundation

// MARK: - Free rolls

/// Rolls one die of a fixed type. The widget has its own `RollDiceIntent` (App Intents metadata is
/// extracted per target); this one runs in the app, so it can join a running game.
public struct RollDiceIntent: AppIntent {
    public static let title: LocalizedStringResource = "Roll Dice"
    public static let description = IntentDescription(
        "Rolls one die and says the result. While a game runs, the roll is shared with the players.",
        categoryName: "Dice",
        searchKeywords: ["d20", "d6", "die", "roll"]
    )
    public static let supportedModes: IntentModes = .background

    @Parameter(title: "Dice Type", default: .d20)
    public var diceType: IntentDiceType

    @Dependency var root: DiceRootModel

    public init(diceType: IntentDiceType) {
        self.diceType = diceType
    }

    public init() {
        self.diceType = .d20
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let die = DieModel.die(sides: diceType.rawDie.max)
        let result = root.rollFromIntent(dice: [die], modifier: 0, name: diceType.rawValue)
        return .result(value: result.sum, dialog: DiceRollDialog.dialog(name: diceType.rawValue, result: result))
    }
}

/// Rolls dice notation ("3d6+2", "2d20", "d100") said to Siri or passed by a shortcut.
/// See CODE_AUDIT_AppIntents3 §4.6.
public struct RollDiceExpressionIntent: AppIntent {
    public static let title: LocalizedStringResource = "Roll Dice Expression"
    public static let description = IntentDescription(
        "Rolls dice written in dice notation, like 3d6+2 or 2d20, and says the total. While a game runs, the roll is shared with the players.",
        categoryName: "Dice",
        searchKeywords: ["notation", "modifier", "d20", "roll"]
    )
    public static let supportedModes: IntentModes = .background

    public static var parameterSummary: some ParameterSummary {
        Summary("Roll \(\.$expression)")
    }

    @Parameter(
        title: "Dice",
        description: "Dice notation such as 3d6+2, 2d20 or d100.",
        requestValueDialog: .localized("Which dice should be rolled, for example 3d6 plus 2?", bundle: .module)
    )
    public var expression: String

    @Dependency var root: DiceRootModel

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        // A misheard or mistyped expression asks again instead of rolling something else.
        guard let dice = DiceExpression(expression) else {
            throw $expression.needsValueError(.localized("I couldn't read those dice. Which dice should be rolled, for example 3d6 plus 2?", bundle: .module))
        }
        let result = root.rollFromIntent(dice: dice.dieModels, modifier: dice.modifier, name: dice.text)
        return .result(value: result.sum, dialog: DiceRollDialog.dialog(name: dice.text, result: result))
    }
}

/// Rolls dice that are not a saved set for an App Intent and records them as the last roll the
/// widget shows.
///
/// The app's and the widget's `RollDiceIntent` each had their own copy of this, and the app's
/// copy wrote the result without the newest-wins check. The two intents and their dice-type
/// enums stay separate declarations: App Intents metadata is extracted per target.
/// See CODE_AUDIT_18 §3.19, CODE_AUDIT_21 §5.23.
public enum DiceIntentRoll {
    /// Returns the rolled value.
    @discardableResult
    public static func rollAndRecord(sides: Int, name: String) -> Int {
        rollAndRecord(dice: [DieModel.die(sides: sides)], modifier: 0, name: name).sum
    }

    static func rollAndRecord(dice: [DieModel], modifier: Int, name: String) -> DiceResultModel {
        let rolled = dice.map { $0.roll(resetResults: true, rerollOptions: []) }
        let values = rolled.map { $0.result.first ?? $0.die.max }
        let sum = values.reduce(modifier) { $0.saturatingSum($1) }
        let snapshot = DiceSnapshot(id: UUID(), name: name, dice: rolled, modifier: Double(modifier))
        let roll = DiceResultModel(
            diceModel: snapshot,
            result: .rolled,
            values: values.map(String.init).joined(separator: "|"),
            sum: sum,
            checked: false,
            timeStamp: Date()
        )
        // Newest wins: a plain load-mutate-save could replace a newer roll.
        if DiceConfiguration.recordLastRoll(roll) {
            DiceWidgetReloader.reloadDiceWidgets()
        }
        return roll
    }
}

extension DiceRootModel {
    /// The game dice set the free rolls from Siri use, one per run: every roll replaces it, so
    /// rolling by voice does not add a set to the game per roll.
    private static let intentRollId = UUID()

    /// A roll from Siri or Shortcuts that is not a saved set. While a game runs it is rolled as a
    /// game dice set and shared with the players like a roll on the sheet; otherwise it is only
    /// recorded as the widget's last roll. See CODE_AUDIT_AppIntents3 §5.3.
    @MainActor
    func rollFromIntent(dice: [DieModel], modifier: Int, name: String) -> DiceResultModel {
        guard let networkActions = IntentGameContext.networkActions() else {
            return DiceIntentRoll.rollAndRecord(dice: dice, modifier: modifier, name: name)
        }
        let model = DiceModel(id: Self.intentRollId, name: name, category: .value, dice: dice, modifier: Double(modifier))
        gameController.setGame(item: model, itemId: model.id)
        gameController.rollDice(itemId: model.id, networkActions: networkActions, rollSynced: true)
        return gameController.result(itemId: model.id)
    }

    /// A saved set, rolled the way the sheet rolls it and shared while a game runs.
    @MainActor
    @discardableResult
    func rollFromIntent(diceId: UUID) -> DiceResultModel {
        // `rollDice(rollSynced: true)` runs synchronously and schedules the widget's write itself
        // through the tracked `diceUpdateWidgetTask`. See CODE_AUDIT.md §3.5.
        gameController.rollDice(itemId: diceId, networkActions: IntentGameContext.networkActions(), rollSynced: true)
        return gameController.result(itemId: diceId)
    }
}

/// What Siri says after a roll. `full` is spoken on a device without a screen, so it names the
/// dice and the single values and has no emoji; `supporting` is the short line next to the card.
/// See CODE_AUDIT_AppIntents3 §4.12.
enum DiceRollDialog {
    static func dialog(name: String, result: DiceResultModel) -> IntentDialog {
        let values = spokenValues(result.values)
        let showsValues = values.contains(",") || result.diceModel.modifier != 0
        let sum = result.sum
        switch result.result {
        case .coup:
            return showsValues
                ? .localized(full: "Critical success. \(name): \(sum), from \(values).", supporting: "Critical success: \(sum)", bundle: .module)
                : .localized(full: "Critical success. \(name): \(sum).", supporting: "Critical success: \(sum)", bundle: .module)
        case .fumble:
            return .localized(full: "Critical failure. \(name) rolled \(values).", supporting: "Critical failure", bundle: .module)
        case .rolled, .notRolled:
            return showsValues
                ? .localized(full: "\(name): \(sum), from \(values).", supporting: "Rolled \(sum)", bundle: .module)
                : .localized(full: "\(name): \(sum).", supporting: "Rolled \(sum)", bundle: .module)
        }
    }

    /// `3|5,2` (dice separated by `|`, rerolls by `,`) as `3, 5, 2`.
    static func spokenValues(_ values: String) -> String {
        values.split { $0 == "|" || $0 == "," }.joined(separator: ", ")
    }
}

// MARK: - Last roll

/// Reports the last dice roll (the same result the widget displays). There is no in-app history
/// screen to open. See CODE_AUDIT §5.2.
public struct ShowDiceHistoryIntent: AppIntent {
    public static let title: LocalizedStringResource = "Show Last Roll"
    public static let description = IntentDescription(
        "Says the result of your last dice roll, the one the dice widget shows.",
        categoryName: "Dice",
        searchKeywords: ["history", "result", "roll"]
    )
    public static let supportedModes: IntentModes = .background

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let lastRoll = DiceConfiguration.loadFromUserDefaults().lastRoll else {
            return .result(dialog: .localized("You haven't rolled any dice yet.", bundle: .module))
        }
        let name = lastRoll.diceModel.name.isEmpty ? lastRoll.diceModel.dice.first?.die.text ?? "" : lastRoll.diceModel.name
        return .result(dialog: .localized("Last roll — \(name): \(lastRoll.sum)", bundle: .module))
    }
}

// MARK: - Dice Type for Intents

/// Simple dice type enum that conforms to AppEnum for use in intents
public enum IntentDiceType: String, AppEnum {
    case d4 = "D4"
    case d6 = "D6"
    case d8 = "D8"
    case d10 = "D10"
    case d12 = "D12"
    case d20 = "D20"
    case d100 = "D100"

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Dice Type")
    }

    public static var caseDisplayRepresentations: [IntentDiceType: DisplayRepresentation] {
        [
            .d4: DisplayRepresentation(title: "D4", subtitle: "4-sided die"),
            .d6: DisplayRepresentation(title: "D6", subtitle: "6-sided die"),
            .d8: DisplayRepresentation(title: "D8", subtitle: "8-sided die"),
            .d10: DisplayRepresentation(title: "D10", subtitle: "10-sided die"),
            .d12: DisplayRepresentation(title: "D12", subtitle: "12-sided die"),
            .d20: DisplayRepresentation(title: "D20", subtitle: "20-sided die"),
            .d100: DisplayRepresentation(title: "D100", subtitle: "100-sided die")
        ]
    }
}

#endif
