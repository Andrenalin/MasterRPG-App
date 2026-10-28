// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreRPG
import Foundation

public enum WeatherIntentSupport {
    /// What Siri asks when an intent's weather is missing, e.g. deleted since Shortcuts cached it.
    static var targetPrompt: IntentDialog { .localized("Which weather?", bundle: .module) }

    /// Names the entity type this module's donations use, so they can be deleted when an item is
    /// trashed or purged, and how an item is exported as text. See CODE_AUDIT_AppIntents §4.4,
    /// CODE_AUDIT_AppIntents3 §4.1.
    @MainActor
    public static func registerIntentSupport(root: WeatherRootModel) {
        WeatherEntityQuery.registerIntentSupport(root: root)
    }

    @MainActor
    public static func reindexChanged(root: WeatherRootModel) async {
        await WeatherEntityQuery.reindexChanged(root: root)
    }
}

public struct WeatherFrameworkPackage: AppIntentsPackage { }

#endif
