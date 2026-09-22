// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreSpotlight
import CoreRPG
import Foundation

struct CreatePdfIntent: AppIntent {
    static let title: LocalizedStringResource = "Create PDF"
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    static var parameterSummary: some ParameterSummary {
        Summary("Create PDF named \(\.$name)")
    }

    @Parameter(title: "Name", requestValueDialog: "What should the PDF be called?")
    var name: String

    @Parameter(title: "Description")
    var details: AttributedString?

    @Parameter(title: "Open When Created", default: true)
    var openWhenCreated: Bool

    @Dependency var root: PdfRootModel
    @Dependency var navigator: Navigator

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<PdfEntity> & ProvidesDialog {
        await DatabaseReadiness.wait()
        let model = PdfModel(
            id: UUID(),
            name: name,
            description: intentPlainText(from: details)
        )
        root.itemController.replace(model: model, isInsert: true)
        await root.itemController.save()

        let entity = PdfEntity(root: root, model: model)
        try await indexIntentEntities([entity])

        if openWhenCreated {
            await navigator.perform(route: KnownRoutes.pdfs(model.id, nil))
            try await continueInForeground(alwaysConfirm: false)
        }

        return .result(value: entity, dialog: "Created \"\(name)\".")
    }
}

struct AddPdfBookmarkIntent: AppIntent {
    static let title: LocalizedStringResource = "Add PDF Bookmark"

    static var parameterSummary: some ParameterSummary {
        Summary("Add bookmark \(\.$bookmarkName) to \(\.$target)")
    }

    @Parameter(title: "PDF", requestValueDialog: "Which PDF?")
    var target: PdfEntity

    @Parameter(title: "Bookmark Name", requestValueDialog: "What should the bookmark be called?")
    var bookmarkName: String

    @Parameter(title: "Content")
    var content: AttributedString?

    @Dependency var root: PdfRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await DatabaseReadiness.wait()
        let entry = root.editController.create(
            name: bookmarkName,
            content: intentPlainText(from: content)
        )
        root.editController.add(entry: entry, itemId: target.id)
        await root.itemController.save()

        if let model = root.itemController.itemSync(for: target.id) {
            try await indexIntentEntities([PdfEntity(root: root, model: model)])
        }

        return .result(dialog: "Added \"\(bookmarkName)\" to \"\(target.name)\".")
    }
}

@AppIntent(schema: .system.search)
struct SearchPdfsIntent: ShowInAppSearchResultsIntent {
    static let title: LocalizedStringResource = "Search PDFs"
    static let searchScopes: [StringSearchScope] = [.general]

    var criteria: StringSearchCriteria

    @Dependency var root: PdfRootModel
    @Dependency var navigator: Navigator

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await DatabaseReadiness.wait()
        root.searchModel.searchText = criteria.term
        await navigator.perform(route: KnownRoutes.pdfs(nil, nil))
        return .result()
    }
}

struct DeletePdfIntent: DeleteIntent {
    static let title: LocalizedStringResource = "Delete PDF"

    @Parameter(title: "PDFs")
    var entities: [PdfEntity]

    @Dependency var root: PdfRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await DatabaseReadiness.wait()
        let ids = entities.map(\.id)

        for id in ids {
            await root.editController.markForDeletion(itemId: id)
        }
        await root.itemController.save()

        try await deleteIntentEntities(ids: ids, ofType: PdfEntity.self)

        let count = entities.count
        let message = AttributedString(
            localized: "Deleted ^[\(count) PDF](inflect: true).",
            bundle: .module
        )
        return .result(dialog: "\(message)")
    }
}

#if os(iOS)
extension SearchPdfsIntent: TargetContentProvidingIntent {}
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
