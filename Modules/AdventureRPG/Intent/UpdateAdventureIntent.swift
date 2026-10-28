// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents

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
        let (updated, changed) = try await updateIntentTarget($target, prompt: AdventureIntentSupport.targetPrompt, name: name, description: story, addTags: addTags, removeTags: removeTags, in: root)
        guard changed else {
            return .result(value: updated, dialog: .localized("Nothing changed in \"\(updated.name)\".", bundle: .module))
        }
        return .result(value: updated, dialog: .localized("Updated \"\(updated.name)\".", bundle: .module))
    }
}

#endif
