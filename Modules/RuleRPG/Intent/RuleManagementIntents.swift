// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreRPG
import CoreSpotlight
import Foundation

struct CreateRuleIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Rule"
    static let description = IntentDescription(
        "Creates a rule with a name and, optionally, a description.",
        categoryName: "Rule",
        searchKeywords: ["compendium", "rulebook", "new"]
    )
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    static var parameterSummary: some ParameterSummary {
        Summary("Create rule named \(\.$name)")
    }

    @Parameter(title: "Name", requestValueDialog: .localized("What should the rule be called?", bundle: .ruleModule))
    var name: String

    @Parameter(title: "Description")
    var details: AttributedString?

    @Parameter(title: "Open When Created", default: false)
    var openWhenCreated: Bool

    @Dependency var root: RuleRootModel
    @Dependency var navigator: Navigator

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<RuleEntity> & ProvidesDialog {
        try await requireReadyDatabase()
        // Siri and Shortcuts can pass an empty name: ask again instead of creating a blank item.
        // See CODE_AUDIT_AppIntents §5.2.
        let trimmedName = try requiredIntentName(name, parameter: $name, prompt: .localized("What should the rule be called?", bundle: .ruleModule))
        let model = RuleModel(
            id: UUID(),
            name: trimmedName,
            description: details.map { String($0.characters) } ?? ""
        )
        // Saved to the library also during a game. See CODE_AUDIT_Since_3.0.1 §5.2.
        root.itemController.replace(model: model, isInsert: true, forceSave: true)
        await root.itemController.save()
        let entity = RuleEntity(root: root, model: model)
        await indexIntentEntities([entity])

        if openWhenCreated {
            await navigator.perform(route: KnownRoutes.rules(model.id, nil))
            try await continueInForeground(alwaysConfirm: false)
        }
        return .result(value: entity, dialog: .localized("Created \"\(trimmedName)\".", bundle: .ruleModule))
    }
}

struct AddRuleSectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Rule Section"
    static let description = IntentDescription(
        "Adds a section with a name and text at the end of a rule.",
        categoryName: "Rule",
        searchKeywords: ["add", "note", "compendium"]
    )

    static var parameterSummary: some ParameterSummary {
        Summary("Add section \(\.$sectionName) to \(\.$target)")
    }

    @Parameter(title: "Rule", requestValueDialog: .localized("Which rule?", bundle: .ruleModule))
    var target: RuleEntity

    @Parameter(title: "Section Name", requestValueDialog: .localized("What should the section be called?", bundle: .ruleModule))
    var sectionName: String

    @Parameter(title: "Content")
    var content: AttributedString?

    @Dependency var root: RuleRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<RuleEntity> & ProvidesDialog {
        try await requireReadyDatabase()
        // Siri and Shortcuts can pass an empty name: ask again instead of adding a blank section.
        // See CODE_AUDIT_AppIntents §5.2.
        let trimmedSectionName = try requiredIntentName(sectionName, parameter: $sectionName, prompt: .localized("What should the section be called?", bundle: .ruleModule))
        let current = root.itemController.itemSync(for: target.id).flatMap { $0.specialCategory ? nil : $0 }
        try requiredIntentTarget(current, parameter: $target, prompt: .localized("Which rule?", bundle: .ruleModule))
        let entry = root.editController.create(
            name: trimmedSectionName,
            content: intentMarkdown(from: content)
        )
        try requireOutsideGame([target.id], in: root)
        root.editController.add(entry: entry, itemId: target.id, forceSave: true)
        await root.itemController.save()
        // The updated rule is returned so a shortcut can go on with it.
        // See CODE_AUDIT_AppIntents3 §4.14.
        let model = try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which rule?", bundle: .ruleModule))
        let updated = RuleEntity(root: root, model: model)
        await indexIntentEntities([updated])
        return .result(value: updated, dialog: .localized("Added \"\(trimmedSectionName)\" to \"\(target.name)\".", bundle: .ruleModule))
    }
}

/// Renames a rule, replaces its description or changes its tags. See CODE_AUDIT_AppIntents3 §4.5.
struct UpdateRuleIntent: AppIntent {
    static let title: LocalizedStringResource = "Update Rule"
    static let description = IntentDescription(
        "Renames a rule, replaces its description, or adds and removes tags. Fields left empty stay as they are.",
        categoryName: "Rule",
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

    @Parameter(title: "Rule", requestValueDialog: .localized("Which rule?", bundle: .ruleModule))
    var target: RuleEntity

    @Parameter(title: "New Name")
    var name: String?

    @Parameter(title: "Description", description: "Replaces the description. Formatting is kept.")
    var details: AttributedString?

    @Parameter(title: "Add Tags")
    var addTags: [String]?

    @Parameter(title: "Remove Tags")
    var removeTags: [String]?

    @Dependency var root: RuleRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<RuleEntity> & ProvidesDialog {
        try await requireReadyDatabase()
        try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which rule?", bundle: .ruleModule))
        let changed = try await updateIntentItem(id: target.id, name: name, description: details, addTags: addTags, removeTags: removeTags, in: root)
        let model = try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which rule?", bundle: .ruleModule))
        let updated = RuleEntity(root: root, model: model)
        guard changed else {
            return .result(value: updated, dialog: .localized("Nothing changed in \"\(updated.name)\".", bundle: .ruleModule))
        }
        await indexIntentEntities([updated])
        return .result(value: updated, dialog: .localized("Updated \"\(updated.name)\".", bundle: .ruleModule))
    }
}

@AppIntent(schema: .system.search)
struct SearchRulesIntent: ShowInAppSearchResultsIntent {
    static let title: LocalizedStringResource = "Search Rules"
    static let description = IntentDescription(
        "Shows the rules that match a search term in the app.",
        categoryName: "Rule",
        searchKeywords: ["find", "compendium"]
    )
    static let searchScopes: [StringSearchScope] = [.general]

    var criteria: StringSearchCriteria
    @Dependency var root: RuleRootModel
    @Dependency var navigator: Navigator

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await DatabaseReadiness.wait()
        root.searchModel.searchText = criteria.term
        await navigator.perform(route: KnownRoutes.rules(nil, nil))
        return .result()
    }
}

struct DeleteRuleIntent: DeleteIntent {
    static let title: LocalizedStringResource = "Delete Rule"
    static let description = IntentDescription(
        "Moves rules to the trash. They can be restored in the app.",
        categoryName: "Rule",
        searchKeywords: ["remove", "trash", "compendium"]
    )
    /// A trashed item is recoverable, but a locked device should not be able to trash a campaign.
    /// Create, Add and the dice and audio intents stay open for use at the table.
    /// See CODE_AUDIT_AppIntents2 §6.1.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Rules")
    var entities: [RuleEntity]

    @Dependency var root: RuleRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await requireReadyDatabase()
        let ids = entities.compactMap { entity -> UUID? in
            guard let model = root.itemController.itemSync(for: entity.id),
                  !model.specialCategory else { return nil }
            return entity.id
        }
        try await trashIntentItems(ids: ids, ofType: RuleEntity.self, in: root)
        let message = AttributedString(localized: "Deleted ^[\(ids.count) rule](inflect: true).", bundle: .ruleModule)
        return .result(dialog: .verbatim(message))
    }
}

#if os(iOS)
extension SearchRulesIntent: TargetContentProvidingIntent {}
#endif

#endif
