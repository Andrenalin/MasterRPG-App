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

    @Parameter(title: "File")
    var file: IntentFile?

    @Parameter(title: "Open When Created", default: false)
    var openWhenCreated: Bool

    @Dependency var root: PdfRootModel
    @Dependency var navigator: Navigator

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<PdfEntity> & ProvidesDialog {
        try await requireReadyDatabase()
        // Siri and Shortcuts can pass an empty name: ask again instead of creating a blank item.
        // See CODE_AUDIT_AppIntents §5.2.
        let trimmedName = try requiredIntentName(name, parameter: $name, prompt: "What should the PDF be called?")
        let fileData = try intentFileData(file, allowedTypes: root.config.fileTypes)
        let model = PdfModel(
            id: UUID(),
            name: trimmedName,
            description: intentPlainText(from: details)
        )
        root.itemController.replace(model: model, isInsert: true)
        await root.itemController.save()

        if let fileData {
            try await attachIntentFile(to: model.id, editControllable: root.editController) {
                try await root.editController.resetFile(data: fileData, itemId: model.id, path: "")
                return true
            }
        }

        let entity = PdfEntity(root: root, model: model)
        await indexIntentEntities([entity])

        if openWhenCreated {
            await navigator.perform(route: KnownRoutes.pdfs(model.id, nil))
            try await continueInForeground(alwaysConfirm: false)
        }

        return .result(value: entity, dialog: "Created \"\(trimmedName)\".")
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
        try await requireReadyDatabase()
        // Siri and Shortcuts can pass an empty name, and `target` can be deleted since it was cached:
        // ask again instead of adding a blank entry or reporting a success that changed nothing.
        // See CODE_AUDIT_AppIntents §5.2.
        let trimmedBookmarkName = try requiredIntentName(bookmarkName, parameter: $bookmarkName, prompt: "What should the bookmark be called?")
        try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: "Which PDF?")
        let entry = root.editController.create(
            name: trimmedBookmarkName,
            content: intentPlainText(from: content)
        )
        root.editController.add(entry: entry, itemId: target.id)
        await root.itemController.save()

        if let model = root.itemController.itemSync(for: target.id) {
            await indexIntentEntities([PdfEntity(root: root, model: model)])
        }

        return .result(dialog: "Added \"\(trimmedBookmarkName)\" to \"\(target.name)\".")
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
    /// A trashed item is recoverable, but a locked device should not be able to trash a campaign.
    /// Create, Add and the dice and audio intents stay open for use at the table.
    /// See CODE_AUDIT_AppIntents2 §6.1.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "PDFs")
    var entities: [PdfEntity]

    @Dependency var root: PdfRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await requireReadyDatabase()
        let ids = entities.map(\.id)

        await trashIntentItems(ids: ids, ofType: PdfEntity.self, in: root)

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

#endif
