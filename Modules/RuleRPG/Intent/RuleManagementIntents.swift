// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreRPG
import CoreSpotlight
import Foundation

struct CreateRuleIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Rule"
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    static var parameterSummary: some ParameterSummary {
        Summary("Create rule named \(\.$name)")
    }

    @Parameter(title: "Name", requestValueDialog: "What should the rule be called?")
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
        await DatabaseReadiness.wait()
        // Siri and Shortcuts can pass an empty name: ask again instead of creating a blank item.
        // See CODE_AUDIT_AppIntents §5.2.
        let trimmedName = try requiredIntentName(name, parameter: $name, prompt: "What should the rule be called?")
        let model = RuleModel(
            id: UUID(),
            name: trimmedName,
            description: details.map { String($0.characters) } ?? ""
        )
        root.itemController.replace(model: model, isInsert: true)
        await root.itemController.save()
        let entity = RuleEntity(root: root, model: model)
        try await indexRuleEntities([entity])

        if openWhenCreated {
            await navigator.perform(route: KnownRoutes.rules(model.id, nil))
            try await continueInForeground(alwaysConfirm: false)
        }
        return .result(value: entity, dialog: "Created \"\(trimmedName)\".")
    }
}

struct AddRuleSectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Rule Section"

    static var parameterSummary: some ParameterSummary {
        Summary("Add section \(\.$sectionName) to \(\.$target)")
    }

    @Parameter(title: "Rule", requestValueDialog: "Which rule?")
    var target: RuleEntity

    @Parameter(title: "Section Name", requestValueDialog: "What should the section be called?")
    var sectionName: String

    @Parameter(title: "Content")
    var content: AttributedString?

    @Dependency var root: RuleRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await DatabaseReadiness.wait()
        // Siri and Shortcuts can pass an empty name: ask again instead of adding a blank section.
        // See CODE_AUDIT_AppIntents §5.2.
        let trimmedSectionName = try requiredIntentName(sectionName, parameter: $sectionName, prompt: "What should the section be called?")
        guard let targetModel = root.itemController.itemSync(for: target.id),
              !targetModel.specialCategory else {
            return .result(dialog: "The selected rule is no longer available.")
        }
        let entry = root.editController.create(
            name: trimmedSectionName,
            content: content.map { String($0.characters) } ?? ""
        )
        root.editController.add(entry: entry, itemId: target.id)
        await root.itemController.save()
        if let model = root.itemController.itemSync(for: target.id) {
            try await indexRuleEntities([RuleEntity(root: root, model: model)])
        }
        return .result(dialog: "Added \"\(trimmedSectionName)\" to \"\(target.name)\".")
    }
}

@AppIntent(schema: .system.search)
struct SearchRulesIntent: ShowInAppSearchResultsIntent {
    static let title: LocalizedStringResource = "Search Rules"
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

    @Parameter(title: "Rules")
    var entities: [RuleEntity]

    @Dependency var root: RuleRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await DatabaseReadiness.wait()
        let ids = entities.compactMap { entity -> UUID? in
            guard let model = root.itemController.itemSync(for: entity.id),
                  !model.specialCategory else { return nil }
            return entity.id
        }
        for id in ids {
            root.editController.markForDeletion(itemId: id)
        }
        await root.itemController.save()
        await deleteIntentEntities(ids: ids, ofType: RuleEntity.self)
        return .result(dialog: "Deleted ^[\(ids.count) rule](inflect: true).")
    }
}

#if os(iOS)
extension SearchRulesIntent: TargetContentProvidingIntent {}
#endif

private func indexRuleEntities(_ entities: [RuleEntity]) async throws {
    guard CSSearchableIndex.isIndexingAvailable() else { return }
    try await CSSearchableIndex.default().indexAppEntities(entities)
}

#endif
