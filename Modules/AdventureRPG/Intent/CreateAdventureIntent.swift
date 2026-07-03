// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight

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
        let storyText = story.map { String($0.characters) } ?? ""
        let model = AdventureModel(id: UUID(), name: name, description: storyText)
        root.itemController.replace(model: model, isInsert: true)
        await root.itemController.save()

        let entity = AdventureEntity(root: root, model: model)
        if CSSearchableIndex.isIndexingAvailable() {
            try await CSSearchableIndex.default().indexAppEntities([entity])
        }

        if openWhenCreated {
            await navigator.perform(route: KnownRoutes.adventures(model.id, nil))
            try await continueInForeground(alwaysConfirm: false)
        }

        return .result(value: entity, dialog: "Created \"\(name)\".")
    }
}

#endif
