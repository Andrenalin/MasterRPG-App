// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreSpotlight
import CoreRPG
import Foundation

struct CreateSpaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Create 3D Object"
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    static var parameterSummary: some ParameterSummary {
        Summary("Create 3D object named \(\.$name)")
    }

    @Parameter(title: "Name", requestValueDialog: "What should the 3D object be called?")
    var name: String

    @Parameter(title: "Description")
    var details: AttributedString?

    @Parameter(title: "Open When Created", default: false)
    var openWhenCreated: Bool

    @Dependency var root: SpaceRootModel
    @Dependency var navigator: Navigator

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<SpaceEntity> & ProvidesDialog {
        await DatabaseReadiness.wait()
        // Siri and Shortcuts can pass an empty name: ask again instead of creating a blank item.
        // See CODE_AUDIT_AppIntents §5.2.
        let trimmedName = try requiredIntentName(name, parameter: $name, prompt: "What should the 3D object be called?")
        let model = SpaceModel(
            id: UUID(),
            name: trimmedName,
            description: intentPlainText(from: details),
            displayState: 0
        )
        root.itemController.replace(model: model, isInsert: true)
        await root.itemController.save()

        let entity = SpaceEntity(root: root, model: model)
        // A Spotlight-indexing hiccup shouldn't override an already-committed data mutation
        // as a failed intent — see CODE_AUDIT_Space §5.5.
        try? await indexIntentEntities([entity])

        if openWhenCreated {
            await navigator.perform(route: KnownRoutes.spaces(model.id, nil))
            try await continueInForeground(alwaysConfirm: false)
        }

        return .result(value: entity, dialog: "Created \"\(trimmedName)\".")
    }
}

struct AddSpaceNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Add 3D Object Note"

    static var parameterSummary: some ParameterSummary {
        Summary("Add note to \(\.$target)")
    }

    @Parameter(title: "3D Object", requestValueDialog: "Which 3D object?")
    var target: SpaceEntity

    @Parameter(title: "Note", requestValueDialog: "What note should be added?")
    var note: AttributedString

    @Dependency var root: SpaceRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await DatabaseReadiness.wait()
        // `target` can be deleted since Siri or Shortcuts cached it. See CODE_AUDIT_AppIntents §5.2.
        let targetModel = try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: "Which 3D object?")
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
            // See CODE_AUDIT_Space §5.5.
            try? await indexIntentEntities([SpaceEntity(root: root, model: model)])
        }

        return .result(dialog: "Added note to \"\(target.name)\".")
    }
}

@AppIntent(schema: .system.search)
struct SearchSpacesIntent: ShowInAppSearchResultsIntent {
    static let title: LocalizedStringResource = "Search 3D Objects"
    static let searchScopes: [StringSearchScope] = [.general]

    var criteria: StringSearchCriteria

    @Dependency var root: SpaceRootModel
    @Dependency var navigator: Navigator

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await DatabaseReadiness.wait()
        root.searchModel.searchText = criteria.term
        await navigator.perform(route: KnownRoutes.spaces(nil, nil))
        return .result()
    }
}

struct DeleteSpaceIntent: DeleteIntent {
    static let title: LocalizedStringResource = "Delete 3D Object"

    @Parameter(title: "3D Objects")
    var entities: [SpaceEntity]

    @Dependency var root: SpaceRootModel

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await DatabaseReadiness.wait()
        let ids = entities.map(\.id)

        await trashIntentItems(ids: ids, ofType: SpaceEntity.self, in: root)

        let count = entities.count
        let message = AttributedString(
            localized: "Deleted ^[\(count) 3D object](inflect: true).",
            bundle: .module
        )
        return .result(dialog: "\(message)")
    }
}

#if os(iOS)
extension SearchSpacesIntent: TargetContentProvidingIntent {}
#endif

#endif
