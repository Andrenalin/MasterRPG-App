// @copyright André Trettin

import AppIntents
import CoreRPG
import DiceRPG
import SwiftUI
import WidgetKit

/// App Intent for rolling dice from the widget
struct RollDiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Roll Dice"
    static let description = IntentDescription("Roll a dice and show the result")
    static let isDiscoverable = false

    @Parameter(title: "Dice Type", default: .d20)
    var diceType: IntentDiceType

    init(diceType: IntentDiceType) {
        self.diceType = diceType
    }

    init() {
        self.diceType = .d20
    }

    func perform() async throws -> some IntentResult {
        await DiceIntentPerformer.roll(diceType)
        return .result()
    }
}

private enum DiceIntentPerformer {
    static func roll(_ diceType: IntentDiceType) async {
        let die = diceType.toDieModel()
        let rolledDie = die.roll(resetResults: true, rerollOptions: [])
        let result = rolledDie.result.first ?? die.die.max

        // Create dice model with the rolled die
        let diceModel = DiceSnapshot(id: UUID(), name: diceType.rawValue, dice: [rolledDie])

        // Create result model
        let rollResult = DiceResultModel(
            diceModel: diceModel,
            result: .rolled,
            values: "\(result)",
            sum: result,
            checked: false,
            timeStamp: Date()
        )

        // Same newest-wins write as the app. See CODE_AUDIT_18 §3.19.
        guard DiceConfiguration.recordLastRoll(rollResult) else { return }
        DiceWidgetReloader.reloadDiceWidgets()
    }
}

// MARK: - Dice Type for Intents

/// Simple dice type enum that conforms to AppEnum for use in intents
enum IntentDiceType: String, AppEnum {
    case d4 = "D4"
    case d6 = "D6"
    case d8 = "D8"
    case d10 = "D10"
    case d12 = "D12"
    case d20 = "D20"
    case d100 = "D100"

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Dice Type")
    }

    static var caseDisplayRepresentations: [IntentDiceType: DisplayRepresentation] {
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

    /// Convert to DieModel for actual dice rolling
    func toDieModel() -> DieModel {
        .die(sides: sides)
    }

    private var sides: Int {
        switch self {
        case .d4: 4
        case .d6: 6
        case .d8: 8
        case .d10: 10
        case .d12: 12
        case .d20: 20
        case .d100: 100
        }
    }
}
