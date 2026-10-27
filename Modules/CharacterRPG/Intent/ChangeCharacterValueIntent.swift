// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import Foundation

/// How `ChangeCharacterValueIntent` changes a value.
enum CharacterValueChange: String, AppEnum {
    case add
    case subtract
    case set

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Change")
    }

    static var caseDisplayRepresentations: [CharacterValueChange: DisplayRepresentation] {
        [
            .add: DisplayRepresentation(title: "Add", synonyms: ["Heal", "Increase", "Raise"]),
            .subtract: DisplayRepresentation(title: "Subtract", synonyms: ["Damage", "Decrease", "Lower"]),
            .set: DisplayRepresentation(title: "Set", synonyms: ["Change To"])
        ]
    }

    func apply(_ amount: Double, to value: Double) -> Double {
        switch self {
        case .add: value + amount
        case .subtract: value - amount
        case .set: amount
        }
    }
}

/// Adds to, subtracts from or sets a number on a character sheet ("subtract 7 from the hit points
/// of Goblin"), through the same write as the sheet's quick editor: a value calculated from a
/// formula or a link keeps it and gets a modifier (`base|modifier`). On a player's device in a
/// running game the change goes to the master like a quick-editor change.
/// See CODE_AUDIT_AppIntents3 §4.5.
struct ChangeCharacterValueIntent: AppIntent {
    static let title: LocalizedStringResource = "Change Character Value"
    static let description = IntentDescription(
        "Adds to, subtracts from or sets a number on a character sheet, such as hit points. A value calculated from a formula keeps its formula.",
        categoryName: "Character",
        searchKeywords: ["hit points", "HP", "damage", "heal", "value"]
    )
    static let supportedModes: IntentModes = .background

    static var parameterSummary: some ParameterSummary {
        Switch(\.$mode) {
            Case(.add) {
                Summary("Add \(\.$amount) to \(\.$valueName) of \(\.$target)") { \.$mode }
            }
            Case(.subtract) {
                Summary("Subtract \(\.$amount) from \(\.$valueName) of \(\.$target)") { \.$mode }
            }
            DefaultCase {
                Summary("Set \(\.$valueName) of \(\.$target) to \(\.$amount)") { \.$mode }
            }
        }
    }

    @Parameter(title: "Character", requestValueDialog: .localized("Which character?", bundle: .module))
    var target: CharacterEntity

    @Parameter(
        title: "Value",
        description: "The name of a number on the sheet, such as Hit Points.",
        requestValueDialog: .localized("Which value should change?", bundle: .module),
        optionsProvider: CharacterValueNameOptions()
    )
    var valueName: String

    @Parameter(title: "Change", default: .subtract)
    var mode: CharacterValueChange

    @Parameter(title: "Amount", requestValueDialog: .localized("By how much?", bundle: .module))
    var amount: Int

    @Dependency var root: CharacterRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        try await requireReadyDatabase()
        try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which character?", bundle: .module))

        let matches = CharacterValueLookup.values(named: valueName, in: target.id, itemController: root.itemController)
        let value: CharacterValueLookup.Value
        switch matches.count {
        case 0:
            throw $valueName.needsValueError(.localized("\(target.name) has no number called \"\(valueName)\". Which value should change?", bundle: .module))
        case 1:
            value = matches[0]
        default:
            let labels = matches.map(\.label)
            let chosen = try await $valueName.requestDisambiguation(
                among: labels,
                dialog: .localized("Which \"\(valueName)\" do you mean?", bundle: .module)
            )
            value = matches[labels.firstIndex(of: chosen) ?? 0]
        }

        let edit = root.editController
        let isDecimal = value.type == .decimal
        let before = isDecimal
            ? edit.entryValueAsDecimal(itemId: value.itemId, entryId: value.entryId)
            : Double(edit.entryValueAsNumber(itemId: value.itemId, entryId: value.entryId))
        let wanted = mode.apply(Double(amount), to: before)
        if isDecimal {
            edit.updateValue(itemId: value.itemId, entryId: value.entryId, decimal: wanted)
        } else {
            edit.updateValue(itemId: value.itemId, entryId: value.entryId, number: Int(wanted.rounded()))
        }
        let after = isDecimal
            ? edit.entryValueAsDecimal(itemId: value.itemId, entryId: value.entryId)
            : Double(edit.entryValueAsNumber(itemId: value.itemId, entryId: value.entryId))

