// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents

public struct CreateAdventureIntent: AppIntent {
    public static let title: LocalizedStringResource = "Create Adventure"
    public static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    public static var parameterSummary: some ParameterSummary {
        Summary("Create adventure named \(\.$name)")
    }

    @Parameter(title: "Name", requestValueDialog: "What should the adventure be called?")
    var name: String

    @Parameter(title: "Story")
    var story: AttributedString?

    @Parameter(title: "Open When Created", default: true)
    var openWhenCreated: Bool

    @Dependency var root: AdventureRootModel
    @Dependency var navigator: Navigator

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<AdventureEntity> & ProvidesDialog {
        await DatabaseReadiness.wait()
        // Shared Spotlight glue (see CODE_AUDIT §9.8) — `indexIntentEntities` already
        // guards `CSSearchableIndex.isIndexingAvailable()` internally.
        // Siri and Shortcuts can pass an empty name: ask again instead of creating a blank
        // adventure. See CODE_AUDIT_21 §5.28.
        let trimmedName = try requiredIntentName(name, parameter: $name, prompt: "What should the adventure be called?")
        let storyText = intentPlainText(from: story)
        let model = AdventureModel(id: UUID(), name: trimmedName, description: storyText)
        root.itemController.replace(model: model, isInsert: true)
        await root.itemController.save()

        let entity = AdventureEntity(root: root, model: model)
        try await indexIntentEntities([entity])

        if openWhenCreated {
            await navigator.perform(route: KnownRoutes.adventures(model.id, nil))
            try await continueInForeground(alwaysConfirm: false)
        }

        return .result(value: entity, dialog: "Created \"\(trimmedName)\".")
    }
}

#endif
