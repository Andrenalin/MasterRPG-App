// @copyright André Trettin

import AppIntents
import CoreRPG
import DiceRPG
import SwiftUI
import WidgetKit

/// App Intent for rolling dice from the widget
struct RollDiceIntent: AppIntent, WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Roll Dice"
    static let description = IntentDescription("Roll a dice and show the result")

    @Parameter(title: "Dice Type", default: .d20)
    var diceType: IntentDiceType

    init(diceType: IntentDiceType) {
        self.diceType = diceType
    }

    init() {
        self.diceType = .d20
    }

    func perform() async throws -> some IntentResult {
        // Convert to DieModel and roll
        let die = diceType.toDieModel()
        let rolledDie = die.role(resetResults: true, reroleOptions: [])
        let result = rolledDie.result.first ?? die.die.max

        // Create dice model with the rolled die
        let diceModel = DiceModel(id: UUID(), name: diceType.rawValue, dice: [rolledDie])

        // Create result model
        let rollResult = DiceResultModel(
            diceModel: diceModel,
            result: .rolled,
            values: "\(result)",
            sum: result,
            checked: false,
            timeStamp: Date()
        )

        // Save to configuration
        var config = DiceConfiguration.loadFromUserDefaults()
        config.lastRoll = rollResult
        config.selectedDice = diceModel
        config.save()

        // Reload widgets
        WidgetCenter.shared.reloadAllTimelines()

        // Start Live Activity if game is running
        await startLiveActivityIfNeeded(with: rollResult)

        return .result()
    }

    private func startLiveActivityIfNeeded(with result: DiceResultModel) async {
        // Check if a game is currently running
        let defaults = UserDefaults(suiteName: "group.de.andretrettin.MasterRPG")
        let isGameActive = defaults?.bool(forKey: "isGameActive") ?? false

        if isGameActive {
            // Start or update Live Activity
            await DiceRollerLiveActivityManager.shared.startOrUpdate(with: result)
        }
    }
}

/// App Intent for clearing dice history
struct ClearDiceHistoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Clear History"
    static let description = IntentDescription("Clear dice roll history")
    
    func perform() async throws -> some IntentResult {
        var config = DiceConfiguration.loadFromUserDefaults()
        config.lastRoll = nil
        config.save()
        
        WidgetCenter.shared.reloadAllTimelines()
        
        return .result()
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
        switch self {
        case .d4: return .die4(color: .G)
        case .d6: return .die6(color: .G)
        case .d8: return .die8(color: .G)
        case .d10: return .die10(color: .G)
        case .d12: return .die12(color: .G)
        case .d20: return .die20(color: .G)
        case .d100: return DieModel(id: UUID(), die: RawDie(.number(100)), color: "G")
        }
    }
}
