// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import Foundation
import os.log

public enum AdventureShortcutCatalog {
    /// Names the entity type this module's donations use, so they can be deleted when an item is
    /// trashed or purged. See CODE_AUDIT_AppIntents §4.4.
    @MainActor
    public static func registerDonations() {
        IntentEntityIdentifiers.register(AdventureEntity.self, for: .adventure)
    }

    /// Whether adventures were added, renamed or removed since the last reindex, which is what
    /// the parameterized Siri phrases ("Open <adventure>") depend on.
    @MainActor
    public static func hasChanges(root: AdventureRootModel) -> Bool {
        root.itemController.itemDataModel.hasIndexChanges
    }

    @MainActor
    public static func reindexChanged(root: AdventureRootModel) async {
        await reindexIntentEntities(
            itemDataModel: root.itemController.itemDataModel,
            module: .adventure,
            model: { root.itemController.itemSync(for: $0) },
            makeEntity: { AdventureEntity(root: root, model: $0) }
        )
    }
}

public struct AdventureFrameworkPackage: AppIntentsPackage { }

#endif
