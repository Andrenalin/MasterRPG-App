// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreSpotlight
import CoreRPG
import Foundation

struct CreatePdfIntent: AppIntent {
    static let title: LocalizedStringResource = "Create PDF"
    static let description = IntentDescription(
        "Creates a PDF with a name and, optionally, a description.",
        categoryName: "PDF",
        searchKeywords: ["book", "document", "handout", "new"]
    )
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    static var parameterSummary: some ParameterSummary {
        Summary("Create PDF named \(\.$name)")
    }

    @Parameter(title: "Name", requestValueDialog: .localized("What should the PDF be called?", bundle: .module))
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
        let trimmedName = try requiredIntentName(name, parameter: $name, prompt: .localized("What should the PDF be called?", bundle: .module))
        let fileData = try await intentFileData(file, allowedTypes: root.config.fileTypes)
        let model = PdfModel(
            id: UUID(),
            name: trimmedName,
            description: intentMarkdown(from: details)
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

        return .result(value: entity, dialog: .localized("Created \"\(trimmedName)\".", bundle: .module))
    }
}

struct AddPdfBookmarkIntent: AppIntent {
    static let title: LocalizedStringResource = "Add PDF Bookmark"
    static let description = IntentDescription(
        "Adds a bookmark with a name and text to a PDF.",
        categoryName: "PDF",
        searchKeywords: ["add", "note", "book"]
    )

    static var parameterSummary: some ParameterSummary {
        Summary("Add bookmark \(\.$bookmarkName) to \(\.$target)")
    }

    @Parameter(title: "PDF", requestValueDialog: .localized("Which PDF?", bundle: .module))
    var target: PdfEntity

    @Parameter(title: "Bookmark Name", requestValueDialog: .localized("What should the bookmark be called?", bundle: .module))
    var bookmarkName: String

    @Parameter(title: "Content")
    var content: AttributedString?

    @Dependency var root: PdfRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<PdfEntity> & ProvidesDialog {
        try await requireReadyDatabase()
        // Siri and Shortcuts can pass an empty name, and `target` can be deleted since it was cached:
        // ask again instead of adding a blank entry or reporting a success that changed nothing.
        // See CODE_AUDIT_AppIntents §5.2.
        let trimmedBookmarkName = try requiredIntentName(bookmarkName, parameter: $bookmarkName, prompt: .localized("What should the bookmark be called?", bundle: .module))
        try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which PDF?", bundle: .module))
        let entry = root.editController.create(
            name: trimmedBookmarkName,
            content: intentMarkdown(from: content)
        )
        root.editController.add(entry: entry, itemId: target.id)
        await root.itemController.save()

        // The updated PDF is returned so a shortcut can go on with it.
        // See CODE_AUDIT_AppIntents3 §4.14.
        let model = try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which PDF?", bundle: .module))
        let updated = PdfEntity(root: root, model: model)
        await indexIntentEntities([updated])

        return .result(value: updated, dialog: .localized("Added \"\(trimmedBookmarkName)\" to \"\(target.name)\".", bundle: .module))
    }
}

/// Renames a PDF, replaces its description or changes its tags. See CODE_AUDIT_AppIntents3 §4.5.
struct UpdatePdfIntent: AppIntent {
    static let title: LocalizedStringResource = "Update PDF"
    static let description = IntentDescription(
        "Renames a PDF, replaces its description, or adds and removes tags. Fields left empty stay as they are.",
        categoryName: "PDF",
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

    @Parameter(title: "PDF", requestValueDialog: .localized("Which PDF?", bundle: .module))
    var target: PdfEntity

    @Parameter(title: "New Name")
    var name: String?

    @Parameter(title: "Description", description: "Replaces the description. Formatting is kept.")
    var details: AttributedString?

    @Parameter(title: "Add Tags")
    var addTags: [String]?

    @Parameter(title: "Remove Tags")
    var removeTags: [String]?

    @Dependency var root: PdfRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<PdfEntity> & ProvidesDialog {
        try await requireReadyDatabase()
        try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which PDF?", bundle: .module))
        let changed = await updateIntentItem(id: target.id, name: name, description: details, addTags: addTags, removeTags: removeTags, in: root)
        let model = try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which PDF?", bundle: .module))
        let updated = PdfEntity(root: root, model: model)
        guard changed else {
            return .result(value: updated, dialog: .localized("Nothing changed in \"\(updated.name)\".", bundle: .module))
        }
        await indexIntentEntities([updated])
        return .result(value: updated, dialog: .localized("Updated \"\(updated.name)\".", bundle: .module))
    }
}

@AppIntent(schema: .system.search)
struct SearchPdfsIntent: ShowInAppSearchResultsIntent {
    static let title: LocalizedStringResource = "Search PDFs"
    static let description = IntentDescription(
        "Shows the PDFs that match a search term in the app.",
        categoryName: "PDF",
        searchKeywords: ["find", "book"]
    )
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
    static let description = IntentDescription(
        "Moves PDFs to the trash. They can be restored in the app.",
        categoryName: "PDF",
        searchKeywords: ["remove", "trash", "book"]
    )
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
        return .result(dialog: .verbatim(message))
    }
}

#if os(iOS)
extension SearchPdfsIntent: TargetContentProvidingIntent {}
#endif

#endif
