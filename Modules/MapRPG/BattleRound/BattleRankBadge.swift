// @copyright André Trettin

import SwiftUI

struct BattleRankBadge: View {
    let rank: Int
    let isActive: Bool

    var body: some View {
        Text(rank, format: .number)
            .font(.callout.bold().monospacedDigit())
            .foregroundStyle(isActive ? .white : .gray)
            .frame(minWidth: 28, minHeight: 28)
            .background(isActive ? Color.blue : Color.gray.opacity(0.14), in: .circle)
            .padding(.top, 8)
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
