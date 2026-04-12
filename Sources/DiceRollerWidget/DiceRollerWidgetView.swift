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
    
    /// Check if game is currently active
    private var isGameActive: Bool {
        UserDefaults(suiteName: UserDefaults.appGroupString)?.bool(forKey: UserDefaults.DiceKeys.isGameActive) ?? false
    }
    
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
            if let lastRoll = entry.configuration.lastRoll {
                // Show last roll result
                diceResultView(lastRoll)
            } else {
                // Show dice type icon
                if let firstDie = entry.configuration.selectedDice.dice.first {
                    dieImageView(firstDie, size: 40, sides: firstDie.die.max)
                }
            }

            // Dice type label
            Text(entry.configuration.selectedDice.name)
                .font(.caption)
                .fontWeight(.medium)
                .widgetAccentable()
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

                    if let timestamp = lastRoll.timestamp {
                        Text(timestamp, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    if let firstDie = entry.configuration.selectedDice.dice.first {
                        dieImageView(firstDie, size: 50, sides: firstDie.die.max)

                        Text(entry.configuration.selectedDice.name)
                            .font(.headline)
                            .widgetAccentable()
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Divider()

            // Right side - Show favorites only if game is active AND we have favorites
            // Otherwise always show quick roll
            VStack(spacing: 4) {
                if isGameActive && !entry.configuration.favoriteDice.isEmpty {
                    Text("Favorites")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    favoriteDiceGrid
                } else {
                    Text("Quick Roll")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    quickDiceGrid
                }
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

                Text("Last Roll")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if let firstDie = entry.configuration.selectedDice.dice.first {
                    dieImageView(firstDie, size: 60, sides: firstDie.die.max)

                    Text(entry.configuration.selectedDice.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .widgetAccentable()
                }
            }

            Divider()

            // Dice selection grid - Show favorites only if game is active AND we have favorites
            // Otherwise always show quick roll
            if isGameActive && !entry.configuration.favoriteDice.isEmpty {
                Text("Favorite Dice")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                favoriteDiceGrid
            } else {
                Text("Quick Roll")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                quickDiceGrid
            }
        }
        .padding()
    }
    
    // MARK: - Components

    /// Renders a die image that works correctly in both full color and tinted modes
    @ViewBuilder
    private func dieImageView(_ die: DieModel, size: CGFloat, sides: Int) -> some View {
        die.diceImage(for: sides)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            // Don't apply widgetAccentable to images - they should stay in full color
            .unredacted() // Ensure images always render
    }

    private func diceResultView(_ result: DiceResultModel) -> some View {
        VStack(spacing: 4) {
            ZStack {
                // Background circle - only show in full color mode
                if renderingMode == .fullColor {
                    Circle()
                        .fill(resultColor(for: result).opacity(0.2))
                        .frame(width: 70, height: 70)
                }

                if let firstDie = result.diceModel.dice.first {
                    dieImageView(firstDie, size: 64, sides: result.sum)
                }
            }
            .widgetAccentable() // Mark the entire result as accentable content

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
                        dieImageView(die, size: 32, sides: die.die.max)

                        Text(diceType.rawValue)
                            .font(.system(size: 8))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .invalidatableContent() // iOS 18: Auto-updates on tap
            }
        }
    }
    
    private var favoriteDiceGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(entry.configuration.favoriteDice.prefix(6)) { favorite in
                Button(intent: RollFavoriteDiceIntent(diceId: favorite.diceModel.id)) {
                    VStack(spacing: 2) {
                        if let firstDie = favorite.diceModel.dice.first {
                            dieImageView(firstDie, size: 32, sides: firstDie.die.max)
                        }
                        
                        Text(favorite.name)
                            .font(.system(size: 8))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
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
            return .gray
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
