// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents

public struct DeleteAdventureIntent: DeleteIntent {
    public static let title: LocalizedStringResource = "Delete Adventure"
    public static let description = IntentDescription(
        "Moves adventures to the trash. They can be restored in the app.",
        categoryName: "Adventure",
        searchKeywords: ["remove", "trash", "campaign"]
    )
    /// A trashed item is recoverable, but a locked device should not be able to trash a campaign.
    /// Create, Add and the dice and audio intents stay open for use at the table.
    /// See CODE_AUDIT_AppIntents2 §6.1.
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Adventures")
    public var entities: [AdventureEntity]

    @Dependency var root: AdventureRootModel

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        try await requireReadyDatabase()
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
