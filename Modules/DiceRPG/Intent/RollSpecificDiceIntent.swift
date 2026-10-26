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
        
        // `rollDice(rollSynced: true)` runs synchronously and internally schedules the
        // widget's UserDefaults write via `GameController.roll(die:for:)`'s tracked,
        // cancellable `diceGameModel.diceUpdateWidgetTask` — the exact same fields this
        // Intent used to write again itself via an untracked `Task.detached`. That second,
        // uncoordinated write could race the tracked one and leave the widget showing
        // whichever roll's write happened to finish last. See CODE_AUDIT.md §3.5.
        root.gameController.rollDice(itemId: dice.id, rollSynced: true)
        let rollResult = root.gameController.result(itemId: dice.id)

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

extension DiceRootModel {
    /// Donates a roll the user made from the UI, so Siri learns it next to the voice and
    /// Shortcuts path. See CODE_AUDIT_AppIntents §4.4.
    @MainActor
    func donateRoll(of itemId: UUID) {
        guard let model = itemController.itemSync(for: itemId) else { return }
        let intent = RollSpecificDiceIntent(dice: DiceEntity(root: self, model: model))
        Task { await IntentDonations.donate(intent) }
    }
}

#endif
