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

    /// Names the entity type this module's donations use, so they can be deleted when an item is
    /// trashed or purged. See CODE_AUDIT_AppIntents §4.4.
    @MainActor
    public static func registerDonations() {
        IntentEntityIdentifiers.register(AdventureEntity.self, for: .adventure)
    }

    @MainActor
    public static func reindexAll(root: AdventureRootModel) async {
        await reindexIntentEntities(
            ids: root.itemController.itemDataModel.items,
            module: .adventure,
            model: { root.itemController.itemSync(for: $0) },
            makeEntity: { AdventureEntity(root: root, model: $0) }
        )
    }
}

public struct AdventureFrameworkPackage: AppIntentsPackage { }

#endif
