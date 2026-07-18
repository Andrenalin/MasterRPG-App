// @copyright André Trettin

import SwiftUI

public enum BattleRoundCounterStyle: Sendable {
    case compact
    case announcement
}

/// A presentation-only round label shared by the game chrome and the battle
/// window. It deliberately has no hit target so the containing chrome decides
/// whether the label opens the battle window or remains passive.
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
                BattleRoundCompactCounter(model: model)
            case .announcement:
                BattleRoundAnnouncementCounter(model: model)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct BattleRoundCompactCounter: View {
    let model: BattleRoundModel

    var body: some View {
        Label {
            BattleRoundTitle(round: model.roundCounter)
                .monospacedDigit()
        } icon: {
            Image(systemName: "shield.lefthalf.filled")
        }
        .font(.headline)
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: .capsule)
    }
}

private struct BattleRoundAnnouncementCounter: View {
    let model: BattleRoundModel

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)

            BattleRoundTitle(round: model.roundCounter)
                .font(.largeTitle.bold())
                .monospacedDigit()

            if let attacker = model.activeEntry.flatMap({ model.attacker(for: $0) }) {
                Text(attacker.name)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(24)
        .frame(minWidth: 220)
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
        .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct BattleRoundTitle: View {
    let round: Int

    var body: some View {
        if round == 0 {
            Text("Surprise", bundle: .module)
        } else {
            Text("Round \(round)", bundle: .module)
        }
    }
}

