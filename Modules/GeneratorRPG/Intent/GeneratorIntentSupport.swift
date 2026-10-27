// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import Foundation

public enum GeneratorIntentSupport {
    /// Names the entity type this module's donations use, so they can be deleted when an item is
    /// trashed or purged, and how an item is exported as text. See CODE_AUDIT_AppIntents §4.4,
    /// CODE_AUDIT_AppIntents3 §4.1.
    @MainActor
    public static func registerDonations(root: GeneratorRootModel) {
        IntentEntityIdentifiers.register(GeneratorEntity.self, for: .generator)
        EntitySummaryExport.register(module: .generator) { [weak root] id in
            guard let root, let model = root.itemController.itemSync(for: id) else { return nil }
            return IntentEntityText.document(of: model)
        }
    }

    @MainActor
    public static func reindexChanged(root: GeneratorRootModel) async {
        await reindexIntentEntities(
            itemDataModel: root.itemController.itemDataModel,
            module: .generator,
            model: { root.itemController.itemSync(for: $0) },
            makeEntity: { GeneratorEntity(root: root, model: $0) }
        )
    }
}

public struct GeneratorFrameworkPackage: AppIntentsPackage { }

#endif
