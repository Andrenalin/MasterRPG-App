// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreSpotlight
import CoreRPG
import Foundation

struct CreateCharacterIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Character"
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    static var parameterSummary: some ParameterSummary {
        Summary("Create character named \(\.$name)")
    }

    @Parameter(title: "Name", requestValueDialog: "What should the character be called?")
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
        let trimmedName = try requiredIntentName(name, parameter: $name, prompt: "What should the character be called?")

        let model = ValueModel(
            id: UUID(),
            name: trimmedName,
            description: intentPlainText(from: details)
        )
        root.itemController.replace(model: model, isInsert: true)
        await root.itemController.save()

        let entity = CharacterEntity(root: root, model: model)
        await indexIntentEntities([entity])

        if openWhenCreated {
            await navigator.perform(route: KnownRoutes.values(model.id, nil))
            try await continueInForeground(alwaysConfirm: false)
        }

        return .result(value: entity, dialog: "Created \"\(trimmedName)\".")
    }
}

struct AddCharacterEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Character Entry"

    static var parameterSummary: some ParameterSummary {
        Summary("Add entry \(\.$entryName) to \(\.$target)")
    }

    @Parameter(title: "Character", requestValueDialog: "Which character?")
    var target: CharacterEntity

    @Parameter(title: "Entry Name", requestValueDialog: "What should the entry be called?")
    var entryName: String

    @Parameter(title: "Content")
    var content: AttributedString?

    @Dependency var root: CharacterRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await requireReadyDatabase()
        // Siri/Shortcuts can pass an empty or all-whitespace string; re-prompt
        // rather than silently adding a blank, unusable entry.
        // See CODE_AUDIT_Character §5.6.
        let trimmedEntryName = try requiredIntentName(entryName, parameter: $entryName, prompt: "What should the entry be called?")

        // `target` may be stale — deleted since Siri/Shortcuts last cached it.
        // Confirm it still resolves before reporting success, rather than
        // silently no-opping while still returning a success dialog.
        let model = try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: "Which character?")

        let entry = root.editController.create(
            name: trimmedEntryName,
            content: intentPlainText(from: content)
        )
        root.editController.add(entry: entry, itemId: target.id)
        await root.itemController.save()

        await indexIntentEntities([CharacterEntity(root: root, model: model)])

        return .result(dialog: "Added \"\(trimmedEntryName)\" to \"\(target.name)\".")
    }
}

@AppIntent(schema: .system.search)
struct SearchCharactersIntent: ShowInAppSearchResultsIntent {
    static let title: LocalizedStringResource = "Search Characters"
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

        await trashIntentItems(ids: ids, ofType: CharacterEntity.self, in: root)

        let count = entities.count
        let message = AttributedString(
            localized: "Deleted ^[\(count) character](inflect: true).",
            bundle: .module
        )
        return .result(dialog: "\(message)")
    }
}

#if os(iOS)
extension SearchCharactersIntent: TargetContentProvidingIntent {}
#endif

#endif
