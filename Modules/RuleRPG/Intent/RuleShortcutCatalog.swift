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

    @MainActor
    public static func reindexAll(root: RuleRootModel) async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        let entities: [RuleEntity] = root.itemController.itemDataModel.items.compactMap { id -> RuleEntity? in
            guard let model = root.itemController.itemSync(for: id), !model.specialCategory else {
                return nil
            }
            return RuleEntity(root: root, model: model)
        }
        try? await CSSearchableIndex.default().indexAppEntities(entities)
    }
}

public struct RuleFrameworkPackage: AppIntentsPackage {}

#endif
