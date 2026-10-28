// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents

public struct CreateAdventureIntent: AppIntent {
    public static let title: LocalizedStringResource = "Create Adventure"
    public static let description = IntentDescription(
        "Creates a new adventure with a name and, optionally, the summary of its story.",
        categoryName: "Adventure",
        searchKeywords: ["campaign", "story", "quest", "new"]
    )
    public static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    public static var parameterSummary: some ParameterSummary {
        Summary("Create adventure named \(\.$name)")
    }

    @Parameter(title: "Name", requestValueDialog: .localized("What should the adventure be called?", bundle: .module))
    var name: String

    @Parameter(title: "Story", description: "The summary of the story. Formatting is kept.")
    var story: AttributedString?

    @Parameter(title: "Open When Created", description: "Shows the new adventure in the app.", default: false)
    var openWhenCreated: Bool

    @Dependency var root: AdventureRootModel
    @Dependency var navigator: Navigator

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<AdventureEntity> & ProvidesDialog {
        try await requireReadyDatabase()
        // Siri and Shortcuts can pass an empty name: ask again instead of creating a blank
        // adventure. See CODE_AUDIT_21 §5.28.
        let trimmedName = try requiredIntentName(name, parameter: $name, prompt: .localized("What should the adventure be called?", bundle: .module))
        let model = AdventureModel(id: UUID(), name: trimmedName, description: intentMarkdown(from: story))
        // Saved to the library also during a game. See CODE_AUDIT_Since_3.0.1 §5.2.
        root.itemController.replace(model: model, isInsert: true, forceSave: true)
        await root.itemController.save()

        let entity = AdventureEntity(root: root, model: model)
        await indexIntentEntities([entity])

        if openWhenCreated {
            await navigator.perform(route: KnownRoutes.adventures(model.id, nil))
            try await continueInForeground(alwaysConfirm: false)
        }

        return .result(value: entity, dialog: .localized("Created \"\(trimmedName)\".", bundle: .module))
    }
}

#endif
