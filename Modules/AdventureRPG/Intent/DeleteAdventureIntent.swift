// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents

public struct DeleteAdventureIntent: DeleteIntent {
    public static let title: LocalizedStringResource = "Delete Adventure"

    @Parameter(title: "Adventures")
    public var entities: [AdventureEntity]

    @Dependency var root: AdventureRootModel

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        await DatabaseReadiness.wait()
        let ids = entities.map(\.id)

        for id in ids {
            await root.editController.delete(itemId: id)
        }
        await root.itemController.save()

        // Shared Spotlight glue (see CODE_AUDIT §9.8) — `deleteIntentEntities` already
        // guards `isIndexingAvailable()` and the iOS 27 `deleteAppEntities` availability
        // split internally.
        try await deleteIntentEntities(ids: ids, ofType: AdventureEntity.self)

        let count = entities.count
        let message = AttributedString(
            localized: "Deleted ^[\(count) adventure](inflect: true).",
            bundle: .module
        )
        return .result(dialog: "\(message)")
    }
}

#endif
