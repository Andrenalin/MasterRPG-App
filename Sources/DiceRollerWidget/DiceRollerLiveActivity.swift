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
            DiceRollerLiveActivityView(
                attributes: context.attributes,
                state: context.state
            )
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
                    Text("Roll: \(context.state.lastRoll.sum)", bundle: .main)
                        .font(.title2)
                        .bold()
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    favoriteDiceButtons(context.state.favoriteDice)
                        .padding(.top, 8)
                }
            } compactLeading: {
                // Compact leading UI
                Image(systemName: diceSymbol(for: context.state.lastRoll.dice.sides))
                    .font(.body)
                    .foregroundStyle(compactResultColor(for: context.state.lastRoll))
                    .accessibilityLabel(Text(verbatim: "D\(context.state.lastRoll.dice.sides)"))
            } compactTrailing: {
                // Compact trailing UI
                Text(verbatim: "\(context.state.lastRoll.sum)")
                    .font(.system(.title3, design: .rounded))
                    .bold()
                    .foregroundStyle(compactResultColor(for: context.state.lastRoll))
            } minimal: {
                // Minimal UI
                Image(systemName: diceSymbol(for: context.state.lastRoll.dice.sides))
                    .font(.body)
                    .foregroundStyle(compactResultColor(for: context.state.lastRoll))
                    .accessibilityLabel(Text(verbatim: "D\(context.state.lastRoll.dice.sides)"))
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
            .font(.title3)
            .foregroundStyle(.white)
            .accessibilityLabel(Text(verbatim: result.dice.name))
    }

    private func diceResultBadge(for result: DiceWidgetRoll) -> some View {
        ZStack {
            Circle()
                .fill(resultColor(for: result))
                .frame(width: 40, height: 40)

            Text(verbatim: "\(result.sum)")
                .font(.title3)
                .bold()
                .foregroundStyle(.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: result.dice.name))
        .accessibilityValue(Text(verbatim: "\(result.sum)"))
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
                                .font(.body)
                            Text(verbatim: favorite.name)
                                .font(.caption2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .accessibilityLabel(Text("Roll \(favorite.name)", bundle: .main))
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
                            .font(.body)
                        Text(verbatim: diceType.rawValue)
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .accessibilityLabel(Text("Roll \(diceType.rawValue)", bundle: .main))
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

#endif // os(iOS)
