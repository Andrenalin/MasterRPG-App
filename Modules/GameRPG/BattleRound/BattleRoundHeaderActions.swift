// @copyright André Trettin

import MapRPG
import SwiftUI

/// The turn actions in the header of the battle side panel. macOS has them in
/// the battle window's toolbar instead (`BattleRoundWindowToolbar`).
struct BattleRoundHeaderActions: View {
    let controller: BattleRoundController
    /// "End" asks first: ending discards the turn order and the rolls.
    let requestEnd: @MainActor () -> Void

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
            .battleHeaderGlassButton()

            Button(
                String(localized: "Next Round", bundle: .module),
                systemImage: "arrow.uturn.backward"
            ) {
                controller.nextRound()
            }
            .labelStyle(.iconOnly)
            .help(Text("Next Round", bundle: .module))
            .buttonStyle(.borderedProminent)

            Spacer(minLength: BattleRoundSpacing.tight)

            Button(
                String(localized: "End", bundle: .module),
                systemImage: "stop.fill",
                role: .destructive,
                action: requestEnd
            )
            .labelStyle(.iconOnly)
            .help(Text("End", bundle: .module))
            .tint(.red)
            .battleHeaderGlassButton()
        }
        .controlSize(.small)
    }
}

private extension View {
    /// Interactive glass where the header sits over the game (iOS, tvOS). On
    /// macOS a glass button inside a window's content shares the hosting view
    /// with the cards' drag, drop and menu gestures, the combination AppKit
    /// asserted on ("Unexpected equal node indexes") before it stopped
    /// delivering clicks to the window — so a plain bordered button there.
    @ViewBuilder
    func battleHeaderGlassButton() -> some View {
#if os(iOS) || os(tvOS)
        buttonStyle(.glass)
#else
        buttonStyle(.bordered)
#endif
    }
}

#Preview("Running battle actions") {
    BattleRoundHeaderActions(controller: .preview(), requestEnd: {})
        .padding()
        .environment(\.locale, Locale(identifier: "de"))
}
