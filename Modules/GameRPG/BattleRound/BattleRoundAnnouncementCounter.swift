// @copyright André Trettin

import SwiftUI

struct BattleRoundAnnouncementCounter: View {
    let round: Int
    let attackerName: String?

    var body: some View {
        VStack(spacing: BattleRoundSpacing.standard) {
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
#if !os(visionOS)
        .glassEffect(in: .rect(cornerRadius: 24))
#endif
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
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
