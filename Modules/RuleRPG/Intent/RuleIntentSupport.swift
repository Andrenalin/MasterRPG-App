// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreRPG
import CoreSpotlight
import Foundation

public enum RuleIntentSupport {
    /// Names the entity type this module's donations use, so they can be deleted when an item is
    /// trashed or purged. See CODE_AUDIT_AppIntents §4.4.
    @MainActor
    public static func registerDonations() {
        IntentEntityIdentifiers.register(RuleEntity.self, for: .rule)
    }

    @MainActor
    public static func reindexChanged(root: RuleRootModel) async {
        await reindexIntentEntities(
            itemDataModel: root.itemController.itemDataModel,
            module: .rule,
            model: { root.itemController.itemSync(for: $0) },
            isIndexable: { !$0.specialCategory },
            makeEntity: { RuleEntity(root: root, model: $0) }
        )
    }
}

public struct RuleFrameworkPackage: AppIntentsPackage {}

#endif
