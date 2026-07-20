// @copyright André Trettin

import SwiftUI

/// A presentation-only round label shared by the game chrome and the battle
/// window. The containing chrome decides whether it is interactive.
public struct BattleRoundCounterView: View {
    public init(model: BattleRoundModel, style: BattleRoundCounterStyle) {
        self.model = model
        self.style = style
    }

    let model: BattleRoundModel
    let style: BattleRoundCounterStyle

    public var body: some View {
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
