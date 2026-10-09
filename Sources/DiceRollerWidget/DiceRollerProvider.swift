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
        let now = Date()
        var entries = [
            DiceRollerEntry(
                date: now,
                snapshot: snapshot,
                intent: configuration,
                relevance: relevance(for: snapshot, at: now)
            )
        ]
        // A second entry for when the roll stops being recent. With the one entry and the
        // policy `.never` the "recent roll" relevance stayed until the next roll.
        // See CODE_AUDIT_21 §7.10.
        if let rolled = snapshot.lastRoll?.timestamp {
            let recentUntil = rolled.addingTimeInterval(Self.recentRollInterval)
            if recentUntil > now {
                entries.append(DiceRollerEntry(
                    date: recentUntil,
                    snapshot: snapshot,
                    intent: configuration,
                    relevance: relevance(for: snapshot, at: recentUntil)
                ))
            }
        }

        return Timeline(entries: entries, policy: .never)
    }

    /// How long a roll counts as recent for the Smart Stack.
    private static let recentRollInterval: TimeInterval = 300
    
    // iOS 18+: Provide recommended configurations
    func recommendations() -> [AppIntentRecommendation<ConfigureDiceWidgetIntent>] {
        [AppIntentRecommendation(intent: ConfigureDiceWidgetIntent(), description: "Standard Dice Roller")]
    }

    private func relevance(for snapshot: DiceWidgetSnapshot, at date: Date) -> TimelineEntryRelevance {
        if let timestamp = snapshot.lastRoll?.timestamp {
            let timeSinceRoll = date.timeIntervalSince(timestamp)
            if timeSinceRoll < Self.recentRollInterval {
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
    var relevance: TimelineEntryRelevance?

    static var preview: DiceRollerEntry {
        DiceRollerEntry(
            date: Date(),
            snapshot: .preview,
            intent: ConfigureDiceWidgetIntent()
        )
    }
}
