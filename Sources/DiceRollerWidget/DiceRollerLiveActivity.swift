// @copyright André Trettin

#if os(iOS)
import ActivityKit
import AppIntents
import CoreRPG
import DiceRPG
import SwiftUI
import WidgetKit

/// Live Activity for dice rolling during active gameplay
struct DiceRollerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DiceRollerActivityAttributes.self) { context in
            // Lock Screen / Banner UI
            DiceRollerLiveActivityView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.3))
                .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    diceIconView(for: context.state.lastRoll)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    diceResultBadge(for: context.state.lastRoll)
                }

                DynamicIslandExpandedRegion(.center) {
                    Text("Roll: \(context.state.lastRoll.sum)")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    favoriteDiceButtons(context.state.favoriteDice)
                        .padding(.top, 8)
                }
            } compactLeading: {
                // Compact leading UI
                Image(systemName: diceSymbol(for: context.state.lastRoll.dice.sides))
                    .font(.system(size: 14))
                    .foregroundStyle(compactResultColor(for: context.state.lastRoll))
            } compactTrailing: {
                // Compact trailing UI
                Text("\(context.state.lastRoll.sum)")
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(compactResultColor(for: context.state.lastRoll))
            } minimal: {
                // Minimal UI
                Image(systemName: diceSymbol(for: context.state.lastRoll.dice.sides))
                    .font(.system(size: 14))
                    .foregroundStyle(compactResultColor(for: context.state.lastRoll))
            }
            .widgetURL(DiceWidgetDeepLink.diceRoot)
            .keylineTint(compactResultColor(for: context.state.lastRoll))
        }
    }
    
    // MARK: - Helper Views

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

    private func diceIconView(for result: DiceWidgetRoll) -> some View {
        Image(systemName: diceSymbol(for: result.dice.sides))
            .font(.system(size: 20))
            .foregroundStyle(.white)
    }

    private func diceResultBadge(for result: DiceWidgetRoll) -> some View {
        ZStack {
            Circle()
                .fill(resultColor(for: result))
                .frame(width: 40, height: 40)

            Text("\(result.sum)")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder private func favoriteDiceButtons(_ favorites: [DiceWidgetFavorite]) -> some View {
        if favorites.isEmpty {
            // Fall back to quick roll if no favorites
            quickRollButtons
        } else {
            // Show favorite dice (up to 6)
            HStack(spacing: 12) {
                ForEach(favorites.prefix(6)) { favorite in
                    Button(intent: RollFavoriteDiceLiveActivityIntent(diceId: favorite.id)) {
                        VStack(spacing: 2) {
                            Image(systemName: diceSymbol(for: favorite.dice.sides))
                                .font(.system(size: 14))
                            Text(favorite.name)
                                .font(.system(size: 8))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                }
            }
        }
    }
    
    private var quickRollButtons: some View {
        HStack(spacing: 12) {
            ForEach([IntentDiceType.d4, .d6, .d8, .d10, .d12, .d20], id: \.self) { diceType in
                Button(intent: RollDiceLiveActivityIntent(diceType: diceType)) {
                    VStack(spacing: 2) {
                        let sides = diceType.toDieModel().die.max
                        Image(systemName: diceSymbol(for: sides))
                            .font(.system(size: 14))
                        Text(diceType.rawValue)
                            .font(.system(size: 8))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
            }
        }
    }

    private func resultColor(for result: DiceWidgetRoll) -> Color {
        switch result.result {
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

    private func compactResultColor(for result: DiceWidgetRoll) -> Color {
        switch result.result {
        case .coup:
            return .green
        case .fumble:
            return .red
        case .rolled, .notRolled:
            return .white
        }
    }
}

// MARK: - Lock Screen View

struct DiceRollerLiveActivityView: View {
    let context: ActivityViewContext<DiceRollerActivityAttributes>

    var body: some View {
        HStack(spacing: 16) {
            // Left side - Dice result with icon
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(resultColor.opacity(0.3))
                        .frame(width: 60, height: 60)

                    VStack(spacing: 4) {
                        Image(systemName: diceSymbol(for: context.state.lastRoll.dice.sides))
                            .font(.system(size: 20))
                            .foregroundStyle(.white)

                        Text("\(context.state.lastRoll.sum)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }

                Text(context.state.lastRoll.dice.name)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Right side - Favorite or quick roll buttons
            VStack(alignment: .leading, spacing: 8) {
                let favorites = context.state.favoriteDice

                if favorites.isEmpty {
                    // Fall back to quick roll if no favorites
                    Text("Quick Roll")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach([IntentDiceType.d20, .d12, .d10], id: \.self) { diceType in
                            Button(intent: RollDiceLiveActivityIntent(diceType: diceType)) {
                                VStack(spacing: 2) {
                                    let sides = diceType.toDieModel().die.max
                                    Image(systemName: diceSymbol(for: sides))
                                        .font(.system(size: 16))
                                    Text(diceType.rawValue)
                                        .font(.system(size: 9, weight: .medium))
                                }
                                .frame(width: 44, height: 44)
                                .background(.quaternary)
                                .clipShape(.rect(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    // Show favorite dice
                    Text("Favorites")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach(favorites.prefix(3)) { favorite in
                            Button(intent: RollFavoriteDiceLiveActivityIntent(diceId: favorite.id)) {
                                VStack(spacing: 2) {
                                    Image(systemName: diceSymbol(for: favorite.dice.sides))
                                        .font(.system(size: 16))
                                    Text(favorite.name)
                                        .font(.system(size: 8, weight: .medium))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.6)
                                }
                                .frame(width: 44, height: 44)
                                .background(.quaternary)
                                .clipShape(.rect(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Spacer()

            // Game status
            VStack(alignment: .trailing, spacing: 4) {
                Text(context.attributes.gameName)
                    .font(.caption)
                    .fontWeight(.semibold)

                Text("Active")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
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
        let result = context.state.lastRoll.result
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

#endif // os(iOS)
