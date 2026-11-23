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
        self.itemId = itemId
        self.configuration = configuration
        self.dismissAction = dismissAction
        self.externalSheetRootModel = externalSheetRootModel
    }

    let root: ItemRootController
    let itemId: UUID
    let configuration: ViewerConfiguration
    let dismissAction: (() -> Void)?
    let externalSheetRootModel: SheetRootModel?

    /// The model this view owns when no external one is passed. It is built in `.task` and not
    /// in `init`: `@State` keeps only the first value, but `init` runs on every parent update,
    /// and building the model projects the whole item tree each time. See CODE_AUDIT_26 §7.6.
    @State private var ownedSheetRootModel: SheetRootModel?
    @State private var generationSelection: WindowItemSelection?

    private var sheetRootModel: SheetRootModel? {
        externalSheetRootModel ?? ownedSheetRootModel
    }

    public var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        Group {
            if let sheetRootModel {
                TableRootSheetContent(
                    root: root,
                    configuration: configuration,
                    dismissAction: dismissAction,
                    sheetRootModel: sheetRootModel,
                    generationSelection: $generationSelection
                )
            } else {
                // Until the model exists, or when the root manager is not set yet.
                Color.clear.themedSurface()
            }
        }
        .task(id: itemId) {
            guard externalSheetRootModel == nil, ownedSheetRootModel == nil,
                  let rootManager = root.rootManager else { return }
            ownedSheetRootModel = SheetRootModel(
                rootManager: rootManager,
                linkControllable: root.linkControllable,
                sheetControllable: root.sheetControllable,
                itemId: itemId,
                isEditor: false
            )
        }
    }
}

private struct TableRootSheetContent: View {
    let root: ItemRootController
    let configuration: ViewerConfiguration
    let dismissAction: (() -> Void)?
    let sheetRootModel: SheetRootModel
    @Binding var generationSelection: WindowItemSelection?

    @Environment(AppWindowSizeModel.self) private var appSizeModel
    @Environment(AppGameStateModel.self) private var appGameStateModel

    var body: some View {

        // The Apple TV game view is a display for the table: no search field there.
        TableSheetView(root: root, model: sheetRootModel, addSearchable: valueFor(iOS: true, macOS: configuration.addToolbar, tvOS: !configuration.isGame, visionOS: true))
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
            .applyIf(!configuration.isGame || configuration.isWindow) {
                $0.navigationTitle(Text(verbatim: sheetRootModel.sheetModel.name))
            }
            .navigationVisibility(true)
            .itemGenerationPresentation(
                root: generationRoot,
                selection: $generationSelection
            )
    }
}

private extension TableRootSheetContent {
    /// A Table opened from another module's sheet (a table link in a Map entry) generates through
    /// the Table module's root, since this sheet's own module has no generator.
    var generationRoot: ItemRootController {
        guard root.generationControllable == nil else { return root }
        return sheetRootModel.rootController(for: .table) ?? root
    }
}

private extension TableRootSheetContent {
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        if configuration.closeButton {
            ToolbarItem(placement: .cancellationAction) {
                TableRootSheetCloseButton(dismissAction: dismissAction)
            }
        }
    }
}

private struct TableRootSheetCloseButton: View {
    let dismissAction: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            if let dismissAction {
                dismissAction()
            } else {
                dismiss()
            }
        } label: {
            // A `Label` with the title hidden, so the title is the accessibility label.
            // See CODE_AUDIT_26 §8.6.
            Label {
                Text("Close", bundle: .module)
            } icon: {
                Image(systemName: "xmark.circle")
            }
            .labelStyle(.iconOnly)
        }
    }
}

#Preview {
    TableRootSheet(root: ItemRootController.fake, itemId: SheetRootModel.fake.sheetModel.id, module: .none, configuration: .init())
        .environment(AppWindowSizeModel())
        .environment(AppGameStateModel())
        .environment(AppFocusModel())
        .environment(ScenesManager())
        .environment(SearchBarVisibleModel())
}
