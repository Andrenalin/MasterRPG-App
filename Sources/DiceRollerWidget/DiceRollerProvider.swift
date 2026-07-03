// @copyright André Trettin

import AppIntents
import CoreRPG
import DiceRPG
import SwiftUI
import WidgetKit

/// Timeline provider for the dice roller widget
struct DiceRollerProvider: AppIntentTimelineProvider {
    typealias Entry = DiceRollerEntry
    typealias Intent = ConfigureDiceWidgetIntent
    
    func placeholder(in context: Context) -> DiceRollerEntry {
        DiceRollerEntry(
            date: Date(),
            snapshot: .preview,
            intent: ConfigureDiceWidgetIntent()
        )
    }

    func snapshot(for configuration: ConfigureDiceWidgetIntent, in context: Context) async -> DiceRollerEntry {
        DiceRollerEntry(
            date: Date(),
            snapshot: .preview,
            intent: configuration
        )
    }

    func timeline(for configuration: ConfigureDiceWidgetIntent, in context: Context) async -> Timeline<DiceRollerEntry> {
        let snapshot = DiceWidgetSnapshot.loadFromUserDefaults()
        let defaults = UserDefaults(suiteName: UserDefaults.appGroupString)
        let isGameActive = defaults?.bool(forKey: UserDefaults.DiceKeys.isGameActive) ?? false

        let entry = DiceRollerEntry(
            date: Date(),
            snapshot: snapshot,
            intent: configuration,
            isGameActive: isGameActive,
            relevance: relevance(for: snapshot, isGameActive: isGameActive)
        )

        return Timeline(entries: [entry], policy: .never)
    }
    
    // iOS 18+: Provide recommended configurations
    func recommendations() -> [AppIntentRecommendation<ConfigureDiceWidgetIntent>] {
        return [
            AppIntentRecommendation(intent: ConfigureDiceWidgetIntent(), description: "Standard Dice Roller"),
            AppIntentRecommendation(
                intent: {
                    let intent = ConfigureDiceWidgetIntent()
                    intent.showFavoritesOnly = true
                    return intent
                }(),
                description: "Favorites Only"
            )
        ]
    }

    private func relevance(for snapshot: DiceWidgetSnapshot, isGameActive: Bool) -> TimelineEntryRelevance {
        if isGameActive {
            return TimelineEntryRelevance(score: 100, duration: 3600)
        }

        if let timestamp = snapshot.lastRoll?.timestamp {
            let timeSinceRoll = Date().timeIntervalSince(timestamp)
            if timeSinceRoll < 300 {
                return TimelineEntryRelevance(score: 75, duration: 300)
            }
            return TimelineEntryRelevance(score: 50, duration: 1800)
        }

        return TimelineEntryRelevance(score: 10)
    }
}

// MARK: - Entry Model with Relevance

struct DiceRollerEntry: TimelineEntry {
    let date: Date
    let snapshot: DiceWidgetSnapshot
    var intent: ConfigureDiceWidgetIntent = ConfigureDiceWidgetIntent()
    var isGameActive: Bool = false
    var relevance: TimelineEntryRelevance?

    static var preview: DiceRollerEntry {
        DiceRollerEntry(
            date: Date(),
            snapshot: .preview,
            intent: ConfigureDiceWidgetIntent()
        )
    }
}
