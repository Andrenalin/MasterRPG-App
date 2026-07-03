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

    @MainActor
    public static func reindexAll(root: TableRootModel) async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        let entities = root.itemController.itemDataModel.items.compactMap { id -> TableEntity? in
            guard let model = root.itemController.itemSync(for: id) else { return nil }
            return TableEntity(root: root, model: model)
        }
        try? await CSSearchableIndex.default().indexAppEntities(entities)
    }
}

public struct TableFrameworkPackage: AppIntentsPackage { }

#endif
