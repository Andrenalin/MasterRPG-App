// @copyright André Trettin

import CoreRPG
import AppIntents
import Foundation

struct GeneratorShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenGeneratorIntent(),
            phrases: [
                "Open in \(.applicationName)",
                "Show \(\.$target) in \(.applicationName)"
            ],
            shortTitle: "Open Generator",
            systemImageName: "apple.intelligence"
        )
    }
}

public struct GeneratorFrameworkPackage: AppIntentsPackage { }

