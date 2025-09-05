// @copyright André Trettin

import CoreRPG
import AppIntents
import Foundation

struct CharacterShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenCharacterIntent(),
            phrases: [
                "Open in \(.applicationName)",
                "Show \(\.$target) in \(.applicationName)"
            ],
            shortTitle: "Open Character",
            systemImageName: "tablecells.fill"
        )
    }
}

public struct CharacterFrameworkPackage: AppIntentsPackage { }

