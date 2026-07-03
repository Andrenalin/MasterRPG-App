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

    @MainActor
    public static func reindexAll(root: CharacterRootModel) async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        let entities = root.itemController.itemDataModel.items.compactMap { id -> CharacterEntity? in
            guard let model = root.itemController.itemSync(for: id) else { return nil }
            return CharacterEntity(root: root, model: model)
        }
        try? await CSSearchableIndex.default().indexAppEntities(entities)
    }
}

public struct CharacterFrameworkPackage: AppIntentsPackage { }

#endif
