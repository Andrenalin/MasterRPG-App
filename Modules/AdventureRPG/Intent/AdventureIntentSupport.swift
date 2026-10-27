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

    /// The names the parameterized Siri phrases ("Open <adventure>") can resolve to: every adventure
    /// that is not in the trash, sorted. The phrase list only depends on these, so an edit of an
    /// adventure's text leaves them unchanged. See CODE_AUDIT §5.4.
    @MainActor
    public static func shortcutNames(root: AdventureRootModel) -> [String] {
        let controller = root.itemController
        return controller.itemDataModel.items
            .compactMap { controller.itemSync(for: $0) }
            .filter { $0.displayState != DisplayStateMask.totalHidden.rawValue }
            .map(\.name)
            .sorted()
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
