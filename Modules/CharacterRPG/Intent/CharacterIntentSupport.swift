// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreRPG
import Foundation

public enum CharacterIntentSupport {
    /// What Siri asks when an intent's character is missing, e.g. deleted since Shortcuts cached it.
    static var targetPrompt: IntentDialog { .localized("Which character?", bundle: .module) }

    /// Names the entity type this module's donations use, so they can be deleted when an item is
    /// trashed or purged, and how an item is exported as text. See CODE_AUDIT_AppIntents §4.4,
    /// CODE_AUDIT_AppIntents3 §4.1.
    @MainActor
    public static func registerIntentSupport(root: CharacterRootModel) {
        CharacterEntityQuery.registerIntentSupport(root: root) { root, model in
            IntentEntityText.document(of: model) { root.linkController.calculate(entry: $0) ?? $0.content }
        }
    }

    @MainActor
    public static func reindexChanged(root: CharacterRootModel) async {
        await CharacterEntityQuery.reindexChanged(root: root)
    }
}

public struct CharacterFrameworkPackage: AppIntentsPackage { }

#endif
