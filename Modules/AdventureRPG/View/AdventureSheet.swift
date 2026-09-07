// @copyright André Trettin

import CoreRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import SwiftUI

struct AdventureSheet: View {
    let model: AdventureModel
    let configuration: ViewerConfiguration
    let dismissAction: (() -> Void)?

    init(
        model: AdventureModel,
        configuration: ViewerConfiguration,
        dismissAction: (() -> Void)?
    ) {
        self.model = model
        self.configuration = configuration
        self.dismissAction = dismissAction
    }

    @Environment(AdventureRootModel.self) private var root

    @ViewBuilder
    var body: some View {
#if os(tvOS)
        ReaderSheetView(model: model, configuration: configuration, dismissAction: dismissAction)
#else
        if configuration.isGame {
            ReaderSheetView(model: model, configuration: configuration, dismissAction: dismissAction)
                .sheetAIAssistant(
                    generatorRoot: root.generatorRoot,
                    rootModel: gameSheetRootModel,
                    module: root.configurable.module
                )
        } else {
            ReaderSheetView(model: model, configuration: configuration, dismissAction: dismissAction)
        }
#endif
    }

    /// The live game view's persistent sheet slot (`ItemEditorModel.gameSheetRootModel`)
    /// — only ever needed, and so only ever created, while an actual game view
    /// is on screen. Reuses the stored instance (moving it to `model.id` if the
    /// player switched selection) or creates it here, seeded with the real
    /// `model.id` directly rather than a throwaway placeholder, and stores it
    /// back for the next selection/reappearance to reuse. Cleared again in
    /// `GameController.resetGameState()` when the game ends.
    ///
    /// `isGameEditor: true` — unlike a typical live game view, Adventure edits
    /// made here are meant to persist just like the standalone editor's, not
    /// stay memory-only for the session; see `SheetRootModel.persistsEdits`.
    private var gameSheetRootModel: SheetRootModel {
        if let existing = root.editController.editorModel.gameSheetRootModel {
            existing.reset(itemId: model.id)
            return existing
        }
        guard let rootManager = root.rootManager else {
            preconditionFailure("AdventureSheet requires ItemRootController.rootManager to be set before presentation.")
        }
        let created = SheetRootModel(
            rootManager: rootManager,
            linkControllable: root.rootController.linkControllable,
            sheetControllable: root.rootController.sheetControllable,
            itemId: model.id,
            isEditor: false,
            isGameEditor: true
        )
        root.editController.editorModel.gameSheetRootModel = created
        return created
    }
}

private struct ReaderSheetView: View {
    let model: AdventureModel
    let configuration: ViewerConfiguration
    let dismissAction: (() -> Void)?

    @Environment(AdventureRootModel.self) private var root

    // The live game view reuses the module's persistent counterpart to the
    // standalone editor's `sheetRootModel` (see `SheetRootModel.syncCounterpart()`)
    // instead of building a throwaway `SheetRootModel` per item — that's
    // what lets an editor edit reach this view (and vice versa) through a
    // direct link rather than a registry, so it's deliberately not
    // `.id(model.id)`-scoped: tearing the view identity down on every
    // selection would discard that reuse.
    var body: some View {
        if configuration.isGame {
            TableRootSheet(
                root: root.rootController,
                itemId: model.id,
                module: root.config.module,
                configuration: configuration,
                dismissAction: dismissAction,
                externalSheetRootModel: gameSheetRootModel
            )
        } else {
            TableRootSheet(
                root: root.rootController,
                itemId: model.id,
                module: root.config.module,
                configuration: configuration,
                dismissAction: dismissAction
            )
            .id(model.id)
        }
    }

    /// The live game view's persistent sheet slot (`ItemEditorModel.gameSheetRootModel`)
    /// — only ever needed, and so only ever created, while an actual game view
    /// is on screen. Reuses the stored instance (moving it to `model.id` if the
    /// player switched selection) or creates it here, seeded with the real
    /// `model.id` directly rather than a throwaway placeholder, and stores it
    /// back for the next selection/reappearance to reuse. Cleared again in
    /// `GameController.resetGameState()` when the game ends.
    ///
    /// `isGameEditor: true` — unlike a typical live game view, Adventure edits
    /// made here are meant to persist just like the standalone editor's, not
    /// stay memory-only for the session; see `SheetRootModel.persistsEdits`.
    private var gameSheetRootModel: SheetRootModel {
        if let existing = root.editController.editorModel.gameSheetRootModel {
            existing.reset(itemId: model.id)
            return existing
        }
        guard let rootManager = root.rootManager else {
            preconditionFailure("AdventureSheet requires ItemRootController.rootManager to be set before presentation.")
        }
        let created = SheetRootModel(
            rootManager: rootManager,
            linkControllable: root.rootController.linkControllable,
            sheetControllable: root.rootController.sheetControllable,
            itemId: model.id,
            isEditor: false,
            isGameEditor: true
        )
        root.editController.editorModel.gameSheetRootModel = created
        return created
    }
}

#Preview("Reader Mode", traits: .mockData) {
    AdventureSheet(model: .preview, configuration: .init(), dismissAction: nil)
}

#Preview("Game Mode", traits: .mockData) {
    AdventureSheet(model: .preview, configuration: .init(isGame: true), dismissAction: nil)
}
