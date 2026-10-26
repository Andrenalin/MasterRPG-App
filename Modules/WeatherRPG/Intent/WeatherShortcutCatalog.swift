// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import Foundation

public enum WeatherShortcutCatalog {
    public static var all: [AppShortcut] {
        [
            open,
            create,
            addNote,
            search,
            delete
        ]
    }

    public static var open: AppShortcut {
        AppShortcut(
            intent: OpenWeatherIntent(),
            phrases: [
                "Open weather in \(.applicationName)",
                "Show \(\.$target) in \(.applicationName)"
            ],
            shortTitle: "Open Weather",
            systemImageName: "cloud.bolt.rain"
        )
    }

    public static var create: AppShortcut {
        AppShortcut(
            intent: CreateWeatherIntent(),
            phrases: [
                "Create weather in \(.applicationName)"
            ],
            shortTitle: "Create Weather",
            systemImageName: "plus.circle"
        )
    }

    public static var addNote: AppShortcut {
        AppShortcut(
            intent: AddWeatherNoteIntent(),
            phrases: [
                "Add a note to weather in \(.applicationName)"
            ],
            shortTitle: "Add Weather Note",
            systemImageName: "note.text.badge.plus"
        )
    }

    public static var search: AppShortcut {
        AppShortcut(
            intent: SearchWeatherIntent(),
            phrases: [
                "Search weather in \(.applicationName)"
            ],
            shortTitle: "Search Weather",
            systemImageName: "magnifyingglass"
        )
    }

    public static var delete: AppShortcut {
        AppShortcut(
            intent: DeleteWeatherIntent(),
            phrases: [
                "Delete weather in \(.applicationName)"
            ],
            shortTitle: "Delete Weather",
            systemImageName: "trash"
        )
    }

    /// Names the entity type this module's donations use, so they can be deleted when an item is
    /// trashed or purged. See CODE_AUDIT_AppIntents §4.4.
    @MainActor
    public static func registerDonations() {
        IntentEntityIdentifiers.register(WeatherEntity.self, for: .weather)
    }

    @MainActor
    public static func reindexChanged(root: WeatherRootModel) async {
        await reindexIntentEntities(
            itemDataModel: root.itemController.itemDataModel,
            module: .weather,
            model: { root.itemController.itemSync(for: $0) },
            makeEntity: { WeatherEntity(root: root, model: $0) }
        )
    }
}

public struct WeatherFrameworkPackage: AppIntentsPackage { }

#endif
