// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreSpotlight
import CoreRPG
import Foundation

struct CreateWeatherIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Weather"
    static let description = IntentDescription(
        "Creates a weather with a name and, optionally, a description.",
        categoryName: "Weather",
        searchKeywords: ["climate", "season", "new"]
    )
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    static var parameterSummary: some ParameterSummary {
        Summary("Create weather named \(\.$name)")
    }

    @Parameter(title: "Name", requestValueDialog: .localized("What should the weather be called?", bundle: .module))
    var name: String

    @Parameter(title: "Description")
    var details: AttributedString?

    @Parameter(title: "Open When Created", default: false)
    var openWhenCreated: Bool

    @Dependency var root: WeatherRootModel
    @Dependency var navigator: Navigator

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<WeatherEntity> & ProvidesDialog {
        try await requireReadyDatabase()
        // Siri and Shortcuts can pass an empty name: ask again instead of creating a blank item.
        // See CODE_AUDIT_AppIntents §5.2.
        let trimmedName = try requiredIntentName(name, parameter: $name, prompt: .localized("What should the weather be called?", bundle: .module))
        let model = WeatherModel.empty(UUID())
        model.name = trimmedName
        model.description = intentMarkdown(from: details)

        root.itemController.replace(model: model, isInsert: true)
        await root.itemController.save()

        let entity = WeatherEntity(root: root, model: model)
        await indexIntentEntities([entity])

        if openWhenCreated {
            await navigator.perform(route: KnownRoutes.weathers(model.id, nil))
            try await continueInForeground(alwaysConfirm: false)
        }

        return .result(value: entity, dialog: .localized("Created \"\(trimmedName)\".", bundle: .module))
    }
}

struct AddWeatherNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Weather Note"
    static let description = IntentDescription(
        "Adds a note to the description of a weather.",
        categoryName: "Weather",
        searchKeywords: ["add", "note", "climate"]
    )

    static var parameterSummary: some ParameterSummary {
        Summary("Add note to \(\.$target)")
    }

    @Parameter(title: "Weather", requestValueDialog: .localized("Which weather?", bundle: .module))
    var target: WeatherEntity

    @Parameter(title: "Note", requestValueDialog: .localized("What note should be added?", bundle: .module))
    var note: AttributedString

    @Dependency var root: WeatherRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<WeatherEntity> & ProvidesDialog {
        try await requireReadyDatabase()
        // `target` can be deleted since Siri or Shortcuts cached it. See CODE_AUDIT_AppIntents §5.2.
        let targetModel = try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which weather?", bundle: .module))
        let currentDescription = targetModel.description
        let updatedDescription = appendingIntentText(
            intentMarkdown(from: note),
            to: currentDescription
        )
        guard updatedDescription != currentDescription else {
            return .result(value: WeatherEntity(root: root, model: targetModel), dialog: .localized("No note added.", bundle: .module))
        }

        root.editController.reset(description: updatedDescription, itemId: target.id)
        await root.itemController.save()

        // The updated weather is returned so a shortcut can go on with it.
        // See CODE_AUDIT_AppIntents3 §4.14.
        let model = try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which weather?", bundle: .module))
        let updated = WeatherEntity(root: root, model: model)
        await indexIntentEntities([updated])

        return .result(value: updated, dialog: .localized("Added note to \"\(target.name)\".", bundle: .module))
    }
}

/// Renames a weather, replaces its description or changes its tags. See CODE_AUDIT_AppIntents3 §4.5.
struct UpdateWeatherIntent: AppIntent {
    static let title: LocalizedStringResource = "Update Weather"
    static let description = IntentDescription(
        "Renames a weather, replaces its description, or adds and removes tags. Fields left empty stay as they are.",
        categoryName: "Weather",
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

    @Parameter(title: "Weather", requestValueDialog: .localized("Which weather?", bundle: .module))
    var target: WeatherEntity

    @Parameter(title: "New Name")
    var name: String?

    @Parameter(title: "Description", description: "Replaces the description. Formatting is kept.")
    var details: AttributedString?

    @Parameter(title: "Add Tags")
    var addTags: [String]?

    @Parameter(title: "Remove Tags")
    var removeTags: [String]?

    @Dependency var root: WeatherRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<WeatherEntity> & ProvidesDialog {
        try await requireReadyDatabase()
        try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which weather?", bundle: .module))
        let changed = await updateIntentItem(id: target.id, name: name, description: details, addTags: addTags, removeTags: removeTags, in: root)
        let model = try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which weather?", bundle: .module))
        let updated = WeatherEntity(root: root, model: model)
        guard changed else {
            return .result(value: updated, dialog: .localized("Nothing changed in \"\(updated.name)\".", bundle: .module))
        }
        await indexIntentEntities([updated])
        return .result(value: updated, dialog: .localized("Updated \"\(updated.name)\".", bundle: .module))
    }
}

@AppIntent(schema: .system.search)
struct SearchWeatherIntent: ShowInAppSearchResultsIntent {
    static let title: LocalizedStringResource = "Search Weather"
    static let description = IntentDescription(
        "Shows the weather items that match a search term in the app.",
        categoryName: "Weather",
        searchKeywords: ["find", "climate"]
    )
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
    static let description = IntentDescription(
        "Moves weather items to the trash. They can be restored in the app.",
        categoryName: "Weather",
        searchKeywords: ["remove", "trash", "climate"]
    )
    /// A trashed item is recoverable, but a locked device should not be able to trash a campaign.
    /// Create, Add and the dice and audio intents stay open for use at the table.
    /// See CODE_AUDIT_AppIntents2 §6.1.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Weather")
    var entities: [WeatherEntity]

    @Dependency var root: WeatherRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await requireReadyDatabase()
        let ids = entities.map(\.id)

        await trashIntentItems(ids: ids, ofType: WeatherEntity.self, in: root)

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

#endif
