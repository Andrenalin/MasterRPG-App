// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreSpotlight
import CoreRPG
import Foundation

struct CreateMapIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Map"
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    static var parameterSummary: some ParameterSummary {
        Summary("Create map named \(\.$name)")
    }

    @Parameter(title: "Name", requestValueDialog: "What should the map be called?")
    var name: String

    @Parameter(title: "Description")
    var details: AttributedString?

    @Parameter(title: "Open When Created", default: true)
    var openWhenCreated: Bool

    @Dependency var root: MapRootModel
    @Dependency var navigator: Navigator

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<MapEntity> & ProvidesDialog {
        await DatabaseReadiness.wait()
        // Siri and Shortcuts can pass an empty name: ask again instead of creating a blank item.
        // See CODE_AUDIT_AppIntents §5.2.
        let trimmedName = try requiredIntentName(name, parameter: $name, prompt: "What should the map be called?")
        let model = MapModel(
            id: UUID(),
            name: trimmedName,
            description: intentPlainText(from: details)
        )
        root.itemController.replace(model: model, isInsert: true)
        await root.itemController.save()

        let entity = MapEntity(root: root, model: model)
        try await indexIntentEntities([entity])

        if openWhenCreated {
            await navigator.perform(route: KnownRoutes.maps(model.id, nil))
            try await continueInForeground(alwaysConfirm: false)
        }

        return .result(value: entity, dialog: "Created \"\(trimmedName)\".")
    }
}

struct AddMapRoomIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Map Room"

    static var parameterSummary: some ParameterSummary {
        Summary("Add room \(\.$roomName) to \(\.$target)")
    }

    @Parameter(title: "Map", requestValueDialog: "Which map?")
    var target: MapEntity

    @Parameter(title: "Room Name", requestValueDialog: "What should the room be called?")
    var roomName: String

    @Parameter(title: "Content")
    var content: AttributedString?

    @Dependency var root: MapRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await DatabaseReadiness.wait()
        // Siri and Shortcuts can pass an empty name, and `target` can be deleted since it was cached:
        // ask again instead of adding a blank entry or reporting a success that changed nothing.
        // See CODE_AUDIT_AppIntents §5.2.
        let trimmedRoomName = try requiredIntentName(roomName, parameter: $roomName, prompt: "What should the room be called?")
        try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: "Which map?")
        let entry = root.editController.create(
            name: trimmedRoomName,
            content: intentPlainText(from: content)
        )
        root.editController.add(entry: entry, itemId: target.id)
        await root.itemController.save()

        if let model = root.itemController.itemSync(for: target.id) {
            try await indexIntentEntities([MapEntity(root: root, model: model)])
        }

        return .result(dialog: "Added \"\(trimmedRoomName)\" to \"\(target.name)\".")
    }
}

@AppIntent(schema: .system.search)
struct SearchMapsIntent: ShowInAppSearchResultsIntent {
    static let title: LocalizedStringResource = "Search Maps"
    static let searchScopes: [StringSearchScope] = [.general]

    var criteria: StringSearchCriteria

    @Dependency var root: MapRootModel
    @Dependency var navigator: Navigator

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await DatabaseReadiness.wait()
        root.searchModel.searchText = criteria.term
        await navigator.perform(route: KnownRoutes.maps(nil, nil))
        return .result()
    }
}

struct DeleteMapIntent: DeleteIntent {
    static let title: LocalizedStringResource = "Delete Map"

    @Parameter(title: "Maps")
    var entities: [MapEntity]

    @Dependency var root: MapRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await DatabaseReadiness.wait()
        let ids = entities.map(\.id)

        for id in ids {
            root.editController.markForDeletion(itemId: id)
        }
        await root.itemController.save()

        try await deleteIntentEntities(ids: ids, ofType: MapEntity.self)

        let count = entities.count
        let message = AttributedString(
            localized: "Deleted ^[\(count) map](inflect: true).",
            bundle: .module
        )
        return .result(dialog: "\(message)")
    }
}

#if os(iOS)
extension SearchMapsIntent: TargetContentProvidingIntent {}
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

    if #available(iOS 27, macOS 27, visionOS 27, *) {
        try await CSSearchableIndex.default().deleteAppEntities(
            identifiedBy: ids,
            ofType: entityType
        )
    } else {
        try await CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: ids.map(\.uuidString))
    }
}

#endif
