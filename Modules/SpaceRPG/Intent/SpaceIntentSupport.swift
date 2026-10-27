// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import Foundation

public enum SpaceIntentSupport {
    /// Names the entity type this module's donations use, so they can be deleted when an item is
    /// trashed or purged. See CODE_AUDIT_AppIntents §4.4.
    @MainActor
    public static func registerDonations() {
        IntentEntityIdentifiers.register(SpaceEntity.self, for: .space)
    }

    @MainActor
    public static func reindexChanged(root: SpaceRootModel) async {
        await reindexIntentEntities(
            itemDataModel: root.itemController.itemDataModel,
            module: .space,
            model: { root.itemController.itemSync(for: $0) },
            makeEntity: { SpaceEntity(root: root, model: $0) }
        )
    }
}

public struct SpaceFrameworkPackage: AppIntentsPackage { }

#endif
