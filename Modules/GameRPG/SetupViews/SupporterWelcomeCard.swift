// @copyright André Trettin

import CoreRPG
import SwiftUI

struct SupporterWelcomeCard: View {
    let openSupporter: @MainActor () -> Void

    @Environment(\.supporterTier) private var supporterTier
    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: openSupporter) {
            HStack {
                SupporterCrownView(tier: supporterTier)
                    .font(.title)

                VStack(alignment: .leading) {
                    if supporterTier == .none {
                        Text("Every adventurer is welcome", bundle: .module)
                            .font(.headline)
                        Text(
                            "Every MasterRPG feature is available to everyone. If the app supports your adventures, you can support its development and receive a crown beside your game name.",
                            bundle: .module
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Welcome back, \(Text(supporterTier.localizedName)).", bundle: .module)
                            .font(.headline)
                        Text(
                            "Thank you for helping keep the adventure going.",
                            bundle: .module
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .multilineTextAlignment(.leading)
            .padding()
            .background(
                theme.panelColor.opacity(0.88),
                in: .rect(cornerRadius: 20)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Opens supporter options.", bundle: .module))
    }
}

#Preview("Shared · Supporter welcome Gold") {
    SupporterWelcomeCard(openSupporter: {})
        .padding()
        .environment(\.supporterTier, .gold)
}

#Preview("Shared · Supporter welcome") {
    SupporterWelcomeCard(openSupporter: {})
        .padding()
        .environment(\.supporterTier, .none)
}
