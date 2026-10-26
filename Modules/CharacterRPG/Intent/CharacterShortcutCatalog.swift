// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import Foundation

public enum CharacterShortcutCatalog {
    public static var all: [AppShortcut] {
        [
            open,
            create,
            addEntry,
            search,
            delete
        ]
    }

    public static var open: AppShortcut {
        AppShortcut(
            intent: OpenCharacterIntent(),
            phrases: [
                "Open a character in \(.applicationName)",
                "Show \(\.$target) in \(.applicationName)"
            ],
            shortTitle: "Open Character",
            systemImageName: "list.bullet.rectangle"
        )
    }

    public static var create: AppShortcut {
        AppShortcut(
            intent: CreateCharacterIntent(),
            phrases: [
                "Create a character in \(.applicationName)"
            ],
            shortTitle: "Create Character",
            systemImageName: "plus.circle"
        )
    }

    public static var addEntry: AppShortcut {
        AppShortcut(
            intent: AddCharacterEntryIntent(),
            phrases: [
                "Add an entry to a character in \(.applicationName)"
            ],
            shortTitle: "Add Character Entry",
            systemImageName: "doc.badge.plus"
        )
    }

    public static var search: AppShortcut {
        AppShortcut(
            intent: SearchCharactersIntent(),
            phrases: [
                "Search characters in \(.applicationName)"
            ],
            shortTitle: "Search Characters",
            systemImageName: "magnifyingglass"
        )
    }

    public static var delete: AppShortcut {
        AppShortcut(
            intent: DeleteCharacterIntent(),
            phrases: [
                "Delete a character in \(.applicationName)"
            ],
            shortTitle: "Delete Character",
            systemImageName: "trash"
        )
    }

    /// Names the entity type this module's donations use, so they can be deleted when an item is
    /// trashed or purged. See CODE_AUDIT_AppIntents §4.4.
    @MainActor
    public static func registerDonations() {
        IntentEntityIdentifiers.register(CharacterEntity.self, for: .value)
    }

    @MainActor
    public static func reindexChanged(root: CharacterRootModel) async {
        await reindexIntentEntities(
            itemDataModel: root.itemController.itemDataModel,
            module: .value,
            model: { root.itemController.itemSync(for: $0) },
            makeEntity: { CharacterEntity(root: root, model: $0) }
        )
    }
}

public struct CharacterFrameworkPackage: AppIntentsPackage { }

#endif
