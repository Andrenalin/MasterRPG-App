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

        await trashIntentItems(ids: ids, ofType: AdventureEntity.self, in: root)

        let count = entities.count
        let message = AttributedString(
            localized: "Deleted ^[\(count) adventure](inflect: true).",
            bundle: .module
        )
        return .result(dialog: "\(message)")
    }
}

#endif
