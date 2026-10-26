// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import Foundation

public enum TableShortcutCatalog {
    public static var all: [AppShortcut] {
        [
            open,
            create,
            addRow,
            search,
            delete
        ]
    }

    public static var open: AppShortcut {
        AppShortcut(
            intent: OpenTableIntent(),
            phrases: [
                "Open a table in \(.applicationName)",
                "Show \(\.$target) in \(.applicationName)"
            ],
            shortTitle: "Open Table",
            systemImageName: "tablecells.fill"
        )
    }

    public static var create: AppShortcut {
        AppShortcut(
            intent: CreateTableIntent(),
            phrases: [
                "Create a table in \(.applicationName)"
            ],
            shortTitle: "Create Table",
            systemImageName: "plus.circle"
        )
    }

    public static var addRow: AppShortcut {
        AppShortcut(
            intent: AddTableRowIntent(),
            phrases: [
                "Add a row to a table in \(.applicationName)"
            ],
            shortTitle: "Add Table Row",
            systemImageName: "doc.badge.plus"
        )
    }

    public static var search: AppShortcut {
        AppShortcut(
            intent: SearchTablesIntent(),
            phrases: [
                "Search tables in \(.applicationName)"
            ],
            shortTitle: "Search Tables",
            systemImageName: "magnifyingglass"
        )
    }

    public static var delete: AppShortcut {
        AppShortcut(
            intent: DeleteTableIntent(),
            phrases: [
                "Delete a table in \(.applicationName)"
            ],
            shortTitle: "Delete Table",
            systemImageName: "trash"
        )
    }

    /// Names the entity type this module's donations use, so they can be deleted when an item is
    /// trashed or purged. See CODE_AUDIT_AppIntents §4.4.
    @MainActor
    public static func registerDonations() {
        IntentEntityIdentifiers.register(TableEntity.self, for: .table)
    }

    @MainActor
    public static func reindexChanged(root: TableRootModel) async {
        await reindexIntentEntities(
            itemDataModel: root.itemController.itemDataModel,
            module: .table,
            model: { root.itemController.itemSync(for: $0) },
            makeEntity: { TableEntity(root: root, model: $0) }
        )
    }
}

public struct TableFrameworkPackage: AppIntentsPackage { }

#endif
