// @copyright André Trettin

import CoreRPG
import AppIntents
import Foundation

struct SpaceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenSpaceIntent(),
            phrases: [
                "Open in \(.applicationName)",
                "Show \(\.$target) in \(.applicationName)"
            ],
            shortTitle: "Open Space",
            systemImageName: "view.3d"
        )
    }
}

public struct SpaceFrameworkPackage: AppIntentsPackage { }

