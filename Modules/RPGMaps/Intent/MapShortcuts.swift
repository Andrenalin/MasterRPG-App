// @copyright André Trettin

#if !os(tvOS)

import AndrenalinKit
import AppIntents
import Foundation

struct MapShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenMapIntent(),
            phrases: [
                "Open in \(.applicationName)",
                "Show \(\.$target) in \(.applicationName)"
            ],
            shortTitle: "Open Map",
            systemImageName: "map"
        )
    }
}

public struct MapFrameworkPackage: AppIntentsPackage { }

#endif
