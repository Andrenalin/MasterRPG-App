// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreSpotlight
import CoreRPG
import Foundation

struct CreatePhotoIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Photo"
    static let description = IntentDescription(
        "Creates a photo with a name and, optionally, a description.",
        categoryName: "Photo",
        searchKeywords: ["image", "picture", "handout", "new"]
    )
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    static var parameterSummary: some ParameterSummary {
        Summary("Create photo named \(\.$name)")
    }

    @Parameter(title: "Name", requestValueDialog: .localized("What should the photo be called?", bundle: .module))
    var name: String

    @Parameter(title: "Description")
    var details: AttributedString?

    @Parameter(title: "File")
    var file: IntentFile?

    @Parameter(title: "Open When Created", default: false)
    var openWhenCreated: Bool

    @Dependency var root: PhotoRootModel
    @Dependency var navigator: Navigator

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<PhotoEntity> & ProvidesDialog {
        try await requireReadyDatabase()
        // Siri and Shortcuts can pass an empty name: ask again instead of creating a blank item.
        // See CODE_AUDIT_AppIntents §5.2.
        let trimmedName = try requiredIntentName(name, parameter: $name, prompt: .localized("What should the photo be called?", bundle: .module))
        let fileData = try await intentFileData(file, allowedTypes: root.config.fileTypes)
        let model = PhotoModel(
            id: UUID(),
            name: trimmedName,
            description: intentMarkdown(from: details)
        )
        // Saved to the library also during a game. See CODE_AUDIT_Since_3.0.1 §5.2.
        root.itemController.replace(model: model, isInsert: true, forceSave: true)
        try await root.itemController.saveForIntent()

        if let fileData {
            try await attachIntentFile(to: model.id, editControllable: root.editController) {
                try await root.editController.resetPhoto(data: fileData, itemId: model.id, forceSave: true)
            }
        }

        let entity = PhotoEntity(root: root, model: model)
        await indexIntentEntities([entity])

        if openWhenCreated {
            await navigator.perform(route: KnownRoutes.photos(model.id, nil))
            try await continueInForeground(alwaysConfirm: false)
        }

        return .result(value: entity, dialog: .localized("Created \"\(trimmedName)\".", bundle: .module))
    }
}

struct AddPhotoNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Photo Note"
    static let description = IntentDescription(
        "Adds a note to the description of a photo.",
        categoryName: "Photo",
        searchKeywords: ["add", "note", "image"]
    )

    static var parameterSummary: some ParameterSummary {
        Summary("Add note to \(\.$target)")
    }

    @Parameter(title: "Photo", requestValueDialog: .localized("Which photo?", bundle: .module))
    var target: PhotoEntity

    @Parameter(title: "Note", requestValueDialog: .localized("What note should be added?", bundle: .module))
    var note: AttributedString

    @Dependency var root: PhotoRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<PhotoEntity> & ProvidesDialog {
        try await requireReadyDatabase()
        // `target` can be deleted since Siri or Shortcuts cached it. See CODE_AUDIT_AppIntents §5.2.
        let targetModel = try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which photo?", bundle: .module))
        let currentDescription = targetModel.description
        let updatedDescription = appendingIntentText(
            intentMarkdown(from: note),
            to: currentDescription
        )
        guard updatedDescription != currentDescription else {
            return .result(value: PhotoEntity(root: root, model: targetModel), dialog: .localized("No note added.", bundle: .module))
        }

        try requireOutsideGame([target.id], in: root)

        root.editController.reset(description: updatedDescription, itemId: target.id, forceSave: true)
        try await root.itemController.saveForIntent()

        // The updated photo is returned so a shortcut can go on with it.
        // See CODE_AUDIT_AppIntents3 §4.14.
        let model = try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which photo?", bundle: .module))
        let updated = PhotoEntity(root: root, model: model)
        await indexIntentEntities([updated])

        return .result(value: updated, dialog: .localized("Added note to \"\(target.name)\".", bundle: .module))
    }
}

/// Renames a photo, replaces its description or changes its tags. See CODE_AUDIT_AppIntents3 §4.5.
struct UpdatePhotoIntent: AppIntent {
    static let title: LocalizedStringResource = "Update Photo"
    static let description = IntentDescription(
        "Renames a photo, replaces its description, or adds and removes tags. Fields left empty stay as they are.",
        categoryName: "Photo",
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

    @Parameter(title: "Photo", requestValueDialog: .localized("Which photo?", bundle: .module))
    var target: PhotoEntity

    @Parameter(title: "New Name")
    var name: String?

    @Parameter(title: "Description", description: "Replaces the description. Formatting is kept.")
    var details: AttributedString?

    @Parameter(title: "Add Tags")
    var addTags: [String]?

    @Parameter(title: "Remove Tags")
    var removeTags: [String]?

    @Dependency var root: PhotoRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<PhotoEntity> & ProvidesDialog {
        try await requireReadyDatabase()
        try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which photo?", bundle: .module))
        let changed = try await updateIntentItem(id: target.id, name: name, description: details, addTags: addTags, removeTags: removeTags, in: root)
        let model = try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which photo?", bundle: .module))
        let updated = PhotoEntity(root: root, model: model)
        guard changed else {
            return .result(value: updated, dialog: .localized("Nothing changed in \"\(updated.name)\".", bundle: .module))
        }
        await indexIntentEntities([updated])
        return .result(value: updated, dialog: .localized("Updated \"\(updated.name)\".", bundle: .module))
    }
}

@AppIntent(schema: .system.search)
struct SearchPhotosIntent: ShowInAppSearchResultsIntent {
    static let title: LocalizedStringResource = "Search Photos"
    static let description = IntentDescription(
        "Shows the photos that match a search term in the app.",
        categoryName: "Photo",
        searchKeywords: ["find", "image"]
    )
    static let searchScopes: [StringSearchScope] = [.general]

    var criteria: StringSearchCriteria

    @Dependency var root: PhotoRootModel
    @Dependency var navigator: Navigator

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await DatabaseReadiness.wait()
        root.searchModel.searchText = criteria.term
        await navigator.perform(route: KnownRoutes.photos(nil, nil))
        return .result()
    }
}

struct DeletePhotoIntent: DeleteIntent {
    static let title: LocalizedStringResource = "Delete Photo"
    static let description = IntentDescription(
        "Moves photos to the trash. They can be restored in the app.",
        categoryName: "Photo",
        searchKeywords: ["remove", "trash", "image"]
    )
    /// A trashed item is recoverable, but a locked device should not be able to trash a campaign.
    /// Create, Add and the dice and audio intents stay open for use at the table.
    /// See CODE_AUDIT_AppIntents2 §6.1.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Photos")
    var entities: [PhotoEntity]

    @Dependency var root: PhotoRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await requireReadyDatabase()
        let ids = entities.map(\.id)

        try await trashIntentItems(ids: ids, ofType: PhotoEntity.self, in: root)

        let count = entities.count
        let message = AttributedString(
            localized: "Deleted ^[\(count) photo](inflect: true).",
            bundle: .module
        )
        return .result(dialog: .verbatim(message))
    }
}

#if os(iOS)
extension SearchPhotosIntent: TargetContentProvidingIntent {}
#endif

#endif
