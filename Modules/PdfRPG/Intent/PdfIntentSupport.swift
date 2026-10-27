// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import Foundation

public enum PdfIntentSupport {
    /// Names the entity type this module's donations use, so they can be deleted when an item is
    /// trashed or purged. See CODE_AUDIT_AppIntents §4.4.
    @MainActor
    public static func registerDonations() {
        IntentEntityIdentifiers.register(PdfEntity.self, for: .pdf)
    }

    @MainActor
    public static func reindexChanged(root: PdfRootModel) async {
        await reindexIntentEntities(
            itemDataModel: root.itemController.itemDataModel,
            module: .pdf,
            model: { root.itemController.itemSync(for: $0) },
            makeEntity: { PdfEntity(root: root, model: $0) }
        )
    }
}

public struct PdfFrameworkPackage: AppIntentsPackage { }

#endif
