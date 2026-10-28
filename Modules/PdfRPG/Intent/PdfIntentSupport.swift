// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreRPG
import Foundation

public enum PdfIntentSupport {
    /// What Siri asks when an intent's PDF is missing, e.g. deleted since Shortcuts cached it.
    static var targetPrompt: IntentDialog { .localized("Which PDF?", bundle: .module) }

    /// Names the entity type this module's donations use, so they can be deleted when an item is
    /// trashed or purged, and how an item is exported as text. See CODE_AUDIT_AppIntents §4.4,
    /// CODE_AUDIT_AppIntents3 §4.1.
    @MainActor
    public static func registerIntentSupport(root: PdfRootModel) {
        PdfEntityQuery.registerIntentSupport(root: root)
    }

    @MainActor
    public static func reindexChanged(root: PdfRootModel) async {
        await PdfEntityQuery.reindexChanged(root: root)
    }
}

public struct PdfFrameworkPackage: AppIntentsPackage { }

#endif
