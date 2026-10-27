// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import Foundation

public enum DiceIntentSupport {
    /// Names the entity type this module's donations use, so they can be deleted when an item is
    /// trashed or purged. See CODE_AUDIT_AppIntents §4.4.
    @MainActor
    public static func registerDonations() {
        IntentEntityIdentifiers.register(DiceEntity.self, for: .dice)
    }

    @MainActor
    public static func reindexChanged(root: DiceRootModel) async {
        await reindexIntentEntities(
            itemDataModel: root.itemController.itemDataModel,
            module: .dice,
            model: { root.itemController.itemSync(for: $0) },
            makeEntity: { DiceEntity(root: root, model: $0) }
        )
    }
}

public struct DiceFrameworkPackage: AppIntentsPackage { }

#endif
