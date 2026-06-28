// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight

struct DeleteAdventureIntent: DeleteIntent {
    static let title: LocalizedStringResource = "Delete Adventure"

    @Parameter(title: "Adventures")
    var entities: [AdventureEntity]

    @Dependency var root: AdventureRootModel

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ids = entities.map(\.id)

        for id in ids {
            await root.editController.delete(itemId: id)
        }
        await root.itemController.save()

        CSSearchableIndex.default().deleteSearchableItems(
            withIdentifiers: ids.map(\.uuidString),
            completionHandler: nil
        )
        AdventureShortcuts.updateAppShortcutParameters()

        let count = entities.count
        let dialog: LocalizedStringResource = count == 1
            ? "Deleted 1 adventure."
            : "Deleted \(count) adventures."
        return .result(dialog: "Deleted \(count) adventures.")
    }
}

#endif
