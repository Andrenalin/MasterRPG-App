// @copyright André Trettin

import SwiftUI

public struct TableRootSheet: View {
    public init(root: ItemRootController, itemId: UUID, module: NetworkModules, configuration: ViewerConfiguration, dismissAction: (() -> Void)? = nil) {
        guard let rootManager = root.rootManager else {
            preconditionFailure("TableRootSheet requires ItemRootController.rootManager to be set before presentation.")
        }

        self.root = root
        self.configuration = configuration
        self.dismissAction = dismissAction
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
}
