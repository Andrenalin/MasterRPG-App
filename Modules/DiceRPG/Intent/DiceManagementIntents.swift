// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreSpotlight
import CoreRPG
import Foundation

struct CreateDiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Dice"
    static let description = IntentDescription(
        "Creates a dice with a name and, optionally, a description.",
        categoryName: "Dice",
        searchKeywords: ["die", "roll", "new"]
    )
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    static var parameterSummary: some ParameterSummary {
        Summary("Create dice named \(\.$name)")
    }

    @Parameter(title: "Name", requestValueDialog: .localized("What should the dice be called?", bundle: .module))
    var name: String

    @Parameter(title: "Description")
    var details: AttributedString?

    @Parameter(title: "First Die", default: .d20)
    var diceType: IntentDiceType

    @Parameter(title: "Open When Created", default: false)
    var openWhenCreated: Bool

    @Dependency var root: DiceRootModel
    @Dependency var navigator: Navigator

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<DiceEntity> & ProvidesDialog {
        try await requireReadyDatabase()
        // Siri and Shortcuts can pass an empty name: ask again instead of creating a blank item.
        // See CODE_AUDIT_AppIntents §5.2.
        let trimmedName = try requiredIntentName(name, parameter: $name, prompt: .localized("What should the dice be called?", bundle: .module))
        let model = DiceModel(
            id: UUID(),
            name: trimmedName,
            description: intentMarkdown(from: details),
            dice: [DieModel(id: UUID(), die: diceType.rawDie)]
        )
        // Saved to the library also during a game. See CODE_AUDIT_Since_3.0.1 §5.2.
        root.itemController.replace(model: model, isInsert: true, forceSave: true)
        await root.itemController.save()

        let entity = DiceEntity(root: root, model: model)
        await indexIntentEntities([entity])

        if openWhenCreated {
            await navigator.perform(route: KnownRoutes.dice(model.id, nil))
            try await continueInForeground(alwaysConfirm: false)
        }

        return .result(value: entity, dialog: .localized("Created \"\(trimmedName)\".", bundle: .module))
    }
}

struct AddDieToDiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Die to Dice"
    static let description = IntentDescription(
        "Adds a die to a dice set.",
        categoryName: "Dice",
        searchKeywords: ["add", "note", "die"]
    )

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$diceType) to \(\.$target)")
    }

    @Parameter(title: "Dice", requestValueDialog: .localized("Which dice?", bundle: .module))
    var target: DiceEntity

    @Parameter(title: "Die Type", default: .d20)
    var diceType: IntentDiceType

    @Dependency var root: DiceRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<DiceEntity> & ProvidesDialog {
        try await requireReadyDatabase()
        // `target` can be deleted since Siri or Shortcuts cached it. See CODE_AUDIT_AppIntents §5.2.
        try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which dice?", bundle: .module))
        let die = DieModel(id: UUID(), die: diceType.rawDie)
        try requireOutsideGame([target.id], in: root)
        root.editController.add(die: die, itemId: target.id, forceSave: true)
        await root.itemController.save()

        // The updated dice is returned so a shortcut can go on with it.
        // See CODE_AUDIT_AppIntents3 §4.14.
        let model = try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which dice?", bundle: .module))
        let updated = DiceEntity(root: root, model: model)
        await indexIntentEntities([updated])

        return .result(value: updated, dialog: .localized("Added \(diceType.rawValue) to \"\(target.name)\".", bundle: .module))
    }
}

/// Renames a dice, replaces its description or changes its tags. See CODE_AUDIT_AppIntents3 §4.5.
struct UpdateDiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Update Dice"
    static let description = IntentDescription(
        "Renames a dice, replaces its description, or adds and removes tags. Fields left empty stay as they are.",
        categoryName: "Dice",
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

    @Parameter(title: "Dice", requestValueDialog: .localized("Which dice?", bundle: .module))
    var target: DiceEntity

    @Parameter(title: "New Name")
    var name: String?

    @Parameter(title: "Description", description: "Replaces the description. Formatting is kept.")
    var details: AttributedString?

    @Parameter(title: "Add Tags")
    var addTags: [String]?

    @Parameter(title: "Remove Tags")
    var removeTags: [String]?

    @Dependency var root: DiceRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<DiceEntity> & ProvidesDialog {
        try await requireReadyDatabase()
        try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which dice?", bundle: .module))
        let changed = try await updateIntentItem(id: target.id, name: name, description: details, addTags: addTags, removeTags: removeTags, in: root)
        let model = try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which dice?", bundle: .module))
        let updated = DiceEntity(root: root, model: model)
        guard changed else {
            return .result(value: updated, dialog: .localized("Nothing changed in \"\(updated.name)\".", bundle: .module))
        }
        await indexIntentEntities([updated])
        return .result(value: updated, dialog: .localized("Updated \"\(updated.name)\".", bundle: .module))
    }
}

@AppIntent(schema: .system.search)
struct SearchDiceIntent: ShowInAppSearchResultsIntent {
    static let title: LocalizedStringResource = "Search Dice"
    static let description = IntentDescription(
        "Shows the dice that match a search term in the app.",
        categoryName: "Dice",
        searchKeywords: ["find", "die"]
    )
    static let searchScopes: [StringSearchScope] = [.general]

    var criteria: StringSearchCriteria

    @Dependency var root: DiceRootModel
    @Dependency var navigator: Navigator

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await DatabaseReadiness.wait()
        root.searchModel.searchText = criteria.term
        await navigator.perform(route: KnownRoutes.dice(nil, nil))
        return .result()
    }
}

struct DeleteDiceIntent: DeleteIntent {
    static let title: LocalizedStringResource = "Delete Dice"
    static let description = IntentDescription(
        "Moves dice to the trash. They can be restored in the app.",
        categoryName: "Dice",
        searchKeywords: ["remove", "trash", "die"]
    )
    /// A trashed item is recoverable, but a locked device should not be able to trash a campaign.
    /// Create, Add and the dice and audio intents stay open for use at the table.
    /// See CODE_AUDIT_AppIntents2 §6.1.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Dice")
    var entities: [DiceEntity]

    @Dependency var root: DiceRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await requireReadyDatabase()
        let ids = entities.map(\.id)

        try await trashIntentItems(ids: ids, ofType: DiceEntity.self, in: root)

        let count = entities.count
        let message = AttributedString(
            localized: "Deleted ^[\(count) dice set](inflect: true).",
            bundle: .module
        )
        return .result(dialog: .verbatim(message))
    }
}

// Shared with `DiceIntents.swift`'s `RollDiceIntent` — kept internal (not
// `private`) so both intent files can map a Siri-facing dice type to the
// concrete `RawDie` without duplicating the switch. See CODE_AUDIT §5.2.
extension IntentDiceType {
    var rawDie: RawDie {
        return switch self {
        case .d4: RawDie(.four)
        case .d6: RawDie(.six)
        case .d8: RawDie(.eight)
        case .d10: RawDie(.ten)
        case .d12: RawDie(.twelve)
        case .d20: RawDie(.twenty)
        case .d100: RawDie(.number(100))
        }
    }
}

#if os(iOS)
extension SearchDiceIntent: TargetContentProvidingIntent {}
#endif

#endif
