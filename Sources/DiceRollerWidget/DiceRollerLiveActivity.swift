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
                    firstDie.diceImage(for: context.state.lastRoll.sum)
                        .resizable()
                        .frame(width: 16, height: 16)
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
                    firstDie.diceImage(for: context.state.lastRoll.sum)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(compactResultColor(for: context.state.lastRoll))
                }
            }
            .widgetURL(URL(string: "masterrpg://dice"))
            .keylineTint(compactResultColor(for: context.state.lastRoll))
        }
    }
    
    // MARK: - Helper Views

    private func diceIconView(for result: DiceResultModel) -> some View {
        Group {
            if let firstDie = result.diceModel.dice.first {
                firstDie.diceImage(for: result.sum)
                    .resizable()
                    .frame(width: 24, height: 24)
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
                        let die = diceType.toDieModel()
                        die.diceImage(for: die.die.max)
                            .resizable()
                            .frame(width: 16, height: 16)
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
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: 16) {
                // Left side - Dice result with Liquid Glass
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(resultColor.opacity(0.3))
                            .frame(width: 60, height: 60)

                        Text("\(context.state.lastRoll.sum)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .glassEffect(.regular.tint(resultColor).interactive())

                    Text(context.state.lastRoll.diceModel.name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white.opacity(0.8))
                }
                
                Divider()
                    .background(.white.opacity(0.3))
                
                // Right side - Quick roll buttons with Liquid Glass
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick Roll")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                    
                    HStack(spacing: 8) {
                        ForEach([IntentDiceType.d20, .d12, .d10], id: \.self) { diceType in
                            Button(intent: RollDiceIntent(diceType: diceType)) {
                                VStack(spacing: 2) {
                                    let die = diceType.toDieModel()
                                    die.diceImage(for: die.die.max)
                                        .resizable()
                                        .frame(width: 24, height: 24)
                                    Text(diceType.rawValue)
                                        .font(.system(size: 8))
                                }
                                .frame(width: 40, height: 40)
                            }
                            .buttonStyle(.glass)
                        }
                    }
                }
                
                Spacer()
                
                // Game status
                VStack(alignment: .trailing, spacing: 4) {
                    Text(context.attributes.gameName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                    
                    Text("Active")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
            .padding()
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
