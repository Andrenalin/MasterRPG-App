// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight

struct CreateAdventureIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Adventure"

    static var parameterSummary: some ParameterSummary {
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

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<AdventureEntity> & ProvidesDialog {
        let storyText = story.map { String($0.characters) } ?? ""
        let model = AdventureModel(id: UUID(), name: name, description: storyText)
        root.itemController.replace(model: model, isInsert: true)
        await root.itemController.save()

        let entity = AdventureEntity(root: root, model: model)
        try await CSSearchableIndex.default().indexAppEntities([entity])
        AdventureShortcuts.updateAppShortcutParameters()

        if openWhenCreated {
            await navigator.perform(route: KnownRoutes.adventures(model.id, nil))
        }

        return .result(value: entity, dialog: "Created \"\(name)\".")
    }
}

#endif
