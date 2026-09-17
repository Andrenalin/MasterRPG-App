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

    @Parameter(title: "Open When Created", default: true)
    var openWhenCreated: Bool

    @Dependency var root: CharacterRootModel
    @Dependency var navigator: Navigator

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<CharacterEntity> & ProvidesDialog {
        // Siri/Shortcuts can pass an empty or all-whitespace string; re-prompt
        // rather than silently creating a blank, unusable character.
        // See CODE_AUDIT_Character §5.6.
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw $name.needsValueError("What should the character be called?")
        }

        let model = ValueModel(
            id: UUID(),
            name: trimmedName,
            description: intentPlainText(from: details)
        )
        root.itemController.replace(model: model, isInsert: true)
        await root.itemController.save()

        let entity = CharacterEntity(root: root, model: model)
        try await indexIntentEntities([entity])

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
        // Siri/Shortcuts can pass an empty or all-whitespace string; re-prompt
        // rather than silently adding a blank, unusable entry.
        // See CODE_AUDIT_Character §5.6.
        let trimmedEntryName = entryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEntryName.isEmpty else {
            throw $entryName.needsValueError("What should the entry be called?")
        }

        // `target` may be stale — deleted since Siri/Shortcuts last cached it.
        // Confirm it still resolves before reporting success, rather than
        // silently no-opping while still returning a success dialog.
        guard let model = root.itemController.itemSync(for: target.id) else {
            throw $target.needsValueError("Which character?")
        }

        let entry = root.editController.create(
            name: trimmedEntryName,
            content: intentPlainText(from: content)
        )
        root.editController.add(entry: entry, itemId: target.id)
        await root.itemController.save()

        try await indexIntentEntities([CharacterEntity(root: root, model: model)])

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
        root.searchModel.searchText = criteria.term
        await navigator.perform(route: KnownRoutes.values(nil, nil))
        return .result()
    }
}

struct DeleteCharacterIntent: DeleteIntent {
    static let title: LocalizedStringResource = "Delete Character"

    @Parameter(title: "Characters")
    var entities: [CharacterEntity]

    @Dependency var root: CharacterRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ids = entities.map(\.id)

        for id in ids {
            await root.editController.delete(itemId: id)
        }
        await root.itemController.save()

        try await deleteIntentEntities(ids: ids, ofType: CharacterEntity.self)

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

private func intentPlainText(from text: AttributedString?) -> String {
    text.map { String($0.characters) } ?? ""
}

private func indexIntentEntities<Entity: IndexedEntity>(_ entities: [Entity]) async throws {
    guard CSSearchableIndex.isIndexingAvailable() else { return }
    try await CSSearchableIndex.default().indexAppEntities(entities)
}

private func deleteIntentEntities<Entity: IndexedEntity>(
    ids: [UUID],
    ofType entityType: Entity.Type
) async throws where Entity.ID == UUID {
    guard CSSearchableIndex.isIndexingAvailable() else { return }

#if compiler(>=6.4)
    if #available(iOS 27, macOS 27, visionOS 27, *) {
        try await CSSearchableIndex.default().deleteAppEntities(
            identifiedBy: ids,
            ofType: entityType
        )
    } else {
        try await CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: ids.map(\.uuidString))
    }
#else
    try await CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: ids.map(\.uuidString))
#endif
}

#endif
