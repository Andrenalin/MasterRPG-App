// @copyright André Trettin

#if os(iOS)
@preconcurrency import ActivityKit
import Foundation
import CoreRPG

// MARK: - Activity Attributes

public struct DiceRollerActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var lastRoll: DiceWidgetRoll
        public var rollCount: Int
        public var favoriteDice: [DiceWidgetFavorite]

        public init(lastRoll: DiceWidgetRoll, rollCount: Int, favoriteDice: [DiceWidgetFavorite]) {
            self.lastRoll = lastRoll
            self.rollCount = rollCount
            self.favoriteDice = favoriteDice
        }
    }

    public var gameName: String
    public var startTime: Date

    public init(gameName: String, startTime: Date) {
        self.gameName = gameName
        self.startTime = startTime
    }
}

@MainActor
public final class DiceRollerLiveActivityManager {
    public static let shared = DiceRollerLiveActivityManager()

    // Isolated stored property: the manager is @MainActor and every access is
    // serialized through its methods — no unsafe opt-out needed.
    private var currentActivity: Activity<DiceRollerActivityAttributes>?

    private init() {}

    public func startOrUpdate(with result: DiceResultModel) async {
        // Check if Live Activities are enabled
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("Live Activities are not enabled")
            return
        }

        // Get game name from UserDefaults
        let defaults = UserDefaults(suiteName: UserDefaults.appGroupString)
        let gameName = defaults?.string(forKey: "currentGameName") ?? "RPG Game"

        let activity = currentActivity ?? Activity<DiceRollerActivityAttributes>.activities.first
        currentActivity = activity
        let snapshot = DiceWidgetSnapshot.loadFromUserDefaults()
        let roll = DiceWidgetRoll(result)

        if let activity {
            // Capture the current state before crossing isolation boundaries
            let currentRollCount = activity.content.state.rollCount

            // Update existing activity
            let updatedState = DiceRollerActivityAttributes.ContentState(
                lastRoll: roll,
                rollCount: currentRollCount + 1,
                favoriteDice: snapshot.favoriteDice
            )

            let activityContent = ActivityContent(
                state: updatedState,
                staleDate: Date().addingTimeInterval(60 * 60) // 1 hour
            )

            await activity.update(activityContent, alertConfiguration: nil)
        } else {
            // Start new activity
            let attributes = DiceRollerActivityAttributes(
                gameName: gameName,
                startTime: Date()
            )

            let initialState = DiceRollerActivityAttributes.ContentState(
                lastRoll: roll,
                rollCount: 1,
                favoriteDice: snapshot.favoriteDice
            )

            let content = ActivityContent(
                state: initialState,
                staleDate: Date().addingTimeInterval(60 * 60)
            )

            do {
                currentActivity = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
            } catch {
                print("Failed to start Live Activity: \(error)")
            }
        }
    }

    public func endActivity() async {
        // Capture activity reference before crossing isolation boundaries
        let activity = currentActivity
        guard let activity else { return }

        // Capture the current state before crossing isolation boundaries
        let currentState = activity.content.state

        let activityContent = ActivityContent(
            state: currentState,
            staleDate: Date()
        )

        await activity.end(activityContent, dismissalPolicy: .immediate)

        currentActivity = nil
    }

    public func endActivityWithDelay(seconds: TimeInterval = 10) async {
        // Capture activity reference before crossing isolation boundaries
        let activity = currentActivity
        guard let activity else { return }

        // Capture the current state before crossing isolation boundaries
        let currentState = activity.content.state

        let activityContent = ActivityContent(
            state: currentState,
            staleDate: Date()
        )

        await activity.end(
            activityContent,
            dismissalPolicy: .after(Date().addingTimeInterval(seconds))
        )

        currentActivity = nil
    }
}

#elseif !os(tVOS)
// MARK: - macOS Stub Implementation

import Foundation
import CoreRPG

/// Stub for macOS - Live Activities are not supported on macOS
public struct DiceRollerActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var lastRoll: DiceWidgetRoll
        public var rollCount: Int
        public var favoriteDice: [DiceWidgetFavorite]

        public init(lastRoll: DiceWidgetRoll, rollCount: Int, favoriteDice: [DiceWidgetFavorite]) {
            self.lastRoll = lastRoll
            self.rollCount = rollCount
            self.favoriteDice = favoriteDice
        }
    }

    public var gameName: String
    public var startTime: Date

    public init(gameName: String, startTime: Date) {
        self.gameName = gameName
        self.startTime = startTime
    }
}

@MainActor
public final class DiceRollerLiveActivityManager {
    public static let shared = DiceRollerLiveActivityManager()

    private init() {}

    public func startOrUpdate(with result: DiceResultModel) async {
        // No-op on macOS - Live Activities not supported
        print("Live Activities are not supported on macOS")
    }

    public func endActivity() async {
        // No-op on macOS
    }

    public func endActivityWithDelay(seconds: TimeInterval = 10) async {
        // No-op on macOS
    }
}

#endif
