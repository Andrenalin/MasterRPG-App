// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreSpotlight
import CoreRPG
import Foundation

struct CreateCharacterIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Character"
    static let description = IntentDescription(
        "Creates a character with a name and, optionally, a description.",
        categoryName: "Character",
        searchKeywords: ["player", "NPC", "monster", "new"]
    )
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    static var parameterSummary: some ParameterSummary {
        Summary("Create character named \(\.$name)")
    }

    @Parameter(title: "Name", requestValueDialog: .localized("What should the character be called?", bundle: .module))
    var name: String

    @Parameter(title: "Description")
    var details: AttributedString?

    @Parameter(title: "Open When Created", default: false)
    var openWhenCreated: Bool

    @Dependency var root: CharacterRootModel
    @Dependency var navigator: Navigator

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<CharacterEntity> & ProvidesDialog {
        try await requireReadyDatabase()
        // Siri/Shortcuts can pass an empty or all-whitespace string; re-prompt
        // rather than silently creating a blank, unusable character.
        // See CODE_AUDIT_Character §5.6.
        let trimmedName = try requiredIntentName(name, parameter: $name, prompt: .localized("What should the character be called?", bundle: .module))

        let model = ValueModel(
            id: UUID(),
            name: trimmedName,
            description: intentMarkdown(from: details)
        )
        // Saved to the library also during a game. See CODE_AUDIT_Since_3.0.1 §5.2.
        root.itemController.replace(model: model, isInsert: true, forceSave: true)
        await root.itemController.save()

        let entity = CharacterEntity(root: root, model: model)
        await indexIntentEntities([entity])

        if openWhenCreated {
            await navigator.perform(route: KnownRoutes.values(model.id, nil))
            try await continueInForeground(alwaysConfirm: false)
        }

        return .result(value: entity, dialog: .localized("Created \"\(trimmedName)\".", bundle: .module))
    }
}

struct AddCharacterEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Character Entry"
    static let description = IntentDescription(
        "Adds an entry with a name and text to a character sheet.",
        categoryName: "Character",
        searchKeywords: ["add", "note", "player"]
    )

    static var parameterSummary: some ParameterSummary {
        Summary("Add entry \(\.$entryName) to \(\.$target)")
    }

    @Parameter(title: "Character", requestValueDialog: .localized("Which character?", bundle: .module))
    var target: CharacterEntity

    @Parameter(title: "Entry Name", requestValueDialog: .localized("What should the entry be called?", bundle: .module))
    var entryName: String

    @Parameter(title: "Content")
    var content: AttributedString?

    @Dependency var root: CharacterRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<CharacterEntity> & ProvidesDialog {
        try await requireReadyDatabase()
        // Siri/Shortcuts can pass an empty or all-whitespace string; re-prompt
        // rather than silently adding a blank, unusable entry.
        // See CODE_AUDIT_Character §5.6.
        let trimmedEntryName = try requiredIntentName(entryName, parameter: $entryName, prompt: .localized("What should the entry be called?", bundle: .module))

        // `target` may be stale — deleted since Siri/Shortcuts last cached it.
        // Confirm it still resolves before reporting success, rather than
        // silently no-opping while still returning a success dialog.
        try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which character?", bundle: .module))

        let entry = root.editController.create(
            name: trimmedEntryName,
            content: intentMarkdown(from: content)
        )
        try requireOutsideGame([target.id], in: root)
        root.editController.add(entry: entry, itemId: target.id, forceSave: true)
        await root.itemController.save()

        // The updated character is returned so a shortcut can go on with it.
        // See CODE_AUDIT_AppIntents3 §4.14.
        let model = try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which character?", bundle: .module))
        let updated = CharacterEntity(root: root, model: model)
        await indexIntentEntities([updated])

        return .result(value: updated, dialog: .localized("Added \"\(trimmedEntryName)\" to \"\(target.name)\".", bundle: .module))
    }
}

/// Renames a character, replaces its description or changes its tags. See CODE_AUDIT_AppIntents3 §4.5.
struct UpdateCharacterIntent: AppIntent {
    static let title: LocalizedStringResource = "Update Character"
    static let description = IntentDescription(
        "Renames a character, replaces its description, or adds and removes tags. Fields left empty stay as they are.",
        categoryName: "Character",
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

    @Parameter(title: "Character", requestValueDialog: .localized("Which character?", bundle: .module))
    var target: CharacterEntity

    @Parameter(title: "New Name")
    var name: String?

    @Parameter(title: "Description", description: "Replaces the description. Formatting is kept.")
    var details: AttributedString?

    @Parameter(title: "Add Tags")
    var addTags: [String]?

    @Parameter(title: "Remove Tags")
    var removeTags: [String]?

    @Dependency var root: CharacterRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<CharacterEntity> & ProvidesDialog {
        try await requireReadyDatabase()
        try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which character?", bundle: .module))
        let changed = try await updateIntentItem(id: target.id, name: name, description: details, addTags: addTags, removeTags: removeTags, in: root)
        let model = try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which character?", bundle: .module))
        let updated = CharacterEntity(root: root, model: model)
        guard changed else {
            return .result(value: updated, dialog: .localized("Nothing changed in \"\(updated.name)\".", bundle: .module))
        }
        await indexIntentEntities([updated])
        return .result(value: updated, dialog: .localized("Updated \"\(updated.name)\".", bundle: .module))
    }
}

@AppIntent(schema: .system.search)
struct SearchCharactersIntent: ShowInAppSearchResultsIntent {
    static let title: LocalizedStringResource = "Search Characters"
    static let description = IntentDescription(
        "Shows the characters that match a search term in the app.",
        categoryName: "Character",
        searchKeywords: ["find", "player"]
    )
    static let searchScopes: [StringSearchScope] = [.general]

    var criteria: StringSearchCriteria

    @Dependency var root: CharacterRootModel
    @Dependency var navigator: Navigator

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await DatabaseReadiness.wait()
        root.searchModel.searchText = criteria.term
        await navigator.perform(route: KnownRoutes.values(nil, nil))
        return .result()
    }
}

struct DeleteCharacterIntent: DeleteIntent {
    static let title: LocalizedStringResource = "Delete Character"
    static let description = IntentDescription(
        "Moves characters to the trash. They can be restored in the app.",
        categoryName: "Character",
        searchKeywords: ["remove", "trash", "player"]
    )
    /// A trashed item is recoverable, but a locked device should not be able to trash a campaign.
    /// Create, Add and the dice and audio intents stay open for use at the table.
    /// See CODE_AUDIT_AppIntents2 §6.1.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Characters")
    var entities: [CharacterEntity]

    @Dependency var root: CharacterRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await requireReadyDatabase()
        let ids = entities.map(\.id)

        try await trashIntentItems(ids: ids, ofType: CharacterEntity.self, in: root)

        let count = entities.count
        let message = AttributedString(
            localized: "Deleted ^[\(count) character](inflect: true).",
            bundle: .module
        )
        return .result(dialog: .verbatim(message))
    }
}

#if os(iOS)
extension SearchCharactersIntent: TargetContentProvidingIntent {}
#endif

#endif
