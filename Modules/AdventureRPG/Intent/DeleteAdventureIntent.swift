// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight

public struct DeleteAdventureIntent: DeleteIntent {
    public static let title: LocalizedStringResource = "Delete Adventure"

    @Parameter(title: "Adventures")
    public var entities: [AdventureEntity]

    @Dependency var root: AdventureRootModel

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let ids = entities.map(\.id)

        for id in ids {
            await root.editController.delete(itemId: id)
        }
        await root.itemController.save()

        if CSSearchableIndex.isIndexingAvailable() {
#if compiler(>=6.4)
            if #available(iOS 27, macOS 27, visionOS 27, *) {
                try await CSSearchableIndex.default().deleteAppEntities(
                    identifiedBy: ids,
                    ofType: AdventureEntity.self
                )
            } else {
                try await CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: ids.map(\.uuidString))
            }
#else
            try await CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: ids.map(\.uuidString))
#endif
        }

        let count = entities.count
        let message = AttributedString(
            localized: "Deleted ^[\(count) adventure](inflect: true).",
            bundle: .module
        )
        return .result(dialog: "\(message)")
    }
}

#endif
