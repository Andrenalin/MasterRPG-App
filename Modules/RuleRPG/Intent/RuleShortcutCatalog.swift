// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreRPG
import CoreSpotlight
import Foundation

public enum RuleShortcutCatalog {
    public static var all: [AppShortcut] {
        [open, create, addSection, search, delete]
    }

    public static var open: AppShortcut {
        AppShortcut(
            intent: OpenRuleIntent(),
            phrases: [
                "Open a rule in \(.applicationName)",
                "Show \(\.$target) in \(.applicationName)"
            ],
            shortTitle: "Open Rule",
            systemImageName: "book.closed"
        )
    }

    public static var create: AppShortcut {
        AppShortcut(
            intent: CreateRuleIntent(),
            phrases: ["Create a rule in \(.applicationName)"],
            shortTitle: "Create Rule",
            systemImageName: "plus.circle"
        )
    }

    public static var addSection: AppShortcut {
        AppShortcut(
            intent: AddRuleSectionIntent(),
            phrases: ["Add a section to a rule in \(.applicationName)"],
            shortTitle: "Add Rule Section",
            systemImageName: "doc.badge.plus"
        )
    }

    public static var search: AppShortcut {
        AppShortcut(
            intent: SearchRulesIntent(),
            phrases: ["Search rules in \(.applicationName)"],
            shortTitle: "Search Rules",
            systemImageName: "magnifyingglass"
        )
    }

    public static var delete: AppShortcut {
        AppShortcut(
            intent: DeleteRuleIntent(),
            phrases: ["Delete a rule in \(.applicationName)"],
            shortTitle: "Delete Rule",
            systemImageName: "trash"
        )
    }

    /// Names the entity type this module's donations use, so they can be deleted when an item is
    /// trashed or purged. See CODE_AUDIT_AppIntents §4.4.
    @MainActor
    public static func registerDonations() {
        IntentEntityIdentifiers.register(RuleEntity.self, for: .rule)
    }

    @MainActor
    public static func reindexChanged(root: RuleRootModel) async {
        await reindexIntentEntities(
            itemDataModel: root.itemController.itemDataModel,
            module: .rule,
            model: { root.itemController.itemSync(for: $0) },
            isIndexable: { !$0.specialCategory },
            makeEntity: { RuleEntity(root: root, model: $0) }
        )
    }
}

public struct RuleFrameworkPackage: AppIntentsPackage {}

#endif
