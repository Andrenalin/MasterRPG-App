// @copyright André Trettin

import MapRPG
import SwiftUI

struct BattleRollResults: View {
    let results: [BattleRollResult]
    let tint: Color
    /// `true` lets the strip run to the end of its row instead of the fixed
    /// width used where a column has to stay narrow.
    var fillsRow = false

    /// The strip scales with the `.caption2` totals it shows instead of clipping them at
    /// accessibility text sizes. See CODE_AUDIT_18 §8.3.
    @ScaledMetric(relativeTo: .caption2) private var stripWidth: CGFloat = 76
    @ScaledMetric(relativeTo: .caption2) private var stripHeight: CGFloat = 25

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var scrollPosition = ScrollPosition(edge: .trailing)

    var body: some View {
        if !results.isEmpty {
            ScrollView(.horizontal) {
                // A plain stack: the model keeps at most
                // `BattleRoundModel.maximumRollsPerCombatant` rolls here.
                HStack(spacing: 3) {
                    ForEach(results) { result in
                        BattleRollResultBadge(result: result, tint: tint)
                    }
                }
            }
            .scrollIndicators(.hidden)
            // The newest roll is the one that matters: start at the end and
            // move there whenever a roll is added.
            .scrollPosition($scrollPosition)
            .defaultScrollAnchor(.trailing, for: .initialOffset)
            .onChange(of: results.last?.id) {
                withAnimation(accessibilityReduceMotion ? nil : .default) {
                    scrollPosition.scrollTo(edge: .trailing)
                }
            }
            .frame(
                minWidth: fillsRow ? nil : stripWidth,
                maxWidth: fillsRow ? .infinity : stripWidth,
                alignment: .leading
            )
            .frame(height: stripHeight)
            .accessibilityLabel(Text("Dice results", bundle: .module))
        }
    }
}

/// One roll total, followed by a symbol when the roll was a critical or a
/// fumble.
private struct BattleRollResultBadge: View {
    let result: BattleRollResult
    let tint: Color

    var body: some View {
        HStack(spacing: BattleRoundSpacing.extraTight) {
            Text(result.total, format: .number)
                .font(.caption2.bold().monospacedDigit())
            if let outcome = result.outcome {
                Image(systemName: outcome.systemImage)
                    .font(.caption2)
                    .foregroundStyle(outcome.color)
                    .accessibilityLabel(Text(outcome.title))
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(tint.opacity(0.18), in: .capsule)
        .help(
            result.expression.map(Text.init(verbatim:))
                ?? Text("Dice result", bundle: .module)
        )
    }
}

extension BattleRollOutcome {
    /// The same symbols the dice roll intent shows for a coup and a fumble.
    var systemImage: String {
        switch self {
        case .critical: "star.fill"
        case .fumble: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .critical: .yellow
        case .fumble: .red
        }
    }

    var title: String {
        switch self {
        case .critical: String(localized: "Critical", bundle: .module)
        case .fumble: String(localized: "Fumble", bundle: .module)
        }
    }
}

#Preview("Roll results") {
    let model = BattleRoundPreviewData.model()

    if let rolls = model.cardPresentations.first?.attacker.rolls {
        BattleRollResults(results: rolls, tint: .blue)
            .padding()
    }
}

#Preview("Critical and fumble") {
    let combatantId = UUID()

    BattleRollResults(
        results: [
            BattleRollResult(combatantId: combatantId, total: 20, outcome: .critical),
            BattleRollResult(combatantId: combatantId, total: 12),
            BattleRollResult(combatantId: combatantId, total: 1, outcome: .fumble),
            BattleRollResult(combatantId: combatantId, total: 9)
        ],
        tint: .blue,
        fillsRow: true
    )
    .frame(width: 300)
    .padding()
}

#Preview("Overflowing strip starts at the newest roll") {
    let combatantId = UUID()

    BattleRollResults(
        results: (1...12).map { BattleRollResult(combatantId: combatantId, total: $0) },
        tint: .blue
    )
    .padding()
}
