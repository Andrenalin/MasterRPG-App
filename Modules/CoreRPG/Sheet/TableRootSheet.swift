// @copyright André Trettin

import SwiftUI

public struct TableRootSheet: View {
    /// - Parameter externalSheetRootModel: an already-constructed, externally
    ///   owned `SheetRootModel` to render instead of building a throwaway one
    ///   (e.g. `ItemEditorModel.gameSheetRootModel`, the live game view's
    ///   persistent counterpart to the standalone editor's `sheetRootModel` —
    ///   see `SheetRootModel.syncCounterpart()`). The caller is responsible for
    ///   keeping it pointed at `itemId` (typically via `.onChange(of: itemId,
    ///   initial: true) { externalSheetRootModel.reset(itemId:) }`, mirroring
    ///   `DetailEditorView`'s existing pattern for the editor's own singleton)
    ///   — this initializer does not reset it, since `@State`'s persisted
    ///   storage only honors `wrappedValue` on a view identity's first
    ///   appearance, and this view is deliberately not `.id()`-scoped to
    ///   `itemId` when reusing a persistent model (unlike the throwaway case
    ///   below), so `init` runs again on every selection without a fresh
    ///   identity to reinitialize `@State` from.
    public init(
        root: ItemRootController,
        itemId: UUID,
        module: NetworkModules,
        configuration: ViewerConfiguration,
        dismissAction: (() -> Void)? = nil,
        externalSheetRootModel: SheetRootModel? = nil
    ) {
        self.root = root
        self.configuration = configuration
        self.dismissAction = dismissAction
        if let externalSheetRootModel {
            self._sheetRootModel = State(wrappedValue: externalSheetRootModel)
        } else {
            guard let rootManager = root.rootManager else {
                preconditionFailure("TableRootSheet requires ItemRootController.rootManager to be set before presentation.")
            }
            self._sheetRootModel = State(
                wrappedValue: SheetRootModel(
                    rootManager: rootManager,
                    linkControllable: root.linkControllable,
                    sheetControllable: root.sheetControllable,
                    itemId: itemId,
                    isEditor: false
                )
            )
        }
    }

    let root: ItemRootController
    let configuration: ViewerConfiguration
    let dismissAction: (() -> Void)?

    @Environment(AppWindowSizeModel.self) private var appSizeModel
    @Environment(AppGameStateModel.self) private var appGameStateModel

    @Environment(\.dismiss) var dismiss

    @State private var sheetRootModel: SheetRootModel    
    @State private var generationSelection: WindowItemSelection?
    
    public var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        
        @Bindable var sheetRootModel = sheetRootModel

        TableSheetView(root: root, model: sheetRootModel, addSearchable: valueFor(iOS: true, macOS: configuration.addToolbar, tvOS: true, visionOS: true))
#if os(macOS) || os(visionOS)
            .padding(.top)
#endif
            .themedSurface()
#if os(visionOS)
            .glassBackgroundEffect()
#endif
            .toolbar {
                toolbarContent
            }
            .applyIf(!configuration.isGame) {
                $0.navigationTitle(Text(verbatim: sheetRootModel.sheetModel.name))
            }
            .navigationVisibility(true)
            .itemGenerationPresentation(
                root: root,
                selection: $generationSelection
            )
    }
}

private extension TableRootSheet {
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        if configuration.closeButton {
            ToolbarItem(placement: .cancellationAction) {
                closeButton
            }
        }
    }

    var closeButton: some View {
        Button {
            if let dismissAction {
                dismissAction()
            } else {
                dismiss()
            }
        } label: {
            Image(systemName: "xmark.circle")
        }
        .accessibilityLabel(Text("Close", bundle: .module))
    }
}

#Preview {
    TableRootSheet(root: ItemRootController.fake, itemId: SheetRootModel.fake.sheetModel.id, module: .none, configuration: .init())
        .environment(AppWindowSizeModel())
        .environment(AppGameStateModel())
        .environment(ScenesManager())
        .environment(SearchBarVisibleModel())
}
