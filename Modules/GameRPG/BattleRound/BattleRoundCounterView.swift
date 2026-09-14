// @copyright André Trettin

import MapRPG
import SwiftUI

/// A presentation-only round label shared by the game chrome and the battle
/// window. The containing chrome decides whether it is interactive.
struct BattleRoundCounterView: View {
    let model: BattleRoundModel
    let style: BattleRoundCounterStyle

    var body: some View {
        Group {
            switch style {
            case .compact:
                BattleRoundCompactCounter(
                    round: model.roundCounter
                )
            case .announcement:
                BattleRoundAnnouncementCounter(
                    round: model.roundCounter,
                    attackerName: activeAttackerName
                )
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var activeAttackerName: String? {
        guard let entry = model.activeEntry else { return nil }
        return model.attacker(for: entry)?.name
    }
}

#Preview("Compact Counter") {
    let model = BattleRoundPreviewData.model()
    BattleRoundCounterView(model: model, style: .compact)
        .padding()
}

#Preview("Round Announcement") {
    let model = BattleRoundPreviewData.model()
    BattleRoundCounterView(model: model, style: .announcement)
        .padding()
}
