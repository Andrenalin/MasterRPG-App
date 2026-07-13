// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import Foundation
import SwiftUI

#Preview(traits: .mockData) {
    @Previewable @Environment(DiceRootModel.self) var root
    RollResultSnippetView(result: DiceResultModel(diceModel: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])))
        .background(.black)
}

public struct RollSpecificDiceIntent: AppIntent {
    public static let title: LocalizedStringResource = "Roll Specific Dice"
    public static let description = IntentDescription("Roll a specific dice from your collection")
    
    @Parameter(title: "Dice", requestValueDialog: "Which dice do you want to roll?")
    var dice: DiceEntity
    
    @Dependency var root: DiceRootModel
    
    public init() {}
    
    init(dice: DiceEntity) {
        self.dice = dice
    }
    
    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        // Roll all dice in the dice model
        
        root.gameController.rollDice(itemId: dice.model.id, rollSynced: true)
        let rollResult = root.gameController.result(itemId: dice.model.id)
        
        // Save to configuration
        var config = DiceConfiguration.loadFromUserDefaults()
        config.lastRoll = rollResult
        config.selectedDice = rollResult.diceModel
        config.save()
        
        // Reload widgets
        DiceWidgetReloader.reloadDiceWidgets()
        
        // Start Live Activity if game is running
        await startLiveActivityIfNeeded(with: rollResult)
        
        let finalSum = rollResult.sum
        // Create result dialog based on result type
        let dialog: IntentDialog
        switch rollResult.result {
        case .coup:
            dialog = "🎉 Critical Success! Rolled \(dice.name): \(finalSum)"
        case .fumble:
            dialog = "💥 Critical Failure! Rolled \(dice.name): \(finalSum)"
        case .rolled:
            dialog = "🎲 Rolled \(dice.name): \(finalSum)"
        case .notRolled:
            dialog = "Rolled \(dice.name): \(finalSum)"
        }
        
        return .result(
            dialog: dialog,
            view: RollResultSnippetView(result: rollResult)
        )
    }
    
    private func formatValues(results: [Int], sumUp: Bool, modifier: Double) -> String {
        if sumUp {
            let sum = results.reduce(0, +)
            if modifier != 0 {
                let modifierString = modifier > 0 ? "+\(Int(modifier))" : "\(Int(modifier))"
                return results.map { String($0) }.joined(separator: ", ") + " \(modifierString) = \(Int(Double(sum) + modifier))"
            } else {
                return results.map { String($0) }.joined(separator: ", ") + " = \(sum)"
            }
        } else {
            if let first = results.first {
                if modifier != 0 {
                    let modifierString = modifier > 0 ? "+\(Int(modifier))" : "\(Int(modifier))"
                    return "\(first) \(modifierString) = \(Int(Double(first) + modifier))"
                } else {
                    return String(first)
                }
            }
            return ""
        }
    }
    
    private func startLiveActivityIfNeeded(with result: DiceResultModel) async {
        // Check if a game is currently running
        let defaults = UserDefaults(suiteName: UserDefaults.appGroupString)
        let isGameActive = defaults?.bool(forKey: UserDefaults.DiceKeys.isGameActive) ?? false
        
        if isGameActive {
            // Start or update Live Activity
            await DiceRollerLiveActivityManager.shared.startOrUpdate(with: result)
        }
    }
}

// MARK: - Snippet View

struct RollResultSnippetView: View {
    let result: DiceResultModel
    
    var body: some View {
        VStack(spacing: 12) {
            // Result type indicator
            HStack {
                resultIcon
                Text(result.result.localizedTitle)
                    .font(.headline)
            }
            
            // Dice name
            Text(result.diceModel.name)
                .font(.title2)
                .bold()
            
            // Result
            HStack(spacing: 4) {
                Image(systemName: "dice.fill")
                    .foregroundStyle(.secondary)
                Text("\(result.sum)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
            }
            
            // Values breakdown
            if !result.values.isEmpty {
                Text(result.values)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.white)
        .padding()
    }
    
    @ViewBuilder
    private var resultIcon: some View {
        switch result.result {
        case .coup:
            Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
        case .fumble:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .rolled:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .notRolled:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        }
    }
}

#if os(iOS)
extension RollSpecificDiceIntent: TargetContentProvidingIntent {}
#endif

#endif
