// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreSpotlight
import CoreRPG
import Foundation

struct CreateDiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Dice"
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    static var parameterSummary: some ParameterSummary {
        Summary("Create dice named \(\.$name)")
    }

    @Parameter(title: "Name", requestValueDialog: "What should the dice be called?")
    var name: String

    @Parameter(title: "Description")
    var details: AttributedString?

    @Parameter(title: "First Die", default: .d20)
    var diceType: IntentDiceType

    @Parameter(title: "Open When Created", default: true)
    var openWhenCreated: Bool

    @Dependency var root: DiceRootModel
    @Dependency var navigator: Navigator

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<DiceEntity> & ProvidesDialog {
        await DatabaseReadiness.wait()
        let model = DiceModel(
            id: UUID(),
            name: name,
            description: intentPlainText(from: details),
            dice: [DieModel(id: UUID(), die: diceType.rawDie)]
        )
        root.itemController.replace(model: model, isInsert: true)
        await root.itemController.save()

        let entity = DiceEntity(root: root, model: model)
        try await indexIntentEntities([entity])

        if openWhenCreated {
            await navigator.perform(route: KnownRoutes.dice(model.id, nil))
            try await continueInForeground(alwaysConfirm: false)
        }

        return .result(value: entity, dialog: "Created \"\(name)\".")
    }
}

struct AddDieToDiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Die to Dice"

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$diceType) to \(\.$target)")
    }

    @Parameter(title: "Dice", requestValueDialog: "Which dice?")
    var target: DiceEntity

    @Parameter(title: "Die Type", default: .d20)
    var diceType: IntentDiceType

    @Dependency var root: DiceRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await DatabaseReadiness.wait()
        let die = DieModel(id: UUID(), die: diceType.rawDie)
        root.editController.add(die: die, itemId: target.id)
        await root.itemController.save()

        if let model = root.itemController.itemSync(for: target.id) {
            try await indexIntentEntities([DiceEntity(root: root, model: model)])
        }

        return .result(dialog: "Added \(diceType.rawValue) to \"\(target.name)\".")
    }
}

@AppIntent(schema: .system.search)
struct SearchDiceIntent: ShowInAppSearchResultsIntent {
    static let title: LocalizedStringResource = "Search Dice"
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

    @Parameter(title: "Dice")
    var entities: [DiceEntity]

    @Dependency var root: DiceRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await DatabaseReadiness.wait()
        let ids = entities.map(\.id)

        for id in ids {
            await root.editController.delete(itemId: id)
        }
        await root.itemController.save()

        try await deleteIntentEntities(ids: ids, ofType: DiceEntity.self)

        let count = entities.count
        let message = AttributedString(
            localized: "Deleted ^[\(count) dice set](inflect: true).",
            bundle: .module
        )
        return .result(dialog: "\(message)")
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
