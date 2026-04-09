// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI
import WidgetKit

/// Timeline provider for the dice roller widget
struct DiceRollerProvider: TimelineProvider {
    
    func placeholder(in context: Context) -> DiceRollerEntry {
        DiceRollerEntry(
            date: Date(),
            configuration: .default
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (DiceRollerEntry) -> Void) {
        let entry = DiceRollerEntry(
            date: Date(),
            configuration: .default
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DiceRollerEntry>) -> Void) {
        // Fetch user's preferred dice configuration
        let configuration = DiceConfiguration.loadFromUserDefaults()

        // Create entry with current state
        let entry = DiceRollerEntry(
            date: Date(),
            configuration: configuration
        )

        // Update timeline every 15 minutes to stay fresh
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
        completion(timeline)
    }
}

// MARK: - Entry Model

struct DiceRollerEntry: TimelineEntry {
    let date: Date
    let configuration: DiceConfiguration

    static var preview: DiceRollerEntry {
        DiceRollerEntry(
            date: Date(),
            configuration: .default
        )
    }
}
