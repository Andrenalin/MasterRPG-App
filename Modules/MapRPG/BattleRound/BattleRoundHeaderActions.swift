// @copyright André Trettin

import SwiftUI

struct BattleRoundHeaderActions: View {
    let isRunning: Bool
    let actions: BattleRoundActions

    var body: some View {
        HStack(spacing: 8) {
            if isRunning {
                Button(
                    String(localized: "Next Turn", bundle: .module),
                    systemImage: "forward.fill",
                    action: actions.nextAttacker
                )
                .buttonStyle(.glass)

                Button(
                    String(localized: "Next Round", bundle: .module),
                    systemImage: "arrow.uturn.backward",
                    action: actions.nextRound
                )
                .buttonStyle(.borderedProminent)

                Spacer(minLength: 4)

                Button(
                    String(localized: "End", bundle: .module),
                    systemImage: "stop.fill",
                    role: .destructive,
                    action: actions.end
                )
                .buttonStyle(.glass)
            } else {
                Button(
                    String(localized: "Start Battle", bundle: .module),
                    systemImage: "play.fill",
                    action: actions.start
                )
                .buttonStyle(.borderedProminent)
            }
        }
        .controlSize(.small)
    }
}

#Preview("Running battle actions") {
    let model = BattleRoundPreviewData.model()

    BattleRoundHeaderActions(
        isRunning: true,
        actions: .preview(model: model)
    )
    .padding()
    .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Start battle action") {
    let model = BattleRoundModel()

    BattleRoundHeaderActions(
        isRunning: false,
        actions: .preview(model: model)
    )
    .padding()
    .environment(\.locale, Locale(identifier: "de"))
}
