// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreSpotlight
import CoreRPG
import Foundation

struct CreateTableIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Table"
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    static var parameterSummary: some ParameterSummary {
        Summary("Create table named \(\.$name)")
    }

    @Parameter(title: "Name", requestValueDialog: "What should the table be called?")
    var name: String

    @Parameter(title: "Description")
    var details: AttributedString?

    @Parameter(title: "Open When Created", default: true)
    var openWhenCreated: Bool

    @Dependency var root: TableRootModel
    @Dependency var navigator: Navigator

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<TableEntity> & ProvidesDialog {
        await DatabaseReadiness.wait()
        // Siri and Shortcuts can pass an empty name: ask again instead of creating a blank item.
        // See CODE_AUDIT_AppIntents §5.2.
        let trimmedName = try requiredIntentName(name, parameter: $name, prompt: "What should the table be called?")
        let model = TableModel(
            id: UUID(),
            name: trimmedName,
            description: intentPlainText(from: details),
            entries: []
        )
        root.itemController.replace(model: model, isInsert: true)
        await root.itemController.save()

        let entity = TableEntity(root: root, model: model)
        try await indexIntentEntities([entity])

        if openWhenCreated {
            await navigator.perform(route: KnownRoutes.tables(model.id, nil))
            try await continueInForeground(alwaysConfirm: false)
        }

        return .result(value: entity, dialog: "Created \"\(trimmedName)\".")
    }
}

struct AddTableRowIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Table Row"

    static var parameterSummary: some ParameterSummary {
        Summary("Add row \(\.$rowName) to \(\.$target)")
    }

    @Parameter(title: "Table", requestValueDialog: "Which table?")
    var target: TableEntity

    @Parameter(title: "Row Name", requestValueDialog: "What should the row be called?")
    var rowName: String

    @Parameter(title: "Content")
    var content: AttributedString?

    @Dependency var root: TableRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await DatabaseReadiness.wait()
        // Siri and Shortcuts can pass an empty name, and `target` can be deleted since it was cached:
        // ask again instead of adding a blank entry or reporting a success that changed nothing.
        // See CODE_AUDIT_AppIntents §5.2.
        let trimmedRowName = try requiredIntentName(rowName, parameter: $rowName, prompt: "What should the row be called?")
        try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: "Which table?")
        let entry = root.editController.create(
            name: trimmedRowName,
            content: intentPlainText(from: content)
        )
        root.editController.add(entry: entry, itemId: target.id)
        await root.itemController.save()

        if let model = root.itemController.itemSync(for: target.id) {
            try await indexIntentEntities([TableEntity(root: root, model: model)])
        }

        return .result(dialog: "Added \"\(trimmedRowName)\" to \"\(target.name)\".")
    }
}

@AppIntent(schema: .system.search)
struct SearchTablesIntent: ShowInAppSearchResultsIntent {
    static let title: LocalizedStringResource = "Search Tables"
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

    @Parameter(title: "Tables")
    var entities: [TableEntity]

    @Dependency var root: TableRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await DatabaseReadiness.wait()
        let ids = entities.map(\.id)

        for id in ids {
            root.editController.markForDeletion(itemId: id)
        }
        await root.itemController.save()

        try await deleteIntentEntities(ids: ids, ofType: TableEntity.self)

        let count = entities.count
        return .result(dialog: "Deleted ^[\(count) table](inflect: true).")
    }
}

#if os(iOS)
extension SearchTablesIntent: TargetContentProvidingIntent {}
#endif

#endif
