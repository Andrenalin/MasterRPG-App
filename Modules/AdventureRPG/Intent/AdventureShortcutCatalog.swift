// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import Foundation
import os.log

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
        let entities = root.itemController.itemDataModel.items.compactMap { id -> AdventureEntity? in
            guard let model = root.itemController.itemSync(for: id) else { return nil }
            return AdventureEntity(root: root, model: model)
        }
        do {
            // `indexIntentEntities` already guards `CSSearchableIndex.isIndexingAvailable()`
            // internally — see CODE_AUDIT §9.8.
            try await indexIntentEntities(entities)
        } catch {
            // Previously `try?`-discarded with no logging, unlike every other Spotlight
            // call in this module. See CODE_AUDIT §5.8.
            Logger.appIntents.error("Adventure reindexAll failed: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
        }
    }
}

public struct AdventureFrameworkPackage: AppIntentsPackage { }

#endif
