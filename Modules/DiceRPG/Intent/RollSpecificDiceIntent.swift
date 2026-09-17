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

        // Off-main for the same reason as GameController.diceUpdateWidget:
        // this JSON-encode + UserDefaults write shouldn't block the main
        // actor. See CODE_AUDIT §3.3.
        Task.detached(priority: .utility) {
            var config = DiceConfiguration.loadFromUserDefaults()
            config.lastRoll = rollResult
            config.selectedDice = rollResult.diceModel
            config.save()
            DiceWidgetReloader.reloadDiceWidgets()
        }

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
    
}

// MARK: - Snippet View

struct RollResultSnippetView: View {
    let result: DiceResultModel
    
    var body: some View {
        VStack(spacing: 12) {
            // Result type indicator
            HStack {
                RollResultSnippetResultIconView(result: result.result)
                Text(result.result.localizedTitle)
                    .font(.headline)
            }
            
            // Dice name
            Text(verbatim: result.diceModel.name)
                .font(.title2)
                .bold()
            
            // Result
            HStack(spacing: 4) {
                Image(systemName: "dice.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(result.sum, format: .number)
                    .font(.largeTitle)
                    .bold()
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            
            // Values breakdown
            if !result.values.isEmpty {
                Text(verbatim: result.values)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.white)
        .padding()
    }
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)

private struct RollResultSnippetResultIconView: View {
    let result: DiceResultModel.DiceResult

    @ViewBuilder
    var body: some View {
        switch result {
        case .coup:
            Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
        case .fumble:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
        case .rolled:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
        case .notRolled:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

#if os(iOS)
extension RollSpecificDiceIntent: TargetContentProvidingIntent {}
#endif

#endif
