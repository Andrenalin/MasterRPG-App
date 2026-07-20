// @copyright André Trettin

import SwiftUI

struct BattleRoundHeading: View {
    let isRunning: Bool
    let round: Int
    let activeAttackerName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if isRunning {
                BattleRoundTitle(round: round)
                    .font(.title2.bold())
                    .monospacedDigit()

                if let activeAttackerName {
                    Text(activeAttackerName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("Initiative", bundle: .module)
                    .font(.title2.bold())
            }
        }
    }
}
