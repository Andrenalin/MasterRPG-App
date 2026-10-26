// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import Foundation

public enum AudioShortcutCatalog {
    /// Names the entity type this module's donations use, so they can be deleted when an item is
    /// trashed or purged. See CODE_AUDIT_AppIntents §4.4.
    @MainActor
    public static func registerDonations() {
        IntentEntityIdentifiers.register(AudioEntity.self, for: .audio)
    }

    @MainActor
    public static func reindexChanged(root: AudioRootModel) async {
        await reindexIntentEntities(
            itemDataModel: root.itemController.itemDataModel,
            module: .audio,
            model: { root.itemController.itemSync(for: $0) },
            makeEntity: { AudioEntity(root: root, model: $0) }
        )
    }
}

public struct AudioFrameworkPackage: AppIntentsPackage { }

#endif
