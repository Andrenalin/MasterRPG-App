// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents

public struct AppendAdventureSectionIntent: AppIntent {
    public static let title: LocalizedStringResource = "Append Section to Adventure"

    public static var parameterSummary: some ParameterSummary {
        Summary("Add section \(\.$sectionName) to \(\.$target)")
    }

    @Parameter(title: "Adventure", requestValueDialog: "Which adventure?")
    var target: AdventureEntity

    @Parameter(title: "Section Name", requestValueDialog: "What should the section be called?")
    var sectionName: String

    @Parameter(title: "Content")
    var content: AttributedString?

    @Dependency var root: AdventureRootModel

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        await DatabaseReadiness.wait()
        // Shared Spotlight glue (see CODE_AUDIT §9.8) — `indexIntentEntities` already
        // guards `CSSearchableIndex.isIndexingAvailable()` internally.
        let contentText = intentPlainText(from: content)
        let entry = root.editController.create(name: sectionName, content: contentText)
        root.editController.add(entry: entry, itemId: target.id)
        await root.itemController.save()

        if let model = root.itemController.itemSync(for: target.id) {
            let updated = AdventureEntity(root: root, model: model)
            try await indexIntentEntities([updated])
        }

        return .result(dialog: "Added \"\(sectionName)\" to \"\(target.name)\".")
    }
}

#endif
