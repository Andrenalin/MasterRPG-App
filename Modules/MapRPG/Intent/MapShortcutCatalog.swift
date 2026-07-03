// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import Foundation

public enum MapShortcutCatalog {
    public static var all: [AppShortcut] {
        [
            open,
            create,
            addRoom,
            search,
            delete
        ]
    }

    public static var open: AppShortcut {
        AppShortcut(
            intent: OpenMapIntent(),
            phrases: [
                "Open a map in \(.applicationName)",
                "Show \(\.$target) in \(.applicationName)"
            ],
            shortTitle: "Open Map",
            systemImageName: "map"
        )
    }

    public static var create: AppShortcut {
        AppShortcut(
            intent: CreateMapIntent(),
            phrases: [
                "Create a map in \(.applicationName)"
            ],
            shortTitle: "Create Map",
            systemImageName: "plus.circle"
        )
    }

    public static var addRoom: AppShortcut {
        AppShortcut(
            intent: AddMapRoomIntent(),
            phrases: [
                "Add a room to a map in \(.applicationName)"
            ],
            shortTitle: "Add Map Room",
            systemImageName: "doc.badge.plus"
        )
    }

    public static var search: AppShortcut {
        AppShortcut(
            intent: SearchMapsIntent(),
            phrases: [
                "Search maps in \(.applicationName)"
            ],
            shortTitle: "Search Maps",
            systemImageName: "magnifyingglass"
        )
    }

    public static var delete: AppShortcut {
        AppShortcut(
            intent: DeleteMapIntent(),
            phrases: [
                "Delete a map in \(.applicationName)"
            ],
            shortTitle: "Delete Map",
            systemImageName: "trash"
        )
    }

    @MainActor
    public static func reindexAll(root: MapRootModel) async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        let entities = root.itemController.itemDataModel.items.compactMap { id -> MapEntity? in
            guard let model = root.itemController.itemSync(for: id) else { return nil }
            return MapEntity(root: root, model: model)
        }
        try? await CSSearchableIndex.default().indexAppEntities(entities)
    }
}

public struct MapFrameworkPackage: AppIntentsPackage { }

#endif
