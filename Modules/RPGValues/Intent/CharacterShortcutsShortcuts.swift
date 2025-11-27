// @copyright André Trettin

#if !os(tvOS)

import AndrenalinKit
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
            systemImageName: "list.bullet.rectangle"
        )
    }
}

public struct CharacterFrameworkPackage: AppIntentsPackage { }

#endif
