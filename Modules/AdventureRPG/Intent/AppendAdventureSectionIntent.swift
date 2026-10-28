// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents

public struct AppendAdventureSectionIntent: AppIntent {
    public static let title: LocalizedStringResource = "Append Section to Adventure"
    public static let description = IntentDescription(
        "Adds a new section with a title and text at the end of an adventure.",
        categoryName: "Adventure",
        searchKeywords: ["chapter", "scene", "note", "add"]
    )

    public static var parameterSummary: some ParameterSummary {
        Summary("Add section \(\.$sectionName) to \(\.$target)")
    }

    @Parameter(title: "Adventure", requestValueDialog: .localized("Which adventure?", bundle: .module))
    var target: AdventureEntity

    @Parameter(title: "Section Name", requestValueDialog: .localized("What should the section be called?", bundle: .module))
    var sectionName: String

    @Parameter(title: "Content", description: "The text of the section. Formatting is kept.")
    var content: AttributedString?

    @Dependency var root: AdventureRootModel

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<AdventureEntity> & ProvidesDialog {
        try await requireReadyDatabase()
        // Siri and Shortcuts can pass an empty name, and `target` can be an adventure that was
        // deleted since it was cached: ask again instead of adding a blank section or
        // reporting success for nothing. See CODE_AUDIT_21 §5.28.
        let trimmedName = try requiredIntentName(sectionName, parameter: $sectionName, prompt: .localized("What should the section be called?", bundle: .module))
        try requiredIntentModel($target, prompt: AdventureIntentSupport.targetPrompt, in: root)
        let entry = root.editController.create(name: trimmedName, content: intentMarkdown(from: content))
        try requireOutsideGame([target.id], in: root)
        root.editController.add(entry: entry, itemId: target.id, forceSave: true)
        try await root.itemController.saveForIntent()

        // The updated adventure is returned so a shortcut can go on with it.
        // See CODE_AUDIT_AppIntents3 §4.14.
        let updated = try await reindexedIntentTarget($target, prompt: AdventureIntentSupport.targetPrompt, in: root)

        return .result(value: updated, dialog: .localized("Added \"\(trimmedName)\" to \"\(target.name)\".", bundle: .module))
    }
}

#endif
