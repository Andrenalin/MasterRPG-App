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
                "Open in \(.applicationName)",
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

    }
}

public struct DiceFrameworkPackage: AppIntentsPackage { }

#endif
