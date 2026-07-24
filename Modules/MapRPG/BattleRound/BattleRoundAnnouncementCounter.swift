// @copyright André Trettin

import SwiftUI

struct BattleRoundAnnouncementCounter: View {
    let round: Int
    let attackerName: String?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)

            BattleRoundTitle(round: round)
                .font(.largeTitle.bold())
                .monospacedDigit()

            if let attackerName {
                Text(attackerName)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(24)
        .frame(minWidth: 220)
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
        .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview("Round announcement") {
    BattleRoundAnnouncementCounter(
        round: 3,
        attackerName: "Aria Swiftwind"
    )
    .padding()
}
