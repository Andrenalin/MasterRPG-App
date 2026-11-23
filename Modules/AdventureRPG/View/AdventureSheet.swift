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

    /// The game view's sheet model, resolved in `onChange` and only read by `body`: resolving it
    /// in `body` wrote observable state during the view update, twice per pass.
    /// See CODE_AUDIT_28 §8.1 and the Character twin.
    @State private var resolvedGameSheetRootModel: SheetRootModel?

    var body: some View {
        Group {
#if os(tvOS)
            ReaderSheetView(model: model, configuration: configuration, dismissAction: dismissAction, gameSheetRootModel: nil)
#else
            if configuration.isGame {
                ReaderSheetView(model: model, configuration: configuration, dismissAction: dismissAction, gameSheetRootModel: currentGameSheetRootModel)
                    .sheetAIAssistant(
                        generatorRoot: root.generatorRoot,
                        rootModel: currentGameSheetRootModel,
                        module: root.configurable.module
                    )
            } else {
                ReaderSheetView(model: model, configuration: configuration, dismissAction: dismissAction, gameSheetRootModel: nil)
            }
#endif
        }
        .onChange(of: model.id, initial: true) {
            resolveGameSheetRootModel()
        }
        // A window turns into the game view when a game starts while it is open.
        .onChange(of: configuration.isGame) {
            resolveGameSheetRootModel()
        }
    }

    private func resolveGameSheetRootModel() {
        guard configuration.isGame else { return }
        resolvedGameSheetRootModel = root.resolveGameSheetRootModel(for: model.id)
    }

    /// A plain read: the model resolved for this selection, or the stored one on the first render.
    private var currentGameSheetRootModel: SheetRootModel? {
        resolvedGameSheetRootModel ?? root.editController.editorModel.gameSheetRootModel
    }
}

private struct ReaderSheetView: View {
    let model: AdventureModel
    let configuration: ViewerConfiguration
    let dismissAction: (() -> Void)?
    let gameSheetRootModel: SheetRootModel?

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
            if let gameSheetRootModel {
                TableRootSheet(
                    root: root.rootController,
                    itemId: model.id,
                    module: root.config.module,
                    configuration: configuration,
                    dismissAction: dismissAction,
                    externalSheetRootModel: gameSheetRootModel
                )
            } else {
                // The model is resolved after the first render when none was stored yet.
                Color.clear
            }
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
}

#Preview("Reader Mode", traits: .mockData) {
    AdventureSheet(model: .preview, configuration: .init(), dismissAction: nil)
        .environment(AppFocusModel())
}

#Preview("Game Mode", traits: .mockData) {
    AdventureSheet(model: .preview, configuration: .init(isGame: true), dismissAction: nil)
        .environment(AppFocusModel())
}
