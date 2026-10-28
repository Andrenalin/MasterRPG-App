// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreSpotlight
import CoreRPG
import Foundation

struct CreateTableIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Table"
    static let description = IntentDescription(
        "Creates a table with a name and, optionally, a description.",
        categoryName: "Table",
        searchKeywords: ["random table", "loot", "encounter", "new"]
    )
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    static var parameterSummary: some ParameterSummary {
        Summary("Create table named \(\.$name)")
    }

    @Parameter(title: "Name", requestValueDialog: .localized("What should the table be called?", bundle: .module))
    var name: String

    @Parameter(title: "Description")
    var details: AttributedString?

    @Parameter(title: "Open When Created", default: false)
    var openWhenCreated: Bool

    @Dependency var root: TableRootModel
    @Dependency var navigator: Navigator

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<TableEntity> & ProvidesDialog {
        try await requireReadyDatabase()
        // Siri and Shortcuts can pass an empty name: ask again instead of creating a blank item.
        // See CODE_AUDIT_AppIntents §5.2.
        let trimmedName = try requiredIntentName(name, parameter: $name, prompt: .localized("What should the table be called?", bundle: .module))
        let model = TableModel(
            id: UUID(),
            name: trimmedName,
            description: intentMarkdown(from: details),
            entries: []
        )
        root.itemController.replace(model: model, isInsert: true)
        await root.itemController.save()

        let entity = TableEntity(root: root, model: model)
        await indexIntentEntities([entity])

        if openWhenCreated {
            await navigator.perform(route: KnownRoutes.tables(model.id, nil))
            try await continueInForeground(alwaysConfirm: false)
        }

        return .result(value: entity, dialog: .localized("Created \"\(trimmedName)\".", bundle: .module))
    }
}

struct AddTableRowIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Table Row"
    static let description = IntentDescription(
        "Adds a row with a name and text to a table.",
        categoryName: "Table",
        searchKeywords: ["add", "note", "random table"]
    )

    static var parameterSummary: some ParameterSummary {
        Summary("Add row \(\.$rowName) to \(\.$target)")
    }

    @Parameter(title: "Table", requestValueDialog: .localized("Which table?", bundle: .module))
    var target: TableEntity

    @Parameter(title: "Row Name", requestValueDialog: .localized("What should the row be called?", bundle: .module))
    var rowName: String

    @Parameter(title: "Content")
    var content: AttributedString?

    @Dependency var root: TableRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<TableEntity> & ProvidesDialog {
        try await requireReadyDatabase()
        // Siri and Shortcuts can pass an empty name, and `target` can be deleted since it was cached:
        // ask again instead of adding a blank entry or reporting a success that changed nothing.
        // See CODE_AUDIT_AppIntents §5.2.
        let trimmedRowName = try requiredIntentName(rowName, parameter: $rowName, prompt: .localized("What should the row be called?", bundle: .module))
        try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which table?", bundle: .module))
        let entry = root.editController.create(
            name: trimmedRowName,
            content: intentMarkdown(from: content)
        )
        root.editController.add(entry: entry, itemId: target.id)
        await root.itemController.save()

        // The updated table is returned so a shortcut can go on with it.
        // See CODE_AUDIT_AppIntents3 §4.14.
        let model = try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which table?", bundle: .module))
        let updated = TableEntity(root: root, model: model)
        await indexIntentEntities([updated])

        return .result(value: updated, dialog: .localized("Added \"\(trimmedRowName)\" to \"\(target.name)\".", bundle: .module))
    }
}

/// Renames a table, replaces its description or changes its tags. See CODE_AUDIT_AppIntents3 §4.5.
struct UpdateTableIntent: AppIntent {
    static let title: LocalizedStringResource = "Update Table"
    static let description = IntentDescription(
        "Renames a table, replaces its description, or adds and removes tags. Fields left empty stay as they are.",
        categoryName: "Table",
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

    @Parameter(title: "Table", requestValueDialog: .localized("Which table?", bundle: .module))
    var target: TableEntity

    @Parameter(title: "New Name")
    var name: String?

    @Parameter(title: "Description", description: "Replaces the description. Formatting is kept.")
    var details: AttributedString?

    @Parameter(title: "Add Tags")
    var addTags: [String]?

    @Parameter(title: "Remove Tags")
    var removeTags: [String]?

    @Dependency var root: TableRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<TableEntity> & ProvidesDialog {
        try await requireReadyDatabase()
        try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which table?", bundle: .module))
        let changed = await updateIntentItem(id: target.id, name: name, description: details, addTags: addTags, removeTags: removeTags, in: root)
        let model = try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which table?", bundle: .module))
        let updated = TableEntity(root: root, model: model)
        guard changed else {
            return .result(value: updated, dialog: .localized("Nothing changed in \"\(updated.name)\".", bundle: .module))
        }
        await indexIntentEntities([updated])
        return .result(value: updated, dialog: .localized("Updated \"\(updated.name)\".", bundle: .module))
    }
}

@AppIntent(schema: .system.search)
struct SearchTablesIntent: ShowInAppSearchResultsIntent {
    static let title: LocalizedStringResource = "Search Tables"
    static let description = IntentDescription(
        "Shows the tables that match a search term in the app.",
        categoryName: "Table",
        searchKeywords: ["find", "random table"]
    )
    static let searchScopes: [StringSearchScope] = [.general]

    var criteria: StringSearchCriteria

    @Dependency var root: TableRootModel
    @Dependency var navigator: Navigator

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await DatabaseReadiness.wait()
        root.searchModel.searchText = criteria.term
        await navigator.perform(route: KnownRoutes.tables(nil, nil))
        return .result()
    }
}

struct DeleteTableIntent: DeleteIntent {
    static let title: LocalizedStringResource = "Delete Table"
    static let description = IntentDescription(
        "Moves tables to the trash. They can be restored in the app.",
        categoryName: "Table",
        searchKeywords: ["remove", "trash", "random table"]
    )
    /// A trashed item is recoverable, but a locked device should not be able to trash a campaign.
    /// Create, Add and the dice and audio intents stay open for use at the table.
    /// See CODE_AUDIT_AppIntents2 §6.1.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Tables")
    var entities: [TableEntity]

    @Dependency var root: TableRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await requireReadyDatabase()
        let ids = entities.map(\.id)

        await trashIntentItems(ids: ids, ofType: TableEntity.self, in: root)

        let count = entities.count
        let message = AttributedString(localized: "Deleted ^[\(count) table](inflect: true).", bundle: .module)
        return .result(dialog: .verbatim(message))
    }
}

#if os(iOS)
extension SearchTablesIntent: TargetContentProvidingIntent {}
#endif

#endif
