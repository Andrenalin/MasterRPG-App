// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import Foundation

public enum CharacterShortcutCatalog {
    /// Names the entity type this module's donations use, so they can be deleted when an item is
    /// trashed or purged. See CODE_AUDIT_AppIntents §4.4.
    @MainActor
    public static func registerDonations() {
        IntentEntityIdentifiers.register(CharacterEntity.self, for: .value)
    }

    @MainActor
    public static func reindexChanged(root: CharacterRootModel) async {
        await reindexIntentEntities(
            itemDataModel: root.itemController.itemDataModel,
            module: .value,
            model: { root.itemController.itemSync(for: $0) },
            makeEntity: { CharacterEntity(root: root, model: $0) }
        )
    }
}

public struct CharacterFrameworkPackage: AppIntentsPackage { }

#endif
