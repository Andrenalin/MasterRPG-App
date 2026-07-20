// @copyright André Trettin

import SwiftUI

struct BattleRollResults: View {
    let results: [BattleRollResult]
    let tint: Color

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
            .frame(width: 76)
            .accessibilityLabel(Text("Dice results", bundle: .module))
        }
    }
}
