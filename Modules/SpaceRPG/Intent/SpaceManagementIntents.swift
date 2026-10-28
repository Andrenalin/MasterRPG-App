// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreRPG
import Foundation

struct CreateSpaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Create 3D Object"
    static let description = IntentDescription(
        "Creates a 3D object with a name and, optionally, a description.",
        categoryName: "3D Object",
        searchKeywords: ["model", "miniature", "new"]
    )
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    static var parameterSummary: some ParameterSummary {
        Summary("Create 3D object named \(\.$name)")
    }

    @Parameter(title: "Name", requestValueDialog: .localized("What should the 3D object be called?", bundle: .module))
    var name: String

    @Parameter(title: "Description")
    var details: AttributedString?

    @Parameter(title: "File")
    var file: IntentFile?

    @Parameter(title: "Open When Created", default: false)
    var openWhenCreated: Bool

    @Dependency var root: SpaceRootModel
    @Dependency var navigator: Navigator

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<SpaceEntity> & ProvidesDialog {
        try await requireReadyDatabase()
        // Siri and Shortcuts can pass an empty name: ask again instead of creating a blank item.
        // See CODE_AUDIT_AppIntents §5.2.
        let trimmedName = try requiredIntentName(name, parameter: $name, prompt: .localized("What should the 3D object be called?", bundle: .module))
        let fileData = try await intentFileData(file, allowedTypes: root.config.fileTypes)
        let model = SpaceModel(
            id: UUID(),
            name: trimmedName,
            description: intentMarkdown(from: details),
            displayState: 0
        )
        // Saved to the library also during a game. See CODE_AUDIT_Since_3.0.1 §5.2.
        root.itemController.replace(model: model, isInsert: true, forceSave: true)
        try await root.itemController.saveForIntent()

        if let fileData {
            try await attachIntentFile(to: model.id, editControllable: root.editController) {
                try await root.editController.resetFile(data: fileData, itemId: model.id, path: "", forceSave: true)
                return true
            }
        }

        let entity = SpaceEntity(root: root, model: model)
        // A Spotlight-indexing hiccup shouldn't override an already-committed data mutation
        // as a failed intent — see CODE_AUDIT_Space §5.5.
        await indexIntentEntities([entity])

        if openWhenCreated {
            await navigator.perform(route: KnownRoutes.spaces(model.id, nil))
            try await continueInForeground(alwaysConfirm: false)
        }

        return .result(value: entity, dialog: .localized("Created \"\(trimmedName)\".", bundle: .module))
    }
}

struct AddSpaceNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Add 3D Object Note"
    static let description = IntentDescription(
        "Adds a note to the description of a 3D object.",
        categoryName: "3D Object",
        searchKeywords: ["add", "note", "model"]
    )

    static var parameterSummary: some ParameterSummary {
        Summary("Add note to \(\.$target)")
    }

    @Parameter(title: "3D Object", requestValueDialog: .localized("Which 3D object?", bundle: .module))
    var target: SpaceEntity

    @Parameter(title: "Note", requestValueDialog: .localized("What note should be added?", bundle: .module))
    var note: AttributedString

    @Dependency var root: SpaceRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<SpaceEntity> & ProvidesDialog {
        try await requireReadyDatabase()
        // `target` can be deleted since Siri or Shortcuts cached it. See CODE_AUDIT_AppIntents §5.2.
        let targetModel = try requiredIntentModel($target, prompt: SpaceIntentSupport.targetPrompt, in: root)
        let currentDescription = targetModel.description
        let updatedDescription = appendingIntentText(
            intentMarkdown(from: note),
            to: currentDescription
        )
        guard updatedDescription != currentDescription else {
            return .result(value: SpaceEntity(root: root, model: targetModel), dialog: .localized("No note added.", bundle: .module))
        }

        try requireOutsideGame([target.id], in: root)

        root.editController.reset(description: updatedDescription, itemId: target.id, forceSave: true)
        try await root.itemController.saveForIntent()

        // The updated 3D object is returned so a shortcut can go on with it. Indexing it is
        // CODE_AUDIT_Space §5.5. See CODE_AUDIT_AppIntents3 §4.14.
        let updated = try await reindexedIntentTarget($target, prompt: SpaceIntentSupport.targetPrompt, in: root)

        return .result(value: updated, dialog: .localized("Added note to \"\(target.name)\".", bundle: .module))
    }
}

/// Renames a 3D object, replaces its description or changes its tags. See CODE_AUDIT_AppIntents3 §4.5.
struct UpdateSpaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Update 3D Object"
    static let description = IntentDescription(
        "Renames a 3D object, replaces its description, or adds and removes tags. Fields left empty stay as they are.",
        categoryName: "3D Object",
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

    @Parameter(title: "3D Object", requestValueDialog: .localized("Which 3D object?", bundle: .module))
    var target: SpaceEntity

    @Parameter(title: "New Name")
    var name: String?

    @Parameter(title: "Description", description: "Replaces the description. Formatting is kept.")
    var details: AttributedString?

    @Parameter(title: "Add Tags")
    var addTags: [String]?

    @Parameter(title: "Remove Tags")
    var removeTags: [String]?

    @Dependency var root: SpaceRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<SpaceEntity> & ProvidesDialog {
        try await requireReadyDatabase()
        let (updated, changed) = try await updateIntentTarget($target, prompt: SpaceIntentSupport.targetPrompt, name: name, description: details, addTags: addTags, removeTags: removeTags, in: root)
        guard changed else {
            return .result(value: updated, dialog: .localized("Nothing changed in \"\(updated.name)\".", bundle: .module))
        }
        return .result(value: updated, dialog: .localized("Updated \"\(updated.name)\".", bundle: .module))
    }
}

@AppIntent(schema: .system.search)
struct SearchSpacesIntent: ShowInAppSearchResultsIntent {
    static let title: LocalizedStringResource = "Search 3D Objects"
    static let description = IntentDescription(
        "Shows the 3D objects that match a search term in the app.",
        categoryName: "3D Object",
        searchKeywords: ["find", "model"]
    )
    static let searchScopes: [StringSearchScope] = [.general]

    var criteria: StringSearchCriteria

    @Dependency var root: SpaceRootModel
    @Dependency var navigator: Navigator

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await DatabaseReadiness.wait()
        root.searchModel.searchText = criteria.term
        await navigator.perform(route: KnownRoutes.spaces(nil, nil))
        return .result()
    }
}

struct DeleteSpaceIntent: DeleteIntent {
    static let title: LocalizedStringResource = "Delete 3D Object"
    static let description = IntentDescription(
        "Moves 3D objects to the trash. They can be restored in the app.",
        categoryName: "3D Object",
        searchKeywords: ["remove", "trash", "model"]
    )
    /// A trashed item is recoverable, but a locked device should not be able to trash a campaign.
    /// Create, Add and the dice and audio intents stay open for use at the table.
    /// See CODE_AUDIT_AppIntents2 §6.1.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "3D Objects")
    var entities: [SpaceEntity]

    @Dependency var root: SpaceRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await requireReadyDatabase()
        let ids = entities.map(\.id)

        try await trashIntentItems(ids: ids, ofType: SpaceEntity.self, in: root)

        let count = entities.count
        let message = AttributedString(
            localized: "Deleted ^[\(count) 3D object](inflect: true).",
            bundle: .module
        )
        return .result(dialog: .verbatim(message))
    }
}

#if os(iOS)
extension SearchSpacesIntent: TargetContentProvidingIntent {}
#endif

#endif
