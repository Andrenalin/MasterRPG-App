// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import Foundation

public enum SpaceShortcutCatalog {
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
            intent: OpenSpaceIntent(),
            phrases: [
                "Open a 3D object in \(.applicationName)",
                "Show \(\.$target) in \(.applicationName)"
            ],
            shortTitle: "Open Space",
            systemImageName: "view.3d"
        )
    }

    public static var create: AppShortcut {
        AppShortcut(
            intent: CreateSpaceIntent(),
            phrases: [
                "Create a 3D object in \(.applicationName)"
            ],
            shortTitle: "Create 3D Object",
            systemImageName: "plus.circle"
        )
    }

    public static var addNote: AppShortcut {
        AppShortcut(
            intent: AddSpaceNoteIntent(),
            phrases: [
                "Add a note to a 3D object in \(.applicationName)"
            ],
            shortTitle: "Add 3D Note",
            systemImageName: "note.text.badge.plus"
        )
    }

    public static var search: AppShortcut {
        AppShortcut(
            intent: SearchSpacesIntent(),
            phrases: [
                "Search 3D objects in \(.applicationName)"
            ],
            shortTitle: "Search 3D Objects",
            systemImageName: "magnifyingglass"
        )
    }

    public static var delete: AppShortcut {
        AppShortcut(
            intent: DeleteSpaceIntent(),
            phrases: [
                "Delete a 3D object in \(.applicationName)"
            ],
            shortTitle: "Delete 3D Object",
            systemImageName: "trash"
        )
    }

    /// Names the entity type this module's donations use, so they can be deleted when an item is
    /// trashed or purged. See CODE_AUDIT_AppIntents §4.4.
    @MainActor
    public static func registerDonations() {
        IntentEntityIdentifiers.register(SpaceEntity.self, for: .space)
    }

    @MainActor
    public static func reindexAll(root: SpaceRootModel) async {
        await reindexIntentEntities(
            ids: root.itemController.itemDataModel.items,
            module: .space,
            model: { root.itemController.itemSync(for: $0) },
            makeEntity: { SpaceEntity(root: root, model: $0) }
        )
    }
}

public struct SpaceFrameworkPackage: AppIntentsPackage { }

#endif
