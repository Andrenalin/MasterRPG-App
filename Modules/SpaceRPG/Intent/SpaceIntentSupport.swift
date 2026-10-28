// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreRPG
import Foundation

public enum SpaceIntentSupport {
    /// What Siri asks when an intent's 3D object is missing, e.g. deleted since Shortcuts cached it.
    static var targetPrompt: IntentDialog { .localized("Which 3D object?", bundle: .module) }

    /// Names the entity type this module's donations use, so they can be deleted when an item is
    /// trashed or purged, and how an item is exported as text. See CODE_AUDIT_AppIntents §4.4,
    /// CODE_AUDIT_AppIntents3 §4.1.
    @MainActor
    public static func registerIntentSupport(root: SpaceRootModel) {
        SpaceEntityQuery.registerIntentSupport(root: root)
    }

    @MainActor
    public static func reindexChanged(root: SpaceRootModel) async {
        await SpaceEntityQuery.reindexChanged(root: root)
    }
}

public struct SpaceFrameworkPackage: AppIntentsPackage { }

#endif
