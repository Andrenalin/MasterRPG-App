// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import Foundation

public enum AdventureShortcutCatalog {
    public static var all: [AppShortcut] {
        [
            open,
            create,
            appendSection,
            startGame,
            search,
            delete
        ]
    }

    public static var open: AppShortcut {
        AppShortcut(
            intent: OpenAdventureIntent(),
            phrases: [
                "Open an adventure in \(.applicationName)",
                "Show \(\.$target) in \(.applicationName)"
            ],
            shortTitle: "Open Adventure",
            systemImageName: "wand.and.stars"
        )
    }

    public static var create: AppShortcut {
        AppShortcut(
            intent: CreateAdventureIntent(),
            phrases: [
                "Create a new adventure in \(.applicationName)"
            ],
            shortTitle: "Create Adventure",
            systemImageName: "plus.circle"
        )
    }

    public static var appendSection: AppShortcut {
        AppShortcut(
            intent: AppendAdventureSectionIntent(),
            phrases: [
                "Add a section to an adventure in \(.applicationName)"
            ],
            shortTitle: "Add Adventure Section",
            systemImageName: "doc.badge.plus"
        )
    }

    public static var startGame: AppShortcut {
        AppShortcut(
            intent: StartAdventureGameIntent(),
            phrases: [
                "Start an adventure in \(.applicationName)",
                "Play \(\.$target) in \(.applicationName)"
            ],
            shortTitle: "Start Adventure Game",
            systemImageName: "gamecontroller"
        )
    }

    public static var search: AppShortcut {
        AppShortcut(
            intent: SearchAdventuresIntent(),
            phrases: [
                "Search adventures in \(.applicationName)"
            ],
            shortTitle: "Search Adventures",
            systemImageName: "magnifyingglass"
        )
    }

    public static var delete: AppShortcut {
        AppShortcut(
            intent: DeleteAdventureIntent(),
            phrases: [
                "Delete an adventure in \(.applicationName)"
            ],
            shortTitle: "Delete Adventure",
            systemImageName: "trash"
        )
    }

    @MainActor
    public static func reindexAll(root: AdventureRootModel) async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        let entities = root.itemController.itemDataModel.items.compactMap { id -> AdventureEntity? in
            guard let model = root.itemController.itemSync(for: id) else { return nil }
            return AdventureEntity(root: root, model: model)
        }
        try? await CSSearchableIndex.default().indexAppEntities(entities)
    }
}

public struct AdventureFrameworkPackage: AppIntentsPackage { }

#endif
