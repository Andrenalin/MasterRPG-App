// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import Foundation
import os.log

public enum AdventureIntentSupport {
    /// Names the entity type this module's donations use, so they can be deleted when an item is
    /// trashed or purged, and how an adventure is exported as text. See CODE_AUDIT_AppIntents §4.4,
    /// CODE_AUDIT_AppIntents3 §4.1.
    @MainActor
    public static func registerDonations(root: AdventureRootModel) {
        IntentEntityIdentifiers.register(AdventureEntity.self, for: .adventure)
        EntitySummaryExport.register(module: .adventure) { [weak root] id in
            root?.itemController.itemSync(for: id).map { IntentEntityText.document(of: $0) }
        }
    }

    @MainActor
    public static func reindexChanged(root: AdventureRootModel) async {
        await reindexIntentEntities(
            itemDataModel: root.itemController.itemDataModel,
            module: .adventure,
            model: { root.itemController.itemSync(for: $0) },
            makeEntity: { AdventureEntity(root: root, model: $0) }
        )
    }
}

public struct AdventureFrameworkPackage: AppIntentsPackage { }

#endif
