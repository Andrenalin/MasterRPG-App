// @copyright André Trettin

import MapRPG
import SwiftUI

struct BattleRoundHeaderActions: View {
    let isRunning: Bool
    let controller: BattleRoundController

    var body: some View {
        HStack(spacing: BattleRoundSpacing.standard) {
            if isRunning {
                Button(
                    String(localized: "Next Turn", bundle: .module),
                    systemImage: "forward.fill"
                ) {
                    controller.nextAttacker()
                }
#if !os(visionOS)
                .buttonStyle(.glass)
#endif

                Button(
                    String(localized: "Next Round", bundle: .module),
                    systemImage: "arrow.uturn.backward"
                ) {
                    controller.nextRound()
                }
                .buttonStyle(.borderedProminent)

                Spacer(minLength: 4)

                Button(
                    String(localized: "End", bundle: .module),
                    systemImage: "stop.fill",
                    role: .destructive
                ) {
                    controller.end()
                }
#if !os(visionOS)
                .buttonStyle(.glass)
#endif
            } else {
                Button(
                    String(localized: "Start Battle", bundle: .module),
                    systemImage: "play.fill"
                ) {
                    controller.start()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .controlSize(.small)
    }
}

#Preview("Running battle actions") {
    BattleRoundHeaderActions(
        isRunning: true,
        controller: .preview()
    )
    .padding()
    .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Start battle action") {
    // The preview fixture always installs a running battle; `isRunning` is
    // passed explicitly here to render the "not started" branch regardless.
    BattleRoundHeaderActions(
        isRunning: false,
        controller: .preview()
    )
    .padding()
    .environment(\.locale, Locale(identifier: "de"))
}
