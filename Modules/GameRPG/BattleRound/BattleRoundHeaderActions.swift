// @copyright André Trettin

import MapRPG
import SwiftUI

struct BattleRoundHeaderActions: View {
    let controller: BattleRoundController

    var body: some View {
        HStack(spacing: BattleRoundSpacing.standard) {
            Button(
                String(localized: "Next Turn", bundle: .module),
                systemImage: "forward.fill"
            ) {
                controller.nextAttacker()
            }
            .labelStyle(.iconOnly)
            .help(Text("Next Turn", bundle: .module))
#if !os(visionOS)
            .buttonStyle(.glass)
#endif

            Button(
                String(localized: "Next Round", bundle: .module),
                systemImage: "arrow.uturn.backward"
            ) {
                controller.nextRound()
            }
            .labelStyle(.iconOnly)
            .help(Text("Next Round", bundle: .module))
            .buttonStyle(.borderedProminent)

            Spacer(minLength: 4)

            Button(
                String(localized: "End", bundle: .module),
                systemImage: "stop.fill",
                role: .destructive
            ) {
                controller.end()
            }
            .labelStyle(.iconOnly)
            .help(Text("End", bundle: .module))
            .tint(.red)
#if !os(visionOS)
            .buttonStyle(.glass)
#endif
        }
        .controlSize(.small)
    }
}

#Preview("Running battle actions") {
    BattleRoundHeaderActions(controller: .preview())
        .padding()
        .environment(\.locale, Locale(identifier: "de"))
}
