// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import Foundation

public enum TableIntentSupport {
    /// Names the entity type this module's donations use, so they can be deleted when an item is
    /// trashed or purged, and how an item is exported as text. See CODE_AUDIT_AppIntents §4.4,
    /// CODE_AUDIT_AppIntents3 §4.1.
    @MainActor
    public static func registerDonations(root: TableRootModel) {
        IntentEntityIdentifiers.register(TableEntity.self, for: .table)
        EntitySummaryExport.register(module: .table) { [weak root] id in
            guard let root, let model = root.itemController.itemSync(for: id) else { return nil }
            return IntentEntityText.document(of: model)
        }
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
