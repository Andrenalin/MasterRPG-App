// @copyright André Trettin

import MapRPG
import SwiftUI

struct BattleRollResults: View {
    let results: [BattleRollResult]
    let tint: Color

    /// The strip scales with the `.caption2` totals it shows instead of clipping them at
    /// accessibility text sizes. See CODE_AUDIT_18 §8.3.
    @ScaledMetric(relativeTo: .caption2) private var stripWidth: CGFloat = 76
    @ScaledMetric(relativeTo: .caption2) private var stripHeight: CGFloat = 25

    var body: some View {
        if !results.isEmpty {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 3) {
                    ForEach(results) { result in
                        Text(result.total, format: .number)
                            .font(.caption2.bold().monospacedDigit())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(tint.opacity(0.18), in: .capsule)
                            .help(
                                result.expression.map(Text.init(verbatim:))
                                    ?? Text("Dice result", bundle: .module)
                            )
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(width: stripWidth, height: stripHeight)
            .accessibilityLabel(Text("Dice results", bundle: .module))
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
