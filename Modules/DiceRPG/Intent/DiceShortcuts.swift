// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import Foundation

struct DiceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenDiceIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Open dice in \(.applicationName)",
                "Show \(\.$target) in \(.applicationName)"
            ],
            shortTitle: "Open Dice",
            systemImageName: "dice"
        )
        
        AppShortcut(
            intent: RollSpecificDiceIntent(),
            phrases: [
                "Roll my dice in \(.applicationName)",
                "Roll \(\.$dice) in \(.applicationName)"
            ],
            shortTitle: "Roll Dice",
            systemImageName: "dice"
        )
        
        AppShortcut(
            intent: RollDiceIntent(diceType: IntentDiceType.d20),
            phrases: [
                "Roll a D20 in \(.applicationName)",
                "Quick roll D20 in \(.applicationName)"
            ],
            shortTitle: "Roll D20",
            systemImageName: "dice.fill"
        )
        
        AppShortcut(
            intent: RollDiceIntent(diceType: IntentDiceType.d6),
            phrases: [
                "Roll a D6 in \(.applicationName)",
                "Quick roll D6 in \(.applicationName)"
            ],
            shortTitle: "Roll D6",
            systemImageName: "die.face.6.fill"
        )
        
        AppShortcut(
            intent: ShowDiceHistoryIntent(),
            phrases: [
                "Show dice history in \(.applicationName)",
                "What was my last roll in \(.applicationName)"
            ],
            shortTitle: "Dice History",
            systemImageName: "clock.arrow.circlepath"
        )
    }
    
    static var shortcutTileColor: ShortcutTileColor {
        .blue
    }
}

public struct DiceFrameworkPackage: AppIntentsPackage { }

#endif
