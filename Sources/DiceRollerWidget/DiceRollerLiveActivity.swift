// @copyright André Trettin

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Live Activity for dice rolling during active gameplay
struct DiceRollerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DiceRollerActivityAttributes.self) { context in
            // Lock Screen / Banner UI
            DiceRollerLiveActivityView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.3))
                .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    diceIconView(for: context.state.lastRoll.diceType)
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    diceResultBadge(for: context.state.lastRoll)
                }
                
                DynamicIslandExpandedRegion(.center) {
                    Text("Roll: \(context.state.lastRoll.value)")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    quickRollButtons
                        .padding(.top, 8)
                }
            } compactLeading: {
                // Compact leading UI
                context.state.lastRoll.diceType.dieImage
                    .frame(width: 16, height: 16)
                    .foregroundStyle(compactResultColor(for: context.state.lastRoll))
            } compactTrailing: {
                // Compact trailing UI
                Text("\(context.state.lastRoll.value)")
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(compactResultColor(for: context.state.lastRoll))
            } minimal: {
                // Minimal UI
                context.state.lastRoll.diceType.dieImage
                    .frame(width: 16, height: 16)
                    .foregroundStyle(compactResultColor(for: context.state.lastRoll))
            }
            .widgetURL(URL(string: "masterrpg://dice"))
            .keylineTint(compactResultColor(for: context.state.lastRoll))
        }
    }
    
    // MARK: - Helper Views
    
    private func diceIconView(for diceType: DiceType) -> some View {
        diceType.dieImage
            .font(.title2)
            .foregroundStyle(.white)
    }
    
    private func diceResultBadge(for result: DiceRollResult) -> some View {
        ZStack {
            Circle()
                .fill(resultColor(for: result))
                .frame(width: 40, height: 40)
            
            Text("\(result.value)")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.white)
        }
    }
    
    private var quickRollButtons: some View {
        HStack(spacing: 12) {
            ForEach([DiceType.d4, .d6, .d8, .d10, .d12, .d20], id: \.self) { diceType in
                Button(intent: RollDiceIntent(diceType: diceType)) {
                    VStack(spacing: 2) {
                        diceType.dieImage
                            .frame(width: 16, height: 16)
                        Text(diceType.rawValue)
                            .font(.system(size: 8))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
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
    
    private func compactResultColor(for result: DiceRollResult) -> Color {
        if result.isCritical {
            return .green
        } else if result.isCriticalFailure {
            return .red
        } else {
            return .white
        }
    }
}

// MARK: - Lock Screen View

struct DiceRollerLiveActivityView: View {
    let context: ActivityViewContext<DiceRollerActivityAttributes>
    
    var body: some View {
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: 16) {
                // Left side - Dice result with Liquid Glass
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(resultColor.opacity(0.3))
                            .frame(width: 60, height: 60)
                        
                        Text("\(context.state.lastRoll.value)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .glassEffect(.regular.tint(resultColor).interactive())
                    
                    Text(context.state.lastRoll.diceType.rawValue)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white.opacity(0.8))
                }
                
                Divider()
                    .background(.white.opacity(0.3))
                
                // Right side - Quick roll buttons with Liquid Glass
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick Roll")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                    
                    HStack(spacing: 8) {
                        ForEach([DiceType.d20, .d12, .d10], id: \.self) { diceType in
                            Button(intent: RollDiceIntent(diceType: diceType)) {
                                VStack(spacing: 2) {
                                    diceType.dieImage
                                        .frame(width: 24, height: 24)
                                    Text(diceType.rawValue)
                                        .font(.system(size: 8))
                                }
                                .frame(width: 40, height: 40)
                            }
                            .buttonStyle(.glass)
                        }
                    }
                }
                
                Spacer()
                
                // Game status
                VStack(alignment: .trailing, spacing: 4) {
                    Text(context.attributes.gameName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                    
                    Text("Active")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
            .padding()
        }
    }
    
    private var resultColor: Color {
        let result = context.state.lastRoll
        if result.isCritical {
            return .green
        } else if result.isCriticalFailure {
            return .red
        } else {
            return .blue
        }
    }
}

// MARK: - Activity Attributes

struct DiceRollerActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var lastRoll: DiceRollResult
        var rollCount: Int
    }
    
    var gameName: String
    var startTime: Date
}

// MARK: - Live Activity Manager

@MainActor
class DiceRollerLiveActivityManager {
    static let shared = DiceRollerLiveActivityManager()
    
    private var currentActivity: Activity<DiceRollerActivityAttributes>?
    
    private init() {}
    
    func startOrUpdate(with result: DiceRollResult) async {
        // Check if Live Activities are enabled
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("Live Activities are not enabled")
            return
        }
        
        // Get game name from UserDefaults
        let defaults = UserDefaults(suiteName: "group.de.andretrettin.MasterRPG")
        let gameName = defaults?.string(forKey: "currentGameName") ?? "RPG Game"
        
        if let activity = currentActivity {
            // Update existing activity
            let updatedState = DiceRollerActivityAttributes.ContentState(
                lastRoll: result,
                rollCount: (activity.content.state.rollCount) + 1
            )
            
            await activity.update(
                ActivityContent(
                    state: updatedState,
                    staleDate: Date().addingTimeInterval(60 * 60) // 1 hour
                ),
                alertConfiguration: nil
            )
        } else {
            // Start new activity
            let attributes = DiceRollerActivityAttributes(
                gameName: gameName,
                startTime: Date()
            )
            
            let initialState = DiceRollerActivityAttributes.ContentState(
                lastRoll: result,
                rollCount: 1
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
    
    func endActivity() async {
        guard let activity = currentActivity else { return }
        
        await activity.end(
            ActivityContent(
                state: activity.content.state,
                staleDate: Date()
            ),
            dismissalPolicy: .immediate
        )
        
        currentActivity = nil
    }
    
    func endActivityWithDelay(seconds: TimeInterval = 10) async {
        guard let activity = currentActivity else { return }
        
        await activity.end(
            ActivityContent(
                state: activity.content.state,
                staleDate: Date()
            ),
            dismissalPolicy: .after(Date().addingTimeInterval(seconds))
        )
        
        currentActivity = nil
    }
}
