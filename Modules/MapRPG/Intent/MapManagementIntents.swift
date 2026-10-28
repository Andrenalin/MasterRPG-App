// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreSpotlight
import CoreRPG
import Foundation

struct CreateMapIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Map"
    static let description = IntentDescription(
        "Creates a map with a name and, optionally, a description.",
        categoryName: "Map",
        searchKeywords: ["dungeon", "room", "location", "new"]
    )
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    static var parameterSummary: some ParameterSummary {
        Summary("Create map named \(\.$name)")
    }

    @Parameter(title: "Name", requestValueDialog: .localized("What should the map be called?", bundle: .module))
    var name: String

    @Parameter(title: "Description")
    var details: AttributedString?

    @Parameter(title: "Open When Created", default: false)
    var openWhenCreated: Bool

    @Dependency var root: MapRootModel
    @Dependency var navigator: Navigator

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<MapEntity> & ProvidesDialog {
        try await requireReadyDatabase()
        // Siri and Shortcuts can pass an empty name: ask again instead of creating a blank item.
        // See CODE_AUDIT_AppIntents §5.2.
        let trimmedName = try requiredIntentName(name, parameter: $name, prompt: .localized("What should the map be called?", bundle: .module))
        let model = MapModel(
            id: UUID(),
            name: trimmedName,
            description: intentMarkdown(from: details)
        )
        // Saved to the library also during a game. See CODE_AUDIT_Since_3.0.1 §5.2.
        root.itemController.replace(model: model, isInsert: true, forceSave: true)
        try await root.itemController.saveForIntent()

        let entity = MapEntity(root: root, model: model)
        await indexIntentEntities([entity])

        if openWhenCreated {
            await navigator.perform(route: KnownRoutes.maps(model.id, nil))
            try await continueInForeground(alwaysConfirm: false)
        }

        return .result(value: entity, dialog: .localized("Created \"\(trimmedName)\".", bundle: .module))
    }
}

struct AddMapRoomIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Map Room"
    static let description = IntentDescription(
        "Adds a room with a name and text to a map.",
        categoryName: "Map",
        searchKeywords: ["add", "note", "dungeon"]
    )

    static var parameterSummary: some ParameterSummary {
        Summary("Add room \(\.$roomName) to \(\.$target)")
    }

    @Parameter(title: "Map", requestValueDialog: .localized("Which map?", bundle: .module))
    var target: MapEntity

    @Parameter(title: "Room Name", requestValueDialog: .localized("What should the room be called?", bundle: .module))
    var roomName: String

    @Parameter(title: "Content")
    var content: AttributedString?

    @Dependency var root: MapRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<MapEntity> & ProvidesDialog {
        try await requireReadyDatabase()
        // Siri and Shortcuts can pass an empty name, and `target` can be deleted since it was cached:
        // ask again instead of adding a blank entry or reporting a success that changed nothing.
        // See CODE_AUDIT_AppIntents §5.2.
        let trimmedRoomName = try requiredIntentName(roomName, parameter: $roomName, prompt: .localized("What should the room be called?", bundle: .module))
        try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which map?", bundle: .module))
        let entry = root.editController.create(
            name: trimmedRoomName,
            content: intentMarkdown(from: content)
        )
        try requireOutsideGame([target.id], in: root)
        root.editController.add(entry: entry, itemId: target.id, forceSave: true)
        try await root.itemController.saveForIntent()

        // The updated map is returned so a shortcut can go on with it.
        // See CODE_AUDIT_AppIntents3 §4.14.
        let model = try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which map?", bundle: .module))
        let updated = MapEntity(root: root, model: model)
        await indexIntentEntities([updated])

        return .result(value: updated, dialog: .localized("Added \"\(trimmedRoomName)\" to \"\(target.name)\".", bundle: .module))
    }
}

/// Renames a map, replaces its description or changes its tags. See CODE_AUDIT_AppIntents3 §4.5.
struct UpdateMapIntent: AppIntent {
    static let title: LocalizedStringResource = "Update Map"
    static let description = IntentDescription(
        "Renames a map, replaces its description, or adds and removes tags. Fields left empty stay as they are.",
        categoryName: "Map",
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

    @Parameter(title: "Map", requestValueDialog: .localized("Which map?", bundle: .module))
    var target: MapEntity

    @Parameter(title: "New Name")
    var name: String?

    @Parameter(title: "Description", description: "Replaces the description. Formatting is kept.")
    var details: AttributedString?

    @Parameter(title: "Add Tags")
    var addTags: [String]?

    @Parameter(title: "Remove Tags")
    var removeTags: [String]?

    @Dependency var root: MapRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<MapEntity> & ProvidesDialog {
        try await requireReadyDatabase()
        try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which map?", bundle: .module))
        let changed = try await updateIntentItem(id: target.id, name: name, description: details, addTags: addTags, removeTags: removeTags, in: root)
        let model = try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which map?", bundle: .module))
        let updated = MapEntity(root: root, model: model)
        guard changed else {
            return .result(value: updated, dialog: .localized("Nothing changed in \"\(updated.name)\".", bundle: .module))
        }
        await indexIntentEntities([updated])
        return .result(value: updated, dialog: .localized("Updated \"\(updated.name)\".", bundle: .module))
    }
}

@AppIntent(schema: .system.search)
struct SearchMapsIntent: ShowInAppSearchResultsIntent {
    static let title: LocalizedStringResource = "Search Maps"
    static let description = IntentDescription(
        "Shows the maps that match a search term in the app.",
        categoryName: "Map",
        searchKeywords: ["find", "dungeon"]
    )
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
    static let description = IntentDescription(
        "Moves maps to the trash. They can be restored in the app.",
        categoryName: "Map",
        searchKeywords: ["remove", "trash", "dungeon"]
    )
    /// A trashed item is recoverable, but a locked device should not be able to trash a campaign.
    /// Create, Add and the dice and audio intents stay open for use at the table.
    /// See CODE_AUDIT_AppIntents2 §6.1.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Maps")
    var entities: [MapEntity]

    @Dependency var root: MapRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await requireReadyDatabase()
        let ids = entities.map(\.id)

        try await trashIntentItems(ids: ids, ofType: MapEntity.self, in: root)

        let count = entities.count
        let message = AttributedString(
            localized: "Deleted ^[\(count) map](inflect: true).",
            bundle: .module
        )
        return .result(dialog: .verbatim(message))
    }
}

#if os(iOS)
extension SearchMapsIntent: TargetContentProvidingIntent {}
#endif

#endif
