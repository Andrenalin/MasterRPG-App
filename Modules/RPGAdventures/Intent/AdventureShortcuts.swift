// @copyright André Trettin

#if !os(tvOS)

import AndrenalinKit
import AppIntents
import Foundation

struct AdventureShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenAdventureIntent(),
            phrases: [
                "Open in \(.applicationName)",
                "Show \(\.$target) in \(.applicationName)"
            ],
            shortTitle: "Open Adventure",
            systemImageName: "wand.and.stars"
        )
    }
}

public struct AdventureFrameworkPackage: AppIntentsPackage { }

#endif
