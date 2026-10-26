// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import Foundation
import os.log

public enum MapShortcutCatalog {
    /// Names the entity type this module's donations use, so they can be deleted when an item is
    /// trashed or purged. See CODE_AUDIT_AppIntents §4.4.
    @MainActor
    public static func registerDonations() {
        IntentEntityIdentifiers.register(MapEntity.self, for: .map)
    }

    @MainActor
    public static func reindexChanged(root: MapRootModel) async {
        await reindexIntentEntities(
            itemDataModel: root.itemController.itemDataModel,
            module: .map,
            model: { root.itemController.itemSync(for: $0) },
            makeEntity: { MapEntity(root: root, model: $0) }
        )
    }
}

public struct MapFrameworkPackage: AppIntentsPackage { }

#endif
