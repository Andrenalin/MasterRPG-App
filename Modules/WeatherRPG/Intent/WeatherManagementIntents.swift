// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreSpotlight
import CoreRPG
import Foundation

struct CreateWeatherIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Weather"
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    static var parameterSummary: some ParameterSummary {
        Summary("Create weather named \(\.$name)")
    }

    @Parameter(title: "Name", requestValueDialog: "What should the weather be called?")
    var name: String

    @Parameter(title: "Description")
    var details: AttributedString?

    @Parameter(title: "Open When Created", default: true)
    var openWhenCreated: Bool

    @Dependency var root: WeatherRootModel
    @Dependency var navigator: Navigator

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<WeatherEntity> & ProvidesDialog {
        await DatabaseReadiness.wait()
        let model = WeatherModel.empty(UUID())
        model.name = name
        model.description = intentPlainText(from: details)

        root.itemController.replace(model: model, isInsert: true)
        await root.itemController.save()

        let entity = WeatherEntity(root: root, model: model)
        try await indexIntentEntities([entity])

        if openWhenCreated {
            await navigator.perform(route: KnownRoutes.weathers(model.id, nil))
            try await continueInForeground(alwaysConfirm: false)
        }

        return .result(value: entity, dialog: "Created \"\(name)\".")
    }
}

struct AddWeatherNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Weather Note"

    static var parameterSummary: some ParameterSummary {
        Summary("Add note to \(\.$target)")
    }

    @Parameter(title: "Weather", requestValueDialog: "Which weather?")
    var target: WeatherEntity

    @Parameter(title: "Note", requestValueDialog: "What note should be added?")
    var note: AttributedString

    @Dependency var root: WeatherRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await DatabaseReadiness.wait()
        let currentDescription = root.itemController.itemSync(for: target.id)?.description ?? ""
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
            try await indexIntentEntities([WeatherEntity(root: root, model: model)])
        }

        return .result(dialog: "Added note to \"\(target.name)\".")
    }
}

@AppIntent(schema: .system.search)
struct SearchWeatherIntent: ShowInAppSearchResultsIntent {
    static let title: LocalizedStringResource = "Search Weather"
    static let searchScopes: [StringSearchScope] = [.general]

    var criteria: StringSearchCriteria

    @Dependency var root: WeatherRootModel
    @Dependency var navigator: Navigator

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await DatabaseReadiness.wait()
        root.searchModel.searchText = criteria.term
        await navigator.perform(route: KnownRoutes.weathers(nil, nil))
        return .result()
    }
}

struct DeleteWeatherIntent: DeleteIntent {
    static let title: LocalizedStringResource = "Delete Weather"

    @Parameter(title: "Weather")
    var entities: [WeatherEntity]

    @Dependency var root: WeatherRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await DatabaseReadiness.wait()
        let ids = entities.map(\.id)

        for id in ids {
            await root.editController.markForDeletion(itemId: id)
        }
        await root.itemController.save()

        try await deleteIntentEntities(ids: ids, ofType: WeatherEntity.self)

        let count = entities.count
        let message = AttributedString(
            localized: "Deleted ^[\(count) weather item](inflect: true).",
            bundle: .module
        )
        return .result(dialog: "\(message)")
    }
}

#if os(iOS)
extension SearchWeatherIntent: TargetContentProvidingIntent {}
#endif

private func intentPlainText(from text: AttributedString?) -> String {
    text.map { String($0.characters) } ?? ""
}

private func appendingIntentText(_ addition: String, to original: String) -> String {
    let trimmedAddition = addition.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedAddition.isEmpty else { return original }

    let trimmedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedOriginal.isEmpty else { return trimmedAddition }

    return "\(trimmedOriginal)\n\n\(trimmedAddition)"
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
