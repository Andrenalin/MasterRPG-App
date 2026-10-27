// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import Foundation
import SwiftUI

#Preview(traits: .mockData) {
    @Previewable @Environment(DiceRootModel.self) var root
    RollResultSnippetView(result: DiceResultModel(diceModel: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])))
}

public struct RollSpecificDiceIntent: AppIntent {
    public static let title: LocalizedStringResource = "Roll Specific Dice"
    public static let description = IntentDescription(
        "Rolls one of your saved dice sets and says the result. While a game runs, the roll is shared with the players.",
        categoryName: "Dice",
        searchKeywords: ["dice set", "attack", "damage", "roll"]
    )

    @Parameter(title: "Dice", requestValueDialog: .localized("Which dice do you want to roll?", bundle: .module))
    var dice: DiceEntity

    @Dependency var root: DiceRootModel

    public init() {}

    init(dice: DiceEntity) {
        self.dice = dice
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog & ShowsSnippetIntent {
        try await requireReadyDatabase()
        // `dice` can be deleted since Siri or Shortcuts cached it. See CODE_AUDIT_AppIntents §5.2.
        try requiredIntentTarget(root.itemController.itemSync(for: dice.id), parameter: $dice, prompt: .localized("Which dice do you want to roll?", bundle: .module))
        let rollResult = root.rollFromIntent(diceId: dice.id)
        return .result(
            value: rollResult.sum,
            dialog: DiceRollDialog.dialog(name: dice.name, result: rollResult),
            snippetIntent: DiceRollSnippetIntent(dice: dice)
        )
    }
}

/// The result card of a saved set with a "Roll Again" button. The system runs `perform()` again
/// after the button's intent and whenever it redraws the card, so it only reads the last result.
/// See CODE_AUDIT_AppIntents3 §8.1.
struct DiceRollSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Dice Roll Result"
    static let isDiscoverable = false

    @Parameter(title: "Dice")
    var dice: DiceEntity

    @Dependency var root: DiceRootModel

    init() {}

    init(dice: DiceEntity) {
        self.dice = dice
    }

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        .result(view: RollResultSnippetView(
            result: root.gameController.result(itemId: dice.id),
            rollAgain: RollDiceAgainIntent(dice: dice)
        ))
    }
}

/// The card's "Roll Again" button: rolls the same set as `RollSpecificDiceIntent` does.
struct RollDiceAgainIntent: AppIntent {
    static let title: LocalizedStringResource = "Roll Dice Again"
    static let isDiscoverable = false

    @Parameter(title: "Dice")
    var dice: DiceEntity

    @Dependency var root: DiceRootModel

    init() {}

    init(dice: DiceEntity) {
        self.dice = dice
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try requiredIntentTarget(root.itemController.itemSync(for: dice.id), parameter: $dice, prompt: .localized("Which dice do you want to roll?", bundle: .module))
        root.rollFromIntent(diceId: dice.id)
        return .result()
    }
}

// MARK: - Snippet View

struct RollResultSnippetView: View {
    let result: DiceResultModel
    var rollAgain: RollDiceAgainIntent?

    var body: some View {
        VStack {
            VStack {
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
                HStack {
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
                    Text(verbatim: DiceRollDialog.spokenValues(result.values))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            // One element read as "<result>, <dice>, <sum>, <values>" instead of five fragments.
            // See CODE_AUDIT_AppIntents2 §8.1.
            .accessibilityElement(children: .combine)
            .padding()

            if let rollAgain {
                Button(intent: rollAgain) {
                    Label {
                        Text("Roll Again", bundle: .module)
                    } icon: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom)
            }
        }
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
    /// Shortcuts path. At most once per dice set every few minutes: rolls come in bursts and the
    /// system ignores a source that floods it. See CODE_AUDIT_AppIntents2 §5.5.
    @MainActor
    func donateRoll(of itemId: UUID) {
        Task {
            await IntentDonations.donateThrottled(for: itemId) {
                guard let model = itemController.itemSync(for: itemId) else { return nil }
                return RollSpecificDiceIntent(dice: DiceEntity(root: self, model: model))
            }
        }
    }
}

#endif
