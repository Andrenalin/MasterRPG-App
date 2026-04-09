// @copyright André Trettin

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
                    quickRollButtons
                        .padding(.top, 8)
                }
            } compactLeading: {
                // Compact leading UI
                if let firstDie = context.state.lastRoll.diceModel.dice.first {
                    Image(systemName: diceSymbol(for: firstDie.die.max))
                        .font(.system(size: 14))
                        .foregroundStyle(compactResultColor(for: context.state.lastRoll))
                }
            } compactTrailing: {
                // Compact trailing UI
                Text("\(context.state.lastRoll.sum)")
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(compactResultColor(for: context.state.lastRoll))
            } minimal: {
                // Minimal UI
                if let firstDie = context.state.lastRoll.diceModel.dice.first {
                    Image(systemName: diceSymbol(for: firstDie.die.max))
                        .font(.system(size: 14))
                        .foregroundStyle(compactResultColor(for: context.state.lastRoll))
                }
            }
            .widgetURL(URL(string: "masterrpg://dice"))
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

    private func diceIconView(for result: DiceResultModel) -> some View {
        Group {
            if let firstDie = result.diceModel.dice.first {
                Image(systemName: diceSymbol(for: firstDie.die.max))
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
            }
        }
    }

    private func diceResultBadge(for result: DiceResultModel) -> some View {
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

    private var quickRollButtons: some View {
        HStack(spacing: 12) {
            ForEach([IntentDiceType.d4, .d6, .d8, .d10, .d12, .d20], id: \.self) { diceType in
                Button(intent: RollDiceIntent(diceType: diceType)) {
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

    private func resultColor(for result: DiceResultModel) -> Color {
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

    private func compactResultColor(for result: DiceResultModel) -> Color {
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
                        if let firstDie = context.state.lastRoll.diceModel.dice.first {
                            Image(systemName: diceSymbol(for: firstDie.die.max))
                                .font(.system(size: 20))
                                .foregroundStyle(.white)
                        }

                        Text("\(context.state.lastRoll.sum)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }

                Text(context.state.lastRoll.diceModel.name)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Right side - Quick roll buttons
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick Roll")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach([IntentDiceType.d20, .d12, .d10], id: \.self) { diceType in
                        Button(intent: RollDiceIntent(diceType: diceType)) {
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
