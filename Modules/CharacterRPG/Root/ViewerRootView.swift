// @copyright André Trettin

import CoreRPG
import SwiftUI
import PhotoRPG

@MainActor
struct ViewerRootView: View {
    let model: ValueModel
    let configuration: ViewerConfiguration
    let dismissAction: (() -> Void)?

    init(
        model: ValueModel,
        configuration: ViewerConfiguration,
        dismissAction: (() -> Void)?
    ) {
        self.model = model
        self.configuration = configuration
        self.dismissAction = dismissAction
    }
    
    @Environment(CharacterRootModel.self) private var root

    @ViewBuilder
    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
#if os(tvOS)
        readerSheet
#else
        if configuration.isGame {
            readerSheet
                .characterAddEntryOverlay(root: root, itemId: model.id)
        } else {
            readerSheet
        }
#endif
    }

    @ViewBuilder
    private var readerSheet: some View {
        // The live game view reuses its module's persistent counterpart to the
        // standalone editor's `sheetRootModel` (see `SheetRootModel.syncCounterpart()`)
        // instead of building a throwaway `SheetRootModel` per character —
        // that's what lets an editor edit reach this view (and vice versa)
        // through a direct link rather than a registry, so it's deliberately
        // not `.id(model.id)`-scoped: tearing the view identity down on every
        // character switch would discard that reuse.
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
    /// player switched characters) or creates it here, seeded with the real
    /// `model.id` directly rather than a throwaway placeholder, and stores it
    /// back for the next selection/reappearance to reuse. Cleared again in
    /// `GameController.resetGameState()` when the game ends.
    ///
    /// `isGameEditor: true` — unlike a typical live game view, character edits
    /// made here (add/remove/move an entry, etc.) are meant to persist just
    /// like the standalone editor's, not stay memory-only for the session; see
    /// `SheetRootModel.persistsEdits`.
    private var gameSheetRootModel: SheetRootModel {
        if let existing = root.editController.editorModel.gameSheetRootModel {
            existing.reset(itemId: model.id)
            return existing
        }
        guard let rootManager = root.rootManager else {
            preconditionFailure("ViewerRootView requires ItemRootController.rootManager to be set before presentation.")
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

#Preview("Andrenalin", traits: .mockData) {
    ViewerRootView(model: .preview, configuration: .init(), dismissAction: nil)
}

#Preview("Mira", traits: .mockData) {
    ViewerRootView(model: .previewAllEntryTypes, configuration: .init(), dismissAction: nil)
}
