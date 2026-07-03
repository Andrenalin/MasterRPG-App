// @copyright André Trettin

import AppIntents
import CoreRPG
import DiceRPG
import SwiftUI
import WidgetKit

/// A widget that displays a dice roller with Liquid Glass design
struct DiceRollerWidget: Widget {
    let kind: String = DiceWidgetKind.roller
    
    private var supportedWidgetFamilies: [WidgetFamily] {
        #if os(iOS)
        return [
            .systemSmall,
            .systemMedium,
            .systemLarge
        ]
        #elseif os(macOS)
        return [
            .systemSmall,
            .systemMedium,
            .systemLarge
        ]
        #else
        return [
            .systemSmall,
            .systemMedium,
            .systemLarge
        ]
        #endif
    }
    
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: ConfigureDiceWidgetIntent.self,
            provider: DiceRollerProvider()
        ) { entry in
            DiceRollerWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    #if os(visionOS)
                    // visionOS: Use depth effect with Liquid Glass
                    Color.clear
                        .glassBackgroundEffect()
                    #else
                    // iOS/macOS: Adaptive background for Liquid Glass
                    Color.clear
                    #endif
                }
                .widgetAccentable() // iOS 18+: Full tinting support
                .invalidatableContent() // iOS 18+: Auto-refresh on interaction
                .widgetURL(DiceWidgetDeepLink.diceRoot)
        }
        .configurationDisplayName("Dice Roller")
        .description("Quickly roll dice for your RPG game with Liquid Glass design")
        .supportedFamilies(supportedWidgetFamilies)
        .containerBackgroundRemovable(true) // Enable Liquid Glass
        #if os(iOS)
        .disfavoredLocations([.standBy], for: [.systemSmall]) // iOS 18+: Optimize for StandBy
        #endif
    }
}

// MARK: - Lock Screen Accessory Widgets (iOS 18+)

#if os(iOS)
struct DiceRollerAccessoryWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: DiceWidgetKind.accessory,
            intent: ConfigureDiceWidgetIntent.self,
            provider: DiceRollerProvider()
        ) { entry in
            AccessoryDiceView(entry: entry)
                .containerBackground(for: .widget) { }
                .widgetAccentable()
                .widgetURL(DiceWidgetDeepLink.diceRoot)
        }
        .configurationDisplayName("Quick Dice")
        .description("Compact dice roller for Lock Screen")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

struct AccessoryDiceView: View {
    @Environment(\.widgetFamily) var family
    let entry: DiceRollerEntry
    
    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 2) {
                    if let lastRoll = entry.snapshot.lastRoll {
                        Image(systemName: diceSymbol(for: lastRoll.dice.sides))
                            .font(.system(size: 18))
                    }
                    Text("\(entry.snapshot.lastRoll?.sum ?? 0)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
            }
            
        case .accessoryRectangular:
            HStack(spacing: 8) {
                if let lastRoll = entry.snapshot.lastRoll {
                    Image(systemName: diceSymbol(for: lastRoll.dice.sides))
                        .font(.system(size: 20))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lastRoll.dice.name)
                            .font(.headline)
                        Text("\(lastRoll.sum)")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                    }
                } else {
                    Image(systemName: "dice.fill")
                    Text("No rolls yet")
                        .font(.caption)
                }
                Spacer()
            }
            
        case .accessoryInline:
            if let lastRoll = entry.snapshot.lastRoll {
                Text("🎲 \(lastRoll.dice.name): \(lastRoll.sum)")
            } else {
                Text("🎲 Tap to roll")
            }
            
        default:
            EmptyView()
        }
    }
    
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
}
#endif

// MARK: - Control Widget (iOS 18+)

#if os(iOS)
struct DiceRollerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: DiceWidgetKind.control) {
            ControlWidgetButton(action: RollDiceIntent(diceType: IntentDiceType.d20)) {
                Label("Roll D20", systemImage: "dice.fill")
            }
        }
        .displayName("Quick Roll D20")
        .description("Roll a D20 from Control Center")
    }
}
#endif

// MARK: - Widget Configuration Intent (iOS 18+)

struct ConfigureDiceWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Configure Dice Widget"
    static let description = IntentDescription("Customize your dice widget appearance")

    @Parameter(title: "Show Favorites Only", default: false)
    var showFavoritesOnly: Bool

    init() {}
}

// MARK: - Widget Bundle

@main
struct DiceRollerWidgetBundle: WidgetBundle {
    var body: some Widget {
        DiceRollerWidget()
        #if os(iOS)
        DiceRollerAccessoryWidget()
        DiceRollerControl()
        DiceRollerLiveActivity()
        #endif
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    DiceRollerWidget()
} timeline: {
    DiceRollerEntry.preview
}

#Preview(as: .systemMedium) {
    DiceRollerWidget()
} timeline: {
    DiceRollerEntry.preview
}

#if os(iOS)
#Preview("Lock Screen Circular", as: .accessoryCircular) {
    DiceRollerAccessoryWidget()
} timeline: {
    DiceRollerEntry.preview
}

#Preview("Lock Screen Rectangular", as: .accessoryRectangular) {
    DiceRollerAccessoryWidget()
} timeline: {
    DiceRollerEntry.preview
}
#endif
