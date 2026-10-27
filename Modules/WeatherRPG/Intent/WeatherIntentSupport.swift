// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import Foundation

public enum WeatherIntentSupport {
    /// Names the entity type this module's donations use, so they can be deleted when an item is
    /// trashed or purged. See CODE_AUDIT_AppIntents §4.4.
    @MainActor
    public static func registerDonations() {
        IntentEntityIdentifiers.register(WeatherEntity.self, for: .weather)
    }

    @MainActor
    public static func reindexChanged(root: WeatherRootModel) async {
        await reindexIntentEntities(
            itemDataModel: root.itemController.itemDataModel,
            module: .weather,
            model: { root.itemController.itemSync(for: $0) },
            makeEntity: { WeatherEntity(root: root, model: $0) }
        )
    }
}

public struct WeatherFrameworkPackage: AppIntentsPackage { }

#endif
