// @copyright André Trettin

import SwiftUI
import WidgetKit
import AppIntents

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
                if let lastRoll = entry.lastRoll {
                    // Show last roll result
                    diceResultView(lastRoll)
                        .widgetAccentable() // Primary content in accented mode
                } else {
                    // Show dice type icon
                    entry.selectedDice.dieImage
                    //Image(systemName: entry.selectedDice.systemImage)
                        .resizable()
                        .frame(width: 40, height: 40)
                        //.font(.system(size: 40))
                        //.foregroundStyle(.primary)
                        .widgetAccentable()
                }
            }
            
            // Dice type label
            Text(entry.selectedDice.rawValue)
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
                if let lastRoll = entry.lastRoll {
                    diceResultView(lastRoll)
                        .widgetAccentable()
                    
                    Text(lastRoll.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    entry.selectedDice.dieImage
                        .resizable()
                        .frame(width: 50, height: 50)
                        .widgetAccentable()
                    
                    Text(entry.selectedDice.rawValue)
                        .font(.headline)
                        .widgetAccentable()
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
                
                if let lastRoll = entry.lastRoll {
                    Text(lastRoll.timestamp, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Main dice display
            if let lastRoll = entry.lastRoll {
                diceResultView(lastRoll)
                    .widgetAccentable()
                
                Text("Last Roll")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                entry.selectedDice.dieImage
                    .resizable()
                    .frame(width: 60, height: 60)
                    .widgetAccentable()
                
                Text(entry.selectedDice.rawValue)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .widgetAccentable()
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
    
    private func diceResultView(_ result: DiceRollResult) -> some View {
        VStack(spacing: 4) {
            ZStack {
                // Background circle with glass effect
                Circle()
                    .fill(resultColor(for: result).opacity(0.2))
                    .frame(width: 70, height: 70)
                
                result.diceType.dieImage(result: result.value)
                    .frame(width: 64, height: 64)
                // Result value
//                Text("\(result.value)")
//                    .font(.system(size: 32, weight: .bold, design: .rounded))
//                    .foregroundStyle(resultColor(for: result))
            }
            
            Text(result.diceType.rawValue)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
    
    private var quickDiceGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(DiceType.allCases.prefix(6)) { diceType in
                Button(intent: RollDiceIntent(diceType: diceType)) {
                    VStack(spacing: 2) {
                        diceType.dieImage
                            .frame(width: 32, height: 32)
                        Text(diceType.rawValue)
                            .font(.system(size: 8))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                //.widgetAccentedRenderingMode(.monochrome)
            }
        }
    }
    
    private func resultColor(for result: DiceRollResult) -> Color {
        if result.isCritical {
            return .green
        } else if result.isCriticalFailure {
            return .red
        } else {
            return .blue
        }
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    DiceRollerWidget()
} timeline: {
    DiceRollerEntry(
        date: .now,
        selectedDice: .d20,
        lastRoll: DiceRollResult(value: 20, diceType: .d20, timestamp: .now),
        configuration: .default
    )
}

#Preview("Medium", as: .systemMedium) {
    DiceRollerWidget()
} timeline: {
    DiceRollerEntry(
        date: .now,
        selectedDice: .d20,
        lastRoll: DiceRollResult(value: 18, diceType: .d20, timestamp: .now),
        configuration: .default
    )
}

#Preview("Large", as: .systemLarge) {
    DiceRollerWidget()
} timeline: {
    DiceRollerEntry(
        date: .now,
        selectedDice: .d20,
        lastRoll: nil,
        configuration: .default
    )
}
