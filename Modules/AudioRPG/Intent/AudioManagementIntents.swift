// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreSpotlight
import CoreRPG
import Foundation

struct CreateAudioIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Audio"
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    static var parameterSummary: some ParameterSummary {
        Summary("Create audio named \(\.$name)")
    }

    @Parameter(title: "Name", requestValueDialog: "What should the audio be called?")
    var name: String

    @Parameter(title: "Description")
    var details: AttributedString?

    @Parameter(title: "Open When Created", default: false)
    var openWhenCreated: Bool

    @Dependency var root: AudioRootModel
    @Dependency var navigator: Navigator

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<AudioEntity> & ProvidesDialog {
        await DatabaseReadiness.wait()
        // Siri and Shortcuts can pass an empty name: ask again instead of creating a blank item.
        // See CODE_AUDIT_AppIntents §5.2.
        let trimmedName = try requiredIntentName(name, parameter: $name, prompt: "What should the audio be called?")
        let model = AudioModel(
            id: UUID(),
            name: trimmedName,
            description: intentPlainText(from: details)
        )
        root.itemController.replace(model: model, isInsert: true)
        await root.itemController.save()

        let entity = AudioEntity(root: root, model: model)
        try await indexIntentEntities([entity])

        if openWhenCreated {
            await navigator.perform(route: KnownRoutes.audios(model.id, nil))
            try await continueInForeground(alwaysConfirm: false)
        }

        return .result(value: entity, dialog: "Created \"\(trimmedName)\".")
    }
}

struct AddAudioNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Audio Note"

    static var parameterSummary: some ParameterSummary {
        Summary("Add note to \(\.$target)")
    }

    @Parameter(title: "Audio", requestValueDialog: "Which audio?")
    var target: AudioEntity

    @Parameter(title: "Note", requestValueDialog: "What note should be added?")
    var note: AttributedString

    @Dependency var root: AudioRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await DatabaseReadiness.wait()
        // `target` can be deleted since Siri or Shortcuts cached it. See CODE_AUDIT_AppIntents §5.2.
        let targetModel = try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: "Which audio?")
        let currentDescription = targetModel.description
        let updatedDescription = appendingIntentText(
            String(note.characters),
            to: currentDescription
        )
        guard updatedDescription != currentDescription else {
            return .result(dialog: "No note added.")
        }

        root.editController.reset(description: updatedDescription, itemId: target.id)
        await root.itemController.save()

        if let model = root.itemController.itemSync(for: target.id) {
            try await indexIntentEntities([AudioEntity(root: root, model: model)])
        }

        return .result(dialog: "Added note to \"\(target.name)\".")
    }
}

@AppIntent(schema: .system.search)
struct SearchAudioIntent: ShowInAppSearchResultsIntent {
    static let title: LocalizedStringResource = "Search Audio"
    static let searchScopes: [StringSearchScope] = [.general]

    var criteria: StringSearchCriteria

    @Dependency var root: AudioRootModel
    @Dependency var navigator: Navigator

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await DatabaseReadiness.wait()
        root.searchModel.searchText = criteria.term
        await navigator.perform(route: KnownRoutes.audios(nil, nil))
        return .result()
    }
}

struct DeleteAudioIntent: DeleteIntent {
    static let title: LocalizedStringResource = "Delete Audio"

    @Parameter(title: "Audio")
    var entities: [AudioEntity]

    @Dependency var root: AudioRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await DatabaseReadiness.wait()
        let ids = entities.map(\.id)

        await trashIntentItems(ids: ids, ofType: AudioEntity.self, in: root)

        let count = entities.count
        let message = AttributedString(
            localized: "Deleted ^[\(count) audio item](inflect: true).",
            bundle: .module
        )
        return .result(dialog: "\(message)")
    }
}

#if os(iOS)
extension SearchAudioIntent: TargetContentProvidingIntent {}
#endif

#endif