        // A player's change goes to the master, as `SheetEntryInlineEditorRowView` sends it.
        if IntentGameContext.gameModus() == .player,
           let update = edit.gameValueEntryUpdate(itemId: value.itemId, entryId: value.entryId) {
            IntentGameContext.networkActions()?.game(update, .valueUpdate, nil)
        }

        if let model = root.itemController.itemSync(for: target.id) {
            await indexIntentEntities([CharacterEntity(root: root, model: model)])
        }

        let afterText = after.formatted(.number.precision(.fractionLength(0...2)))
        let beforeText = before.formatted(.number.precision(.fractionLength(0...2)))
        return .result(
            value: after,
            dialog: .localized(
                full: "\(value.name) of \(target.name) is now \(afterText), was \(beforeText).",
                supporting: "\(value.name): \(afterText)",
                bundle: .module
            )
        )
    }
}

/// The names of the numbers on the chosen character, for the Value parameter in Shortcuts.
struct CharacterValueNameOptions: DynamicOptionsProvider {
    @IntentParameterDependency<ChangeCharacterValueIntent>(\.$target)
    var intent

    @Dependency var root: CharacterRootModel

    @MainActor
    func results() async throws -> [String] {
        guard let target = intent?.target else { return [] }
        var seen = Set<String>()
        return CharacterValueLookup.values(named: nil, in: target.id, itemController: root.itemController)
            .map(\.name)
            .filter { seen.insert($0.lowercased()).inserted }
    }
}

/// Finds the numbers of a character by name, in its own entries and in the value groups it
/// links (a group is another character item, e.g. "Attributes").
enum CharacterValueLookup {
    /// Group levels searched below the character.
    static let maximumDepth = 3

    struct Value: Equatable, Sendable {
        let itemId: UUID
        let entryId: UUID
        let name: String
        /// The group the entry is in, empty for the character itself.
        let groupName: String
        let type: ValueEntryModel.ValueType

        /// The name, with the group when there is one: "Strength (Attributes)".
        var label: String {
            groupName.isEmpty ? name : "\(name) (\(groupName))"
        }
    }

    /// Every number of the character for `nil`; else an exact (case- and diacritic-insensitive)
    /// match, or the names that contain `name` when nothing matches exactly.
    @MainActor
    static func values(named name: String?, in itemId: UUID, itemController: ItemController) -> [Value] {
        var all: [Value] = []
        var visited: Set<UUID> = []
        collect(itemId: itemId, groupName: "", depth: 0, itemController: itemController, visited: &visited, into: &all)
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return all }
        let exact = all.filter { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        return exact.isEmpty ? all.filter { $0.name.localizedStandardContains(name) } : exact
    }

    @MainActor
    private static func collect(
        itemId: UUID,
        groupName: String,
        depth: Int,
        itemController: ItemController,
        visited: inout Set<UUID>,
        into values: inout [Value]
    ) {
        guard depth <= maximumDepth, visited.insert(itemId).inserted,
              let model = itemController.itemSync(for: itemId) else { return }
        for entry in model.entries where entry.displayState != DisplayStateMask.totalHidden.rawValue {
            if let groupId = entry.valueId {
                let group = itemController.itemSync(for: groupId)?.name ?? entry.name
                collect(itemId: groupId, groupName: group, depth: depth + 1, itemController: itemController, visited: &visited, into: &values)
            } else if entry.type == .number || entry.type == .decimal {
                let name = IntentEntityText.readable(entry.name)
                guard !name.isEmpty else { continue }
                values.append(Value(itemId: itemId, entryId: entry.id, name: name, groupName: groupName, type: entry.type))
            }
        }
    }
}

#endif
