// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import Foundation

// MARK: - Shared App Intents (accessible from both app and widget)

/// App Intent for rolling simple dice (D4-D20)
public struct RollDiceIntent: AppIntent {
    public static let title: LocalizedStringResource = "Roll Dice"
    public static let description = IntentDescription("Roll a dice and show the result")
    
    // iOS 18: Support for interactive widgets
    public static let isDiscoverable = true
    public static let openAppWhenRun = false
    
    @Parameter(title: "Dice Type", default: .d20)
    public var diceType: IntentDiceType
    
    public init(diceType: IntentDiceType) {
        self.diceType = diceType
    }
    
    public init() {
        self.diceType = .d20
    }
    
    // Previously opened a hardcoded "gamerpg://..." URL — a scheme the app
    // never registers (the real scheme is `URL.appScheme`, "RPG") — so this
    // shortcut silently did nothing. Rolling a raw die and reporting the
    // result directly needs no app-side navigation at all. See CODE_AUDIT §5.2.
    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let die = DieModel(id: UUID(), die: diceType.rawDie)
        let rollValue = die.die.roll()
        let rolledDie = die.applyResult(values: [rollValue])
        let snapshot = DiceSnapshot(id: UUID(), name: diceType.rawValue, dice: [rolledDie])

        var config = DiceConfiguration.loadFromUserDefaults()
        config.lastRoll = DiceResultModel(diceModel: snapshot, result: .rolled, values: "\(rollValue)", sum: rollValue, checked: false)
        config.selectedDice = snapshot
        config.save()
        DiceWidgetReloader.reloadDiceWidgets()

        let dialog: IntentDialog = "🎲 Rolled \(diceType.rawValue): \(rollValue)"
        return .result(dialog: dialog)
    }
}

/// App Intent for showing the last dice roll (the same result the widget
/// displays) — there is no dedicated in-app "history" screen to navigate to,
/// so this reports the last roll directly instead of opening a URL nothing
/// ever handled. See CODE_AUDIT §5.2.
public struct ShowDiceHistoryIntent: AppIntent {
    public static let title: LocalizedStringResource = "Show Dice History"
    public static let description = IntentDescription("Show your last dice roll")

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let lastRoll = DiceConfiguration.loadFromUserDefaults().lastRoll else {
            return .result(dialog: "You haven't rolled any dice yet.")
        }
        let name = lastRoll.diceModel.name.isEmpty ? lastRoll.diceModel.dice.first?.die.text ?? "" : lastRoll.diceModel.name
        let dialog: IntentDialog = "Last roll — \(name): \(lastRoll.sum)"
        return .result(dialog: dialog)
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
