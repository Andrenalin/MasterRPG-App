// @copyright André Trettin

import WidgetKit
import SwiftUI
import CoreRPG

/// A widget that displays a dice roller with Liquid Glass design
struct DiceRollerWidget: Widget {
    let kind: String = "DiceRollerWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DiceRollerProvider()) { entry in
            DiceRollerWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    // Subtle background that will be replaced with Liquid Glass in accented mode
                    Color.clear
                }
        }
        .configurationDisplayName("Dice Roller")
        .description("Quickly roll dice for your RPG game")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .containerBackgroundRemovable(true) // Enable Liquid Glass effects
    }
}

// MARK: - Widget Bundle

@main
struct DiceRollerWidgetBundle: WidgetBundle {
    var body: some Widget {
        DiceRollerWidget()
        DiceRollerLiveActivity()
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    DiceRollerWidget()
} timeline: {
    DiceRollerEntry.preview
    DiceRollerEntry.preview
}

#Preview(as: .systemMedium) {
    DiceRollerWidget()
} timeline: {
    DiceRollerEntry.preview
}
