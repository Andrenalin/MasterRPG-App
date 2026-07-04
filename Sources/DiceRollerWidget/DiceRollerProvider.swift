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
            configuration: DiceConfiguration(
                selectedDice: DiceModel.previewSnapshot,
                lastRoll: DiceResultModel(
                    diceModel: DiceModel.previewSnapshot,
                    result: .rolled,
                    values: "18",
                    sum: 18,
                    checked: false,
                    timeStamp: Date()
                ),
                availableDice: [.die20(color: .G), .die12(color: .G), .die6(color: .G)],
                showHistory: true,
                favoriteDice: []
            ),
            intent: ConfigureDiceWidgetIntent()
        )
    }

    func snapshot(for configuration: ConfigureDiceWidgetIntent, in context: Context) async -> DiceRollerEntry {
        DiceRollerEntry(
            date: Date(),
            configuration: .default,
            intent: configuration
        )
    }

    func timeline(for configuration: ConfigureDiceWidgetIntent, in context: Context) async -> Timeline<DiceRollerEntry> {
        // Load dice configuration
        let diceConfig = DiceConfiguration.loadFromUserDefaults()
        
        // Check game status for smart refresh
        let defaults = UserDefaults(suiteName: UserDefaults.appGroupString)
        let isGameActive = defaults?.bool(forKey: UserDefaults.DiceKeys.isGameActive) ?? false
        
        // Create entry
        let entry = DiceRollerEntry(
            date: Date(),
            configuration: diceConfig,
            intent: configuration
        )
        
        // Smart refresh policy based on game state
        let refreshInterval: TimeInterval
        if isGameActive {
            // Active game: Refresh every 5 minutes
            refreshInterval = 5 * 60
        } else if diceConfig.lastRoll != nil {
            // Recent activity: Refresh every 15 minutes
            refreshInterval = 15 * 60
        } else {
            // Idle: Refresh every 30 minutes
            refreshInterval = 30 * 60
        }
        
        let nextUpdate = Date().addingTimeInterval(refreshInterval)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        
        return timeline
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
}

// MARK: - Entry Model with Relevance

struct DiceRollerEntry: TimelineEntry {
    let date: Date
    let configuration: DiceConfiguration
    var intent: ConfigureDiceWidgetIntent = ConfigureDiceWidgetIntent()

    static var preview: DiceRollerEntry {
        DiceRollerEntry(
            date: Date(),
            configuration: .default,
            intent: ConfigureDiceWidgetIntent()
        )
    }
    
    // iOS 17+: Relevance for StandBy mode
    var relevance: TimelineEntryRelevance? {
        let defaults = UserDefaults(suiteName: UserDefaults.appGroupString)
        let isGameActive = defaults?.bool(forKey: UserDefaults.DiceKeys.isGameActive) ?? false
        
        if isGameActive {
            // High relevance during active game (shown prominently in StandBy)
            return TimelineEntryRelevance(score: 100, duration: 3600)
        } else if configuration.lastRoll != nil {
            // Medium relevance if there's recent activity
            let timeSinceRoll = Date().timeIntervalSince(configuration.lastRoll?.timestamp ?? Date.distantPast)
            if timeSinceRoll < 300 { // 5 minutes
                return TimelineEntryRelevance(score: 75, duration: 300)
            }
            return TimelineEntryRelevance(score: 50, duration: 1800)
        }
        return TimelineEntryRelevance(score: 10)
    }
}
