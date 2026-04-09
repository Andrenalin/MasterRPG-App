// @copyright André Trettin

import AppIntents
import SwiftUI
import WidgetKit

/// App Intent for rolling dice from the widget
struct RollDiceIntent: AppIntent, WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Roll Dice"
    static let description = IntentDescription("Roll a dice and show the result")
    
    @Parameter(title: "Dice Type")
    var diceType: DiceType?
    
    init(diceType: DiceType) {
        self.diceType = diceType
    }
    
    init() {
        self.diceType = .d20
    }
    
    func perform() async throws -> some IntentResult {
        guard let diceType else { return .result() }
        // Roll the dice
        let result = diceType.roll()
        
        // Create result
        let rollResult = DiceRollResult(
            value: result,
            diceType: diceType,
            timestamp: Date()
        )
        
        // Save to configuration
        var config = DiceConfiguration.loadFromUserDefaults()
        config.lastRoll = rollResult
        config.selectedDice = diceType
        config.save()
        
        // Reload widgets
        WidgetCenter.shared.reloadAllTimelines()
        
        // Start Live Activity if game is running
        await startLiveActivityIfNeeded(with: rollResult)
        
        return .result()
    }
    
    private func startLiveActivityIfNeeded(with result: DiceRollResult) async {
        // Check if a game is currently running
        let defaults = UserDefaults(suiteName: "group.de.andretrettin.MasterRPG")
        let isGameActive = defaults?.bool(forKey: "isGameActive") ?? false
        
        if isGameActive {
            // Start or update Live Activity
            await DiceRollerLiveActivityManager.shared.startOrUpdate(with: result)
        }
    }
}

/// App Intent for selecting a dice type
struct SelectDiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Select Dice"
    static let description = IntentDescription("Select which dice to use")
    
    @Parameter(title: "Dice Type")
    var diceType: DiceType
    
    func perform() async throws -> some IntentResult {
        // Update configuration
        var config = DiceConfiguration.loadFromUserDefaults()
        config.selectedDice = diceType
        config.save()
        
        // Reload widgets
        WidgetCenter.shared.reloadAllTimelines()
        
        return .result()
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

// MARK: - App Intent Extensions

extension DiceType: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Dice Type")
    }
    
    static var caseDisplayRepresentations: [DiceType: DisplayRepresentation] {
        [
            .d4: DisplayRepresentation(title: "D4", subtitle: "4-sided die", image: .init(systemName: "triangle.fill")),
            .d6: DisplayRepresentation(title: "D6", subtitle: "6-sided die", image: .init(systemName: "square.fill")),
            .d8: DisplayRepresentation(title: "D8", subtitle: "8-sided die", image: .init(systemName: "diamond.fill")),
            .d10: DisplayRepresentation(title: "D10", subtitle: "10-sided die", image: .init(systemName: "pentagon.fill")),
            .d12: DisplayRepresentation(title: "D12", subtitle: "12-sided die", image: .init(systemName: "hexagon.fill")),
            .d20: DisplayRepresentation(title: "D20", subtitle: "20-sided die", image: .init(systemName: "circle.hexagonpath.fill")),
            .d100: DisplayRepresentation(title: "D100", subtitle: "100-sided die", image: .init(systemName: "circles.hexagongrid.fill"))
        ]
    }
}
