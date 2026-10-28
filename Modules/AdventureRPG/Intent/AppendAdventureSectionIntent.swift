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
        try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which adventure?", bundle: .module))
        let entry = root.editController.create(name: trimmedName, content: intentMarkdown(from: content))
        try requireOutsideGame([target.id], in: root)
        root.editController.add(entry: entry, itemId: target.id, forceSave: true)
        await root.itemController.save()

        // The updated adventure is returned so a shortcut can go on with it.
        // See CODE_AUDIT_AppIntents3 §4.14.
        let model = try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which adventure?", bundle: .module))
        let updated = AdventureEntity(root: root, model: model)
        await indexIntentEntities([updated])

        return .result(value: updated, dialog: .localized("Added \"\(trimmedName)\" to \"\(target.name)\".", bundle: .module))
    }
}

/// Renames an adventure, replaces its summary or changes its tags. See CODE_AUDIT_AppIntents3 §4.5.
public struct UpdateAdventureIntent: AppIntent {
    public static let title: LocalizedStringResource = "Update Adventure"
    public static let description = IntentDescription(
        "Renames an adventure, replaces the summary of its story, or adds and removes tags. Fields left empty stay as they are.",
        categoryName: "Adventure",
        searchKeywords: ["rename", "edit", "change", "tag"]
    )
    /// A locked device cannot rename an item or replace its description. Value changes and
    /// rolls stay open for play. See CODE_AUDIT_AppIntents3 §6.
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    public static var parameterSummary: some ParameterSummary {
        Summary("Update \(\.$target)") {
            \.$name
            \.$story
            \.$addTags
            \.$removeTags
        }
    }

    @Parameter(title: "Adventure", requestValueDialog: .localized("Which adventure?", bundle: .module))
    var target: AdventureEntity

    @Parameter(title: "New Name")
    var name: String?

    @Parameter(title: "Story", description: "Replaces the summary of the story. Formatting is kept.")
    var story: AttributedString?

    @Parameter(title: "Add Tags")
    var addTags: [String]?

    @Parameter(title: "Remove Tags")
    var removeTags: [String]?

    @Dependency var root: AdventureRootModel

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<AdventureEntity> & ProvidesDialog {
        try await requireReadyDatabase()
        try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which adventure?", bundle: .module))
        let changed = try await updateIntentItem(id: target.id, name: name, description: story, addTags: addTags, removeTags: removeTags, in: root)
        let model = try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which adventure?", bundle: .module))
        let updated = AdventureEntity(root: root, model: model)
        guard changed else {
            return .result(value: updated, dialog: .localized("Nothing changed in \"\(updated.name)\".", bundle: .module))
        }
        await indexIntentEntities([updated])
        return .result(value: updated, dialog: .localized("Updated \"\(updated.name)\".", bundle: .module))
    }
}

#endif
