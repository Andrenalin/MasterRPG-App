// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import Foundation

// MARK: - Shared App Intents (accessible from both app and widget)

/// App Intent for rolling simple dice (D4-D20)
public struct RollDiceIntent: AppIntent {
    public static let title: LocalizedStringResource = "Roll Dice"
    public static let description = IntentDescription("Roll a dice and show the result")
    
    // iOS 18: Support for interactive widgets
    public static let isDiscoverable = true
    public static let openAppWhenRun = false
    
    @Parameter(title: "Dice Type", default: .d20)
    public var diceType: IntentDiceType
    
    public init(diceType: IntentDiceType) {
        self.diceType = diceType
    }
    
    public init() {
        self.diceType = .d20
    }
    
    public func perform() async throws -> some IntentResult {
        // This is a simple intent that just creates a URL to open the app
        // The full implementation is in DiceRollerIntents.swift for widgets
        let urlString = "gamerpg://dice/400/\(UUID().uuidString)/roll?type=\(diceType.rawValue)"
        guard let url = URL(string: urlString) else {
            return .result()
        }
        
        return .result(opensIntent: OpenURLIntent(url))
    }
}

/// App Intent for showing dice history
public struct ShowDiceHistoryIntent: AppIntent {
    public static let title: LocalizedStringResource = "Show Dice History"
    public static let description = IntentDescription("Show recent dice rolls")
    
    public init() {}
    
    public func perform() async throws -> some IntentResult {
        // Open app to history view
        let urlString = "gamerpg://dice/0/history"
        guard let url = URL(string: urlString) else {
            return .result()
        }
        
        return .result(opensIntent: OpenURLIntent(url))
    }
}

// MARK: - Dice Type for Intents

/// Simple dice type enum that conforms to AppEnum for use in intents
public enum IntentDiceType: String, AppEnum {
    case d4 = "D4"
    case d6 = "D6"
    case d8 = "D8"
    case d10 = "D10"
    case d12 = "D12"
    case d20 = "D20"
    case d100 = "D100"
    
    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Dice Type")
    }
    
    public static var caseDisplayRepresentations: [IntentDiceType: DisplayRepresentation] {
        [
            .d4: DisplayRepresentation(title: "D4", subtitle: "4-sided die"),
            .d6: DisplayRepresentation(title: "D6", subtitle: "6-sided die"),
            .d8: DisplayRepresentation(title: "D8", subtitle: "8-sided die"),
            .d10: DisplayRepresentation(title: "D10", subtitle: "10-sided die"),
            .d12: DisplayRepresentation(title: "D12", subtitle: "12-sided die"),
            .d20: DisplayRepresentation(title: "D20", subtitle: "20-sided die"),
            .d100: DisplayRepresentation(title: "D100", subtitle: "100-sided die")
        ]
    }
}

#endif
