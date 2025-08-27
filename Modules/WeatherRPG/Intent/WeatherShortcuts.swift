// @copyright André Trettin

import CoreRPG
import AppIntents
import Foundation

struct WeatherShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenWeatherIntent(),
            phrases: [
                "Open in \(.applicationName)",
                "Show \(\.$target) in \(.applicationName)"
            ],
            shortTitle: "Open Weather",
            systemImageName: "cloud.bolt.rain"
        )
    }
}

public struct WeatherFrameworkPackage: AppIntentsPackage { }

