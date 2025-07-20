// @copyright André Trettin

import CoreRPG
import AppIntents
import Foundation

@available(iOS 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, *)
struct PhotoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenPhotoIntent(),
            phrases: [
                "Open in \(.applicationName)",
                "Show \(\.$target) in \(.applicationName)"
            ],
            shortTitle: "Open Photo",
            systemImageName: "photo.on.rectangle.angled"
        )
    }
}

public struct PhotoFrameworkPackage: AppIntentsPackage { }

