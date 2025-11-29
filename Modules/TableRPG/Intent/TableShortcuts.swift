// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import Foundation

struct TableShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenTableIntent(),
            phrases: [
                "Open in \(.applicationName)",
                "Show \(\.$target) in \(.applicationName)"
            ],
            shortTitle: "Open Table",
            systemImageName: "tablecells.fill"
        )
    }
}

public struct TableFrameworkPackage: AppIntentsPackage { }

#endif
