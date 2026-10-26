// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import Foundation

public enum GeneratorShortcutCatalog {
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
            intent: OpenGeneratorIntent(),
            phrases: [
                "Open a generator in \(.applicationName)",
                "Show \(\.$target) in \(.applicationName)"
            ],
            shortTitle: "Open Generator",
            systemImageName: "apple.intelligence"
        )
    }

    public static var create: AppShortcut {
        AppShortcut(
            intent: CreateGeneratorIntent(),
            phrases: [
                "Create a generator in \(.applicationName)"
            ],
            shortTitle: "Create Generator",
            systemImageName: "plus.circle"
        )
    }

    public static var addNote: AppShortcut {
        AppShortcut(
            intent: AddGeneratorNoteIntent(),
            phrases: [
                "Add a note to a generator in \(.applicationName)"
            ],
            shortTitle: "Add Generator Note",
            systemImageName: "note.text.badge.plus"
        )
    }

    public static var search: AppShortcut {
        AppShortcut(
            intent: SearchGeneratorsIntent(),
            phrases: [
                "Search generators in \(.applicationName)"
            ],
            shortTitle: "Search Generators",
            systemImageName: "magnifyingglass"
        )
    }

    public static var delete: AppShortcut {
        AppShortcut(
            intent: DeleteGeneratorIntent(),
            phrases: [
                "Delete a generator in \(.applicationName)"
            ],
            shortTitle: "Delete Generator",
            systemImageName: "trash"
        )
    }

    /// Names the entity type this module's donations use, so they can be deleted when an item is
    /// trashed or purged. See CODE_AUDIT_AppIntents §4.4.
    @MainActor
    public static func registerDonations() {
        IntentEntityIdentifiers.register(GeneratorEntity.self, for: .generator)
    }

    @MainActor
    public static func reindexAll(root: GeneratorRootModel) async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        let entities = root.itemController.itemDataModel.items.compactMap { id -> GeneratorEntity? in
            guard let model = root.itemController.itemSync(for: id) else { return nil }
            return GeneratorEntity(root: root, model: model)
        }
        try? await CSSearchableIndex.default().indexAppEntities(entities)
    }
}

public struct GeneratorFrameworkPackage: AppIntentsPackage { }

#endif
