// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import Foundation

public enum TableShortcutCatalog {
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
