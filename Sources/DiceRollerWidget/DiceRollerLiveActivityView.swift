// @copyright André Trettin

#if os(iOS)
import ActivityKit
import AppIntents
import CoreRPG
import DiceRPG
import SwiftUI

struct DiceRollerLiveActivityView: View {
    let attributes: DiceRollerActivityAttributes
    let state: DiceRollerActivityAttributes.ContentState

    init(
        attributes: DiceRollerActivityAttributes,
        state: DiceRollerActivityAttributes.ContentState
    ) {
        self.attributes = attributes
        self.state = state
    }

    var body: some View {
        HStack(spacing: 16) {
            // Left side - Dice result with icon
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(resultColor.opacity(0.3))
                        .frame(width: 60, height: 60)

                    VStack(spacing: 4) {
                        Image(systemName: diceSymbol(for: state.lastRoll.dice.sides))
                            .font(.title3)
                            .foregroundStyle(.white)
                            .accessibilityHidden(true)

                        Text(verbatim: "\(state.lastRoll.sum)")
                            .font(.title3)
                            .bold()
                            .foregroundStyle(.white)
                    }
                }

                Text(verbatim: state.lastRoll.dice.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: state.lastRoll.dice.name))
            .accessibilityValue(Text(verbatim: "\(state.lastRoll.sum)"))

            Divider()

            // Right side - Favorite or quick roll buttons
            VStack(alignment: .leading, spacing: 8) {
                let favorites = state.favoriteDice

                if favorites.isEmpty {
                    // Fall back to quick roll if no favorites
                    Text("Quick Roll", bundle: .main)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach([IntentDiceType.d20, .d12, .d10], id: \.self) { diceType in
                            Button(intent: RollDiceLiveActivityIntent(diceType: diceType)) {
                                VStack(spacing: 2) {
                                    let sides = diceType.toDieModel().die.max
                                    Image(systemName: diceSymbol(for: sides))
                                        .font(.body)
                                    Text(verbatim: diceType.rawValue)
                                        .font(.caption2)
                                }
                                .frame(width: 44, height: 44)
                                .background(.quaternary)
                                .clipShape(.rect(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Roll \(diceType.rawValue)", bundle: .main))
                        }
                    }
                } else {
                    // Show favorite dice
                    Text("Favorites", bundle: .main)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach(favorites.prefix(3)) { favorite in
                            Button(intent: RollFavoriteDiceLiveActivityIntent(diceId: favorite.id)) {
                                VStack(spacing: 2) {
                                    Image(systemName: diceSymbol(for: favorite.dice.sides))
                                        .font(.body)
                                    Text(verbatim: favorite.name)
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.6)
                                }
                                .frame(width: 44, height: 44)
                                .background(.quaternary)
                                .clipShape(.rect(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Roll \(favorite.name)", bundle: .main))
                        }
                    }
                }
            }

            Spacer()

            // Game status
            VStack(alignment: .trailing, spacing: 4) {
                Text(verbatim: attributes.gameName)
                    .font(.caption)
                    .bold()

                Text("Active", bundle: .main)
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
            .accessibilityElement(children: .combine)
        }
        .padding()
    }
    
    /// SF Symbol representation for dice (Live Activities can't reliably load asset images)
    private func diceSymbol(for sides: Int) -> String {
        switch sides {
        case 4: return "triangle.fill"
        case 6: return "square.fill"
        case 8: return "diamond.fill"
        case 10: return "pentagon.fill"
        case 12: return "hexagon.fill"
        case 20: return "circle.hexagonpath.fill"
        default: return "die.face.\(min(sides, 6)).fill"
        }
    }

    private var resultColor: Color {
        let result = state.lastRoll.result
        switch result {
        case .coup:
            return .green
        case .fumble:
            return .red
        case .rolled:
            return .blue
        case .notRolled:
            return .gray
        }
    }
}

#Preview("Live activity lock screen") {
    let d20 = DiceWidgetDice(
        id: UUID(uuid: (0xD3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)),
        name: "Arcane Check",
        sides: 20,
        face: 20
    )
    let d8 = DiceWidgetDice(
        id: UUID(uuid: (0xD3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2)),
        name: "Longsword",
        sides: 8,
        face: 8
    )
    let roll = DiceWidgetRoll(
        id: UUID(uuid: (0xD3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3)),
        dice: d20,
        result: .coup,
        values: "20",
        sum: 20,
        checked: false,
        timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000)
    )
    let attributes = DiceRollerActivityAttributes(
        gameName: "The Verdant Vault",
        startTime: Date(timeIntervalSinceReferenceDate: 799_996_400)
    )
    let state = DiceRollerActivityAttributes.ContentState(
        lastRoll: roll,
        rollCount: 7,
        favoriteDice: [
            DiceWidgetFavorite(
                id: d8.id,
                name: "Damage",
                dice: d8
            )
        ]
    )

    DiceRollerLiveActivityView(attributes: attributes, state: state)
        .background(.black.opacity(0.8))
}

#endif // os(iOS)
