// @copyright André Trettin

import SwiftUI

/// `Equatable` so `.equatable()` at its call sites can skip re-diffing this
/// leaf when an unrelated part of the same card changes. See CODE_AUDIT §7.2.
struct BattleRankBadge: View, Equatable {
    let rank: Int
    let isActive: Bool

    var body: some View {
        Text(rank, format: .number)
            .font(.callout.bold().monospacedDigit())
            .foregroundStyle(isActive ? .white : .gray)
            .frame(minWidth: 28, minHeight: 28)
            .background(isActive ? Color.blue : Color.gray.opacity(0.14), in: .circle)
            .padding(.top, BattleRoundSpacing.standard)
            .accessibilityLabel(Text("Initiative position \(rank)", bundle: .module))
    }
}

#Preview("Battle rank") {
    HStack {
        BattleRankBadge(rank: 1, isActive: true)
        BattleRankBadge(rank: 2, isActive: false)
    }
    .padding()
}
