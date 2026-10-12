// @copyright André Trettin

import SwiftUI

/// `Equatable` so `.equatable()` at its call sites can skip re-diffing this
/// leaf when an unrelated part of the same card changes.
struct BattleRankBadge: View, Equatable {
    let rank: Int
    let isActive: Bool

    @ScaledMetric(relativeTo: .callout) private var side: CGFloat = 28

    var body: some View {
        Text(rank, format: .number)
            .font(.callout.bold().monospacedDigit())
            .foregroundStyle(isActive ? .white : BattleRoundPalette.inactive)
            .frame(minWidth: side, minHeight: side)
            .background(
                isActive ? BattleRoundPalette.attacker : BattleRoundPalette.inactive.opacity(0.14),
                in: .circle
            )
            .padding(.top, BattleRoundSpacing.standard)
            .accessibilityLabel(Text("Initiative position \(rank)", bundle: .module))
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.rank == rhs.rank && lhs.isActive == rhs.isActive
    }
}

#Preview("Battle rank") {
    HStack {
        BattleRankBadge(rank: 1, isActive: true)
        BattleRankBadge(rank: 2, isActive: false)
    }
    .padding()
}
