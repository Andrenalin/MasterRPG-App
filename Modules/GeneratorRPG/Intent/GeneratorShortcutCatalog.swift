// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import Foundation

public enum GeneratorShortcutCatalog {
    /// Names the entity type this module's donations use, so they can be deleted when an item is
    /// trashed or purged. See CODE_AUDIT_AppIntents §4.4.
    @MainActor
    public static func registerDonations() {
        IntentEntityIdentifiers.register(GeneratorEntity.self, for: .generator)
    }

    @MainActor
    public static func reindexChanged(root: GeneratorRootModel) async {
        await reindexIntentEntities(
            itemDataModel: root.itemController.itemDataModel,
            module: .generator,
            model: { root.itemController.itemSync(for: $0) },
            makeEntity: { GeneratorEntity(root: root, model: $0) }
        )
    }
}

public struct GeneratorFrameworkPackage: AppIntentsPackage { }

#endif
