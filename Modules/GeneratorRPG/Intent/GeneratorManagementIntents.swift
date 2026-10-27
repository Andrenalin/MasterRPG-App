// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreSpotlight
import CoreRPG
import Foundation

struct CreateGeneratorIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Generator"
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    static var parameterSummary: some ParameterSummary {
        Summary("Create generator named \(\.$name)")
    }

    @Parameter(title: "Name", requestValueDialog: "What should the generator be called?")
    var name: String

    @Parameter(title: "Instructions")
    var instructions: AttributedString?

    @Parameter(title: "Open When Created", default: false)
    var openWhenCreated: Bool

    @Dependency var root: GeneratorRootModel
    @Dependency var navigator: Navigator

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<GeneratorEntity> & ProvidesDialog {
        try await requireReadyDatabase()
        // Siri and Shortcuts can pass an empty name: ask again instead of creating a blank item.
        // See CODE_AUDIT_AppIntents §5.2.
        let trimmedName = try requiredIntentName(name, parameter: $name, prompt: "What should the generator be called?")
        let model = GeneratorModel(
            id: UUID(),
            name: trimmedName,
            description: intentPlainText(from: instructions),
            displayState: 0
        )
        root.itemController.replace(model: model, isInsert: true)
        await root.itemController.save()

        let entity = GeneratorEntity(root: root, model: model)
        await indexIntentEntities([entity])

        if openWhenCreated {
            await navigator.perform(route: KnownRoutes.generators(model.id, nil))
            try await continueInForeground(alwaysConfirm: false)
        }

        return .result(value: entity, dialog: "Created \"\(trimmedName)\".")
    }
}

struct AddGeneratorNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Generator Note"

    static var parameterSummary: some ParameterSummary {
        Summary("Add note to \(\.$target)")
    }

    @Parameter(title: "Generator", requestValueDialog: "Which generator?")
    var target: GeneratorEntity

    @Parameter(title: "Note", requestValueDialog: "What note should be added?")
    var note: AttributedString

    @Dependency var root: GeneratorRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await requireReadyDatabase()
        // `target` can be deleted since Siri or Shortcuts cached it. See CODE_AUDIT_AppIntents §5.2.
        let targetModel = try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: "Which generator?")
        let currentDescription = targetModel.description
        let updatedDescription = appendingIntentText(
            String(note.characters),
            to: currentDescription
        )
        guard updatedDescription != currentDescription else {
            return .result(dialog: "No note added.")
        }

        root.editController.reset(description: updatedDescription, itemId: target.id)
        await root.itemController.save()

        if let model = root.itemController.itemSync(for: target.id) {
            await indexIntentEntities([GeneratorEntity(root: root, model: model)])
        }

        return .result(dialog: "Added note to \"\(target.name)\".")
    }
}

@AppIntent(schema: .system.search)
struct SearchGeneratorsIntent: ShowInAppSearchResultsIntent {
    static let title: LocalizedStringResource = "Search Generators"
    static let searchScopes: [StringSearchScope] = [.general]

    var criteria: StringSearchCriteria

    @Dependency var root: GeneratorRootModel
    @Dependency var navigator: Navigator

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await DatabaseReadiness.wait()
        root.searchModel.searchText = criteria.term
        await navigator.perform(route: KnownRoutes.generators(nil, nil))
        return .result()
    }
}

struct DeleteGeneratorIntent: DeleteIntent {
    static let title: LocalizedStringResource = "Delete Generator"
    /// A trashed item is recoverable, but a locked device should not be able to trash a campaign.
    /// Create, Add and the dice and audio intents stay open for use at the table.
    /// See CODE_AUDIT_AppIntents2 §6.1.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Generators")
    var entities: [GeneratorEntity]

    @Dependency var root: GeneratorRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await requireReadyDatabase()
        let ids = entities.map(\.id)

        await trashIntentItems(ids: ids, ofType: GeneratorEntity.self, in: root)

        let count = entities.count
        return .result(dialog: "Deleted ^[\(count) generator](inflect: true).")
    }
}

#if os(iOS)
extension SearchGeneratorsIntent: TargetContentProvidingIntent {}
#endif

#endif
