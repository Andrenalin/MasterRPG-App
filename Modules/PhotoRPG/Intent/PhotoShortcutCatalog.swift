// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import Foundation

public enum PhotoShortcutCatalog {
    /// Names the entity type this module's donations use, so they can be deleted when an item is
    /// trashed or purged. See CODE_AUDIT_AppIntents §4.4.
    @MainActor
    public static func registerDonations() {
        IntentEntityIdentifiers.register(PhotoEntity.self, for: .photo)
    }

    @MainActor
    public static func reindexChanged(root: PhotoRootModel) async {
        await reindexIntentEntities(
            itemDataModel: root.itemController.itemDataModel,
            module: .photo,
            model: { root.itemController.itemSync(for: $0) },
            makeEntity: { PhotoEntity(root: root, model: $0) }
        )
    }
}

public struct PhotoFrameworkPackage: AppIntentsPackage { }

#endif
