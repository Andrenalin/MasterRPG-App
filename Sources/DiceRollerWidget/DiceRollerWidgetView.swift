// @copyright André Trettin

import AppIntents
import CoreRPG
import DiceRPG
import SwiftUI
import WidgetKit

/// Main view for the dice roller widget with Liquid Glass design
struct DiceRollerWidgetView: View {
    @Environment(\.widgetFamily) var family
    @Environment(\.widgetRenderingMode) var renderingMode
    
    let entry: DiceRollerEntry
    
    var body: some View {
        switch family {
        case .systemSmall:
            smallWidgetView
        case .systemMedium:
            mediumWidgetView
        case .systemLarge:
            largeWidgetView
        default:
            smallWidgetView
        }
    }
    
    // MARK: - Small Widget
    
    private var smallWidgetView: some View {
        VStack(spacing: 8) {
            // Dice icon with result
            ZStack {
                if let lastRoll = entry.configuration.lastRoll {
                    // Show last roll result
                    diceResultView(lastRoll)
                        .widgetAccentable() // Primary content in accented mode
                } else {
                    // Show dice type icon
                    if let firstDie = entry.configuration.selectedDice.dice.first {
                        firstDie.diceImage(for: firstDie.die.max)
                            .resizable()
                            .frame(width: 40, height: 40)
                            .widgetAccentable()
                    }
                }
            }

            // Dice type label
            Text(entry.configuration.selectedDice.name)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding()
    }
    
    // MARK: - Medium Widget
    
    private var mediumWidgetView: some View {
        HStack(spacing: 16) {
            // Left side - Current dice and result
            VStack(spacing: 8) {
                if let lastRoll = entry.configuration.lastRoll {
                    diceResultView(lastRoll)
                        .widgetAccentable()

                    if let timestamp = lastRoll.timestamp {
                        Text(timestamp, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    if let firstDie = entry.configuration.selectedDice.dice.first {
                        firstDie.diceImage(for: firstDie.die.max)
                            .resizable()
                            .frame(width: 50, height: 50)
                            .widgetAccentable()

                        Text(entry.configuration.selectedDice.name)
                            .font(.headline)
                            .widgetAccentable()
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Divider()

            // Right side - Quick dice selection using Liquid Glass
            VStack(spacing: 4) {
                Text("Quick Roll")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                quickDiceGrid
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
    }
    
    // MARK: - Large Widget
    
    private var largeWidgetView: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Dice Roller")
                    .font(.headline)
                    .widgetAccentable()

                Spacer()

                if let lastRoll = entry.configuration.lastRoll, let timestamp = lastRoll.timestamp {
                    Text(timestamp, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Main dice display
            if let lastRoll = entry.configuration.lastRoll {
                diceResultView(lastRoll)
                    .widgetAccentable()

                Text("Last Roll")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if let firstDie = entry.configuration.selectedDice.dice.first {
                    firstDie.diceImage(for: firstDie.die.max)
                        .resizable()
                        .frame(width: 60, height: 60)
                        .widgetAccentable()

                    Text(entry.configuration.selectedDice.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .widgetAccentable()
                }
            }

            Divider()

            // Dice selection grid with Liquid Glass
            Text("Quick Roll")
                .font(.caption)
                .foregroundStyle(.secondary)

            quickDiceGrid
        }
        .padding()
    }
    
    // MARK: - Components

    private func diceResultView(_ result: DiceResultModel) -> some View {
        VStack(spacing: 4) {
            ZStack {
                // Background circle with glass effect
                Circle()
                    .fill(resultColor(for: result).opacity(0.2))
                    .frame(width: 70, height: 70)

                if let firstDie = result.diceModel.dice.first {
                    firstDie.diceImage(for: result.sum)
                        .resizable()
                        .frame(width: 64, height: 64)
                }
            }

            Text(result.diceModel.name)
                .font(.caption)
                .fontWeight(.medium)
        }
    }

    private var quickDiceGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach([IntentDiceType.d4, .d6, .d8, .d10, .d12, .d20], id: \.self) { diceType in
                Button(intent: RollDiceIntent(diceType: diceType)) {
                    VStack(spacing: 2) {
                        let die = diceType.toDieModel()
                        die.diceImage(for: die.die.max)
                            .resizable()
                            .frame(width: 32, height: 32)
                        Text(diceType.rawValue)
                            .font(.system(size: 8))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
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
            return .secondary
        }
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    DiceRollerWidget()
} timeline: {
    DiceRollerEntry(
        date: .now,
        configuration: .default
    )
}

#Preview("Medium", as: .systemMedium) {
    DiceRollerWidget()
} timeline: {
    DiceRollerEntry(
        date: .now,
        configuration: .default
    )
}

#Preview("Large", as: .systemLarge) {
    DiceRollerWidget()
} timeline: {
    DiceRollerEntry(
        date: .now,
        configuration: .default
    )
}
