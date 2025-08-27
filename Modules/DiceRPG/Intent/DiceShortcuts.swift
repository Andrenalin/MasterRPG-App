// @copyright André Trettin

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
            systemImageName: "apple.books.pages"
        )
    }
}

public struct DiceFrameworkPackage: AppIntentsPackage { }

