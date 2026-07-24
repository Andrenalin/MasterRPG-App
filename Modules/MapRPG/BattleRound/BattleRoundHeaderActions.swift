// @copyright André Trettin

import SwiftUI

struct BattleRoundHeaderActions: View {
    let isRunning: Bool
    let actions: BattleRoundActions

    var body: some View {
        HStack(spacing: 8) {
            if isRunning {
                Button(
                    "Next Turn",
                    systemImage: "person.line.dotted.person.fill",
                    action: actions.nextAttacker
                )
                .buttonStyle(.bordered)

                Button(
                    "Next Round",
                    systemImage: "chevron.right.2",
                    action: actions.nextRound
                )
                .buttonStyle(.borderedProminent)

                Menu {
                    Button(
                        "End Battle",
                        systemImage: "stop.fill",
                        role: .destructive,
                        action: actions.end
                    )
                } label: {
                    Label("More Battle Actions", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
            } else {
                Button(
                    "Start Battle",
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
}

#Preview("Start battle action") {
    let model = BattleRoundModel()

    BattleRoundHeaderActions(
        isRunning: false,
        actions: .preview(model: model)
    )
    .padding()
}
