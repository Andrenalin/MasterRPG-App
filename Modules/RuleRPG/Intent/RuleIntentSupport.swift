// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreRPG
import CoreSpotlight
import Foundation

public enum RuleIntentSupport {
    /// Names the entity type this module's donations use, so they can be deleted when an item is
    /// trashed or purged, and how an item is exported as text. See CODE_AUDIT_AppIntents §4.4,
    /// CODE_AUDIT_AppIntents3 §4.1.
    @MainActor
    public static func registerDonations(root: RuleRootModel) {
        IntentEntityIdentifiers.register(RuleEntity.self, for: .rule)
        EntitySummaryExport.register(module: .rule) { [weak root] id in
            guard let root, let model = root.itemController.itemSync(for: id) else { return nil }
            return IntentEntityText.document(of: model)
        }
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
