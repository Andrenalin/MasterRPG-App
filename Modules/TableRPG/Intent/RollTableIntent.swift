// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import Foundation

/// Rolls on a random table the way "Auto Roll" does, nested tables included, and says the
/// result. The roll is never shared with the players: the game master decides what they learn.
/// See CODE_AUDIT_AppIntents3 §4.7.
struct RollTableIntent: AppIntent {
    static let title: LocalizedStringResource = "Roll on Table"
    static let description = IntentDescription(
        "Rolls on a random table, including the tables it links to, and says the result. The result is not shared with the players.",
        categoryName: "Table",
        searchKeywords: ["random table", "encounter", "loot", "generate"]
    )
    static let supportedModes: IntentModes = .background

    static var parameterSummary: some ParameterSummary {
        Summary("Roll on \(\.$target)")
    }

    @Parameter(title: "Table", requestValueDialog: .localized("Which table do you want to roll on?", bundle: .module))
    var target: TableEntity

    @Dependency var root: TableRootModel

    init() {}

    init(target: TableEntity) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        try await requireReadyDatabase()
        // `target` can be deleted since Siri or Shortcuts cached it. See CODE_AUDIT_AppIntents §5.2.
        try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which table do you want to roll on?", bundle: .module))
        let model = root.generationController.makeModel(itemId: target.id)
        root.generationController.autoRoll(model: model, donates: false)

        let lines = TableRollText.lines(for: model.root)
        guard !lines.isEmpty else {
            let message = model.errorMessage ?? String(localized: "\(target.name) has no entries.", bundle: .module)
            return .result(value: "", dialog: "\(message)")
        }
        let text = lines.joined(separator: "\n")
        let spoken = TableRollText.spoken(lines)
        return .result(value: text, dialog: .localized("\(target.name): \(spoken)", bundle: .module))
    }
}

/// The result of a table roll as text: one line per rolled table, "table: entry — text", nested
/// tables after the entry that links them. Links become their labels.
enum TableRollText {
    /// Characters Siri reads at most; the full text is the intent's value.
    static let spokenLimit = 600

    @MainActor
    static func lines(for occurrence: TableGenerationOccurrence) -> [String] {
        var lines: [String] = []
        append(occurrence, to: &lines)
        return lines
    }

    @MainActor
    private static func append(_ occurrence: TableGenerationOccurrence, to lines: inout [String]) {
        for entry in occurrence.selectedEntries {
            let name = IntentEntityText.readable(entry.name)
            let content = IntentEntityText.readable(entry.content)
            let result = content.isEmpty || content == name ? name : "\(name) — \(content)"
            lines.append(occurrence.depth == 0 ? result : "\(occurrence.tableName): \(result)")
        }
        for child in occurrence.children {
            append(child, to: &lines)
        }
    }

    static func spoken(_ lines: [String]) -> String {
        let text = lines.joined(separator: ". ")
        guard text.count > spokenLimit else { return text }
        return String(text.prefix(spokenLimit)) + "…"
    }
}

extension TableRootModel {
    /// Donates an "Auto Roll" the user made in the app, so Siri learns which tables are rolled
    /// at the table. Throttled per table like dice rolls. See CODE_AUDIT_AppIntents3 §4.7.
    @MainActor
    func donateRoll(of itemId: UUID) {
        Task {
            await IntentDonations.donateThrottled(for: itemId) {
                guard let model = itemController.itemSync(for: itemId) else { return nil }
                return RollTableIntent(target: TableEntity(root: self, model: model))
            }
        }
    }
}

#endif
