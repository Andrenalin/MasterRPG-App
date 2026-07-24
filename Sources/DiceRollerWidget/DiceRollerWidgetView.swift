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
            if let lastRoll = entry.snapshot.lastRoll {
                // Show last roll result
                diceResultView(lastRoll)
            } else {
                // Show dice type icon
                dieImageView(entry.snapshot.selectedDice, size: 40)
            }

            // Dice type label
            Text(verbatim: entry.snapshot.selectedDice.name)
                .font(.caption)
                .widgetAccentable()
        }
        .padding()
        .accessibilityElement(children: .combine)
    }
    
    // MARK: - Medium Widget

    private var mediumWidgetView: some View {
        HStack(spacing: 16) {
            // Left side - Current dice and result
            VStack(spacing: 8) {
                if let lastRoll = entry.snapshot.lastRoll {
                    diceResultView(lastRoll)

                    if let timestamp = lastRoll.timestamp {
                        Text(timestamp, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    dieImageView(entry.snapshot.selectedDice, size: 50)

                    Text(verbatim: entry.snapshot.selectedDice.name)
                        .font(.headline)
                        .widgetAccentable()
                }
            }
            .frame(maxWidth: .infinity)

            Divider()

            VStack(spacing: 4) {
                Text("Quick Roll", bundle: .main)
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
                Text("Dice Roller", bundle: .main)
                    .font(.headline)
                    .widgetAccentable()

                Spacer()

                if let lastRoll = entry.snapshot.lastRoll, let timestamp = lastRoll.timestamp {
                    Text(timestamp, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Main dice display
            if let lastRoll = entry.snapshot.lastRoll {
                diceResultView(lastRoll)

                Text("Last Roll", bundle: .main)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                dieImageView(entry.snapshot.selectedDice, size: 60)

                Text(verbatim: entry.snapshot.selectedDice.name)
                    .font(.title2)
                    .bold()
                    .widgetAccentable()
            }

            Divider()

            Text("Quick Roll", bundle: .main)
                .font(.caption)
                .foregroundStyle(.secondary)

            quickDiceGrid
        }
        .padding()
    }
    
    // MARK: - Components

    /// Renders a die image that works correctly in both full color and tinted modes
    @ViewBuilder
    private func dieImageView(_ dice: DiceWidgetDice, size: CGFloat) -> some View {
        dice.dieModel.diceImage(for: dice.displayFace)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            // Don't apply widgetAccentable to images - they should stay in full color
            .unredacted() // Ensure images always render
            .accessibilityHidden(true)
    }

    private func diceResultView(_ result: DiceWidgetRoll) -> some View {
        VStack(spacing: 4) {
            ZStack {
                // Background circle - only show in full color mode
                if renderingMode == .fullColor {
                    Circle()
                        .fill(resultColor(for: result).opacity(0.2))
                        .frame(width: 70, height: 70)
                }

                dieImageView(result.dice, size: 64)
            }
            .widgetAccentable() // Mark the entire result as accentable content

            Text(verbatim: result.dice.name)
                .font(.caption)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: result.dice.name))
        .accessibilityValue(Text(verbatim: "\(result.sum)"))
    }

    private var quickDiceGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach([IntentDiceType.d4, .d6, .d8, .d10, .d12, .d20], id: \.self) { diceType in
                Button(intent: RollDiceIntent(diceType: diceType)) {
                    VStack(spacing: 2) {
                        let die = diceType.toDieModel()
                        dieImageView(
                            DiceWidgetDice(id: die.id, name: diceType.rawValue, sides: die.die.max),
                            size: 32
                        )

                        Text(verbatim: diceType.rawValue)
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .invalidatableContent() // iOS 18: Auto-updates on tap
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
}

// MARK: - Previews

#Preview("Dice roller view") {
    DiceRollerWidgetView(
        entry: DiceRollerEntry(
            date: Date(timeIntervalSinceReferenceDate: 800_000_000),
            snapshot: .preview
        )
    )
    .containerBackground(for: .widget) { }
}

#Preview("Small", as: .systemSmall) {
    DiceRollerWidget()
} timeline: {
    DiceRollerEntry(
        date: .now,
        snapshot: .preview
    )
}

#Preview("Medium", as: .systemMedium) {
    DiceRollerWidget()
} timeline: {
    DiceRollerEntry(
        date: .now,
        snapshot: .preview
    )
}

#Preview("Large", as: .systemLarge) {
    DiceRollerWidget()
} timeline: {
    DiceRollerEntry(
        date: .now,
        snapshot: .preview
    )
}
