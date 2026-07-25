// @copyright André Trettin

import CoreRPG
import SwiftUI

struct GameSetupStatisticsCard: View {
    let sessionCount: Int
    let openStatistics: @MainActor () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: openStatistics) {
            GameStatisticsEntryLabel(sessionCount: sessionCount)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(
                    theme.panelColor.opacity(0.82),
                    in: .rect(cornerRadius: 20)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview("Shared · Statistics") {
    GameSetupStatisticsCard(
        sessionCount: 42,
        openStatistics: {}
    )
    .padding()
}
