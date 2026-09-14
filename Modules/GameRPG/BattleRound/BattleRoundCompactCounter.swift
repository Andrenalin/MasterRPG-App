// @copyright André Trettin

import SwiftUI

struct BattleRoundCompactCounter: View {
    let round: Int

    var body: some View {
        Label {
            BattleRoundTitle(round: round)
                .monospacedDigit()
        } icon: {
            Image(systemName: "shield.lefthalf.filled")
        }
        .font(.headline)
        .foregroundStyle(.primary)
        .padding(.horizontal, BattleRoundSpacing.loose)
        .padding(.vertical, BattleRoundSpacing.standard)
        .background(.regularMaterial, in: .capsule)
    }
}

#Preview("Compact round counter") {
    BattleRoundCompactCounter(round: 3)
        .padding()
}
