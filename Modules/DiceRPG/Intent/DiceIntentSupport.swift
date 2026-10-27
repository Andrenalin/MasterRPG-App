// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import Foundation

public enum DiceIntentSupport {
    /// Names the entity type this module's donations use, so they can be deleted when an item is
    /// trashed or purged, and how an item is exported as text. See CODE_AUDIT_AppIntents §4.4,
    /// CODE_AUDIT_AppIntents3 §4.1.
    @MainActor
    public static func registerDonations(root: DiceRootModel) {
        IntentEntityIdentifiers.register(DiceEntity.self, for: .dice)
        EntitySummaryExport.register(module: .dice) { [weak root] id in
            guard let root, let model = root.itemController.itemSync(for: id) else { return nil }
            return IntentEntityText.document(of: model)
        }
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
