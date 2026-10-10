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
        ReaderSheetView(model: model, configuration: configuration, dismissAction: dismissAction)
#else
        if configuration.isGame {
            ReaderSheetView(model: model, configuration: configuration, dismissAction: dismissAction)
                .characterAddEntryOverlay(root: root, itemId: model.id)
        } else {
            ReaderSheetView(model: model, configuration: configuration, dismissAction: dismissAction)
        }
#endif
    }
}

@MainActor
private struct ReaderSheetView: View {
    let model: ValueModel
    let configuration: ViewerConfiguration
    let dismissAction: (() -> Void)?

    @Environment(CharacterRootModel.self) private var root

    /// Local read-only mirror of `ItemEditorModel.gameSheetRootModel`, resolved
    /// from the `.onChange(of: model.id, initial: true)` lifecycle hook below
    /// rather than as a side effect of a `body`-read computed property — see
    /// CODE_AUDIT_Character §8.3. `body` only ever reads this; it never mutates
    /// observable state itself.
    @State private var resolvedGameSheetRootModel: SheetRootModel?

    // The live game view reuses its module's persistent counterpart to the
    // standalone editor's `sheetRootModel` (see `SheetRootModel.syncCounterpart()`)
    // instead of building a throwaway `SheetRootModel` per character —
    // that's what lets an editor edit reach this view (and vice versa)
    // through a direct link rather than a registry, so it's deliberately
    // not `.id(model.id)`-scoped: tearing the view identity down on every
    // character switch would discard that reuse.
    var body: some View {
        Group {
            if configuration.isGame {
                // `CharacterRootModel.startGameSheetRootModel(itemId:)` already
                // resolves this at game join (see `GameController.startGame(for:)`),
                // so the common case reads it here on the very first render — the
                // `onChange` below only still needs to run where this view appears
                // outside that flow (a proxy), or the player switches
                // characters. A plain read of an existing `@Observable` value is
                // not a body-mutation, unlike the removed computed property this
                // replaced — see CODE_AUDIT_Character §8.3.
                if let sheetRootModel = resolvedGameSheetRootModel ?? root.editController.editorModel.gameSheetRootModel {
                    TableRootSheet(
                        root: root.rootController,
                        itemId: model.id,
                        module: root.config.module,
                        configuration: configuration,
                        dismissAction: dismissAction,
                        externalSheetRootModel: sheetRootModel
                    )
                } else {
                    // A `Group` without content has no view to carry the `onChange`
                    // below, so it never ran and the panel stayed empty whenever the
                    // character arrives after game join (a proxy on Apple TV gets it
                    // from its host player, so `startGame(for:)` had none to resolve).
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
        .onChange(of: model.id, initial: true) {
            guard configuration.isGame else { return }
            resolveGameSheetRootModel()
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
    private func resolveGameSheetRootModel() {
        if let existing = root.editController.editorModel.gameSheetRootModel {
            existing.reset(itemId: model.id)
            resolvedGameSheetRootModel = existing
            return
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
        resolvedGameSheetRootModel = created
    }
}

#Preview("Andrenalin", traits: .mockData) {
    ViewerRootView(model: .preview, configuration: .init(), dismissAction: nil)
}

#Preview("Mira", traits: .mockData) {
    ViewerRootView(model: .previewAllEntryTypes, configuration: .init(), dismissAction: nil)
}
