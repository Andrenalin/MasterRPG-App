// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight

struct AppendAdventureSectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Append Section to Adventure"

    static var parameterSummary: some ParameterSummary {
        Summary("Add section \(\.$sectionName) to \(\.$target)")
    }

    @Parameter(title: "Adventure", requestValueDialog: "Which adventure?")
    var target: AdventureEntity

    @Parameter(title: "Section Name", requestValueDialog: "What should the section be called?")
    var sectionName: String

    @Parameter(title: "Content")
    var content: AttributedString?

    @Dependency var root: AdventureRootModel

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let contentText = content.map { String($0.characters) } ?? ""
        let entry = root.editController.create(name: sectionName, content: contentText)
        root.editController.add(entry: entry, itemId: target.id)
        await root.itemController.save()

        if let model = root.itemController.itemSync(for: target.id) {
            let updated = AdventureEntity(root: root, model: model)
            try await CSSearchableIndex.default().indexAppEntities([updated])
        }

        return .result(dialog: "Added \"\(sectionName)\" to \"\(target.name)\".")
    }
}

#endif
