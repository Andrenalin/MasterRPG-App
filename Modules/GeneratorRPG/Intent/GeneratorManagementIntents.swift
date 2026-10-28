// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreSpotlight
import CoreRPG
import Foundation

struct CreateGeneratorIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Generator"
    static let description = IntentDescription(
        "Creates a generator with a name and, optionally, a description.",
        categoryName: "Generator",
        searchKeywords: ["prompt", "idea", "new"]
    )
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    static var parameterSummary: some ParameterSummary {
        Summary("Create generator named \(\.$name)")
    }

    @Parameter(title: "Name", requestValueDialog: .localized("What should the generator be called?", bundle: .module))
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
        let trimmedName = try requiredIntentName(name, parameter: $name, prompt: .localized("What should the generator be called?", bundle: .module))
        let model = GeneratorModel(
            id: UUID(),
            name: trimmedName,
            description: intentMarkdown(from: instructions),
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

        return .result(value: entity, dialog: .localized("Created \"\(trimmedName)\".", bundle: .module))
    }
}

struct AddGeneratorNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Generator Note"
    static let description = IntentDescription(
        "Adds a note to the description of a generator.",
        categoryName: "Generator",
        searchKeywords: ["add", "note", "prompt"]
    )

    static var parameterSummary: some ParameterSummary {
        Summary("Add note to \(\.$target)")
    }

    @Parameter(title: "Generator", requestValueDialog: .localized("Which generator?", bundle: .module))
    var target: GeneratorEntity

    @Parameter(title: "Note", requestValueDialog: .localized("What note should be added?", bundle: .module))
    var note: AttributedString

    @Dependency var root: GeneratorRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<GeneratorEntity> & ProvidesDialog {
        try await requireReadyDatabase()
        // `target` can be deleted since Siri or Shortcuts cached it. See CODE_AUDIT_AppIntents §5.2.
        let targetModel = try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which generator?", bundle: .module))
        let currentDescription = targetModel.description
        let updatedDescription = appendingIntentText(
            intentMarkdown(from: note),
            to: currentDescription
        )
        guard updatedDescription != currentDescription else {
            return .result(value: GeneratorEntity(root: root, model: targetModel), dialog: .localized("No note added.", bundle: .module))
        }

        root.editController.reset(description: updatedDescription, itemId: target.id)
        await root.itemController.save()

        // The updated generator is returned so a shortcut can go on with it.
        // See CODE_AUDIT_AppIntents3 §4.14.
        let model = try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which generator?", bundle: .module))
        let updated = GeneratorEntity(root: root, model: model)
        await indexIntentEntities([updated])

        return .result(value: updated, dialog: .localized("Added note to \"\(target.name)\".", bundle: .module))
    }
}

/// Renames a generator, replaces its description or changes its tags. See CODE_AUDIT_AppIntents3 §4.5.
struct UpdateGeneratorIntent: AppIntent {
    static let title: LocalizedStringResource = "Update Generator"
    static let description = IntentDescription(
        "Renames a generator, replaces its description, or adds and removes tags. Fields left empty stay as they are.",
        categoryName: "Generator",
        searchKeywords: ["rename", "edit", "change", "tag"]
    )
    /// A locked device cannot rename an item or replace its description. Value changes and
    /// rolls stay open for play. See CODE_AUDIT_AppIntents3 §6.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    static var parameterSummary: some ParameterSummary {
        Summary("Update \(\.$target)") {
            \.$name
            \.$details
            \.$addTags
            \.$removeTags
        }
    }

    @Parameter(title: "Generator", requestValueDialog: .localized("Which generator?", bundle: .module))
    var target: GeneratorEntity

    @Parameter(title: "New Name")
    var name: String?

    @Parameter(title: "Description", description: "Replaces the description. Formatting is kept.")
    var details: AttributedString?

    @Parameter(title: "Add Tags")
    var addTags: [String]?

    @Parameter(title: "Remove Tags")
    var removeTags: [String]?

    @Dependency var root: GeneratorRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<GeneratorEntity> & ProvidesDialog {
        try await requireReadyDatabase()
        try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which generator?", bundle: .module))
        let changed = await updateIntentItem(id: target.id, name: name, description: details, addTags: addTags, removeTags: removeTags, in: root)
        let model = try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which generator?", bundle: .module))
        let updated = GeneratorEntity(root: root, model: model)
        guard changed else {
            return .result(value: updated, dialog: .localized("Nothing changed in \"\(updated.name)\".", bundle: .module))
        }
        await indexIntentEntities([updated])
        return .result(value: updated, dialog: .localized("Updated \"\(updated.name)\".", bundle: .module))
    }
}

@AppIntent(schema: .system.search)
struct SearchGeneratorsIntent: ShowInAppSearchResultsIntent {
    static let title: LocalizedStringResource = "Search Generators"
    static let description = IntentDescription(
        "Shows the generators that match a search term in the app.",
        categoryName: "Generator",
        searchKeywords: ["find", "prompt"]
    )
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
    static let description = IntentDescription(
        "Moves generators to the trash. They can be restored in the app.",
        categoryName: "Generator",
        searchKeywords: ["remove", "trash", "prompt"]
    )
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
        let message = AttributedString(localized: "Deleted ^[\(count) generator](inflect: true).", bundle: .module)
        return .result(dialog: .verbatim(message))
    }
}

#if os(iOS)
extension SearchGeneratorsIntent: TargetContentProvidingIntent {}
#endif

#endif
