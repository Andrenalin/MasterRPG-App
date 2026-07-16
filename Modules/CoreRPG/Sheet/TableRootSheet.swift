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
        self._sheetRootModel = State(wrappedValue: SheetRootModel(rootManager: rootManager, linkControllable: root.linkControllable, sheetControllable: root.sheetControllable, itemId: itemId, isEditor: false))
    }
        
    let root: ItemRootController
    let configuration: ViewerConfiguration
    let dismissAction: (() -> Void)?

    @Environment(AppWindowSizeModel.self) private var appSizeModel
    @Environment(AppGameStateModel.self) private var appGameStateModel

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) var dismiss

    @State private var sheetRootModel: SheetRootModel
    
    public var body: some View {
        TableSheetView(root: root, model: sheetRootModel, addSearchable: configuration.addToolbar)
#if os(macOS) || os(visionOS)
            .padding(.top)
#else
            .background(colorScheme == .dark ? Color.black.ignoresSafeArea() : Color.white.ignoresSafeArea())
#endif
#if os(visionOS)
            .glassBackgroundEffect()
#endif
            .toolbar {
                toolbarContent
            }
            .navigationTitle(Text(verbatim: sheetRootModel.sheetModel.name))
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
    TableRootSheet(root: ItemRootController.fake, itemId: UUID(), module: .none, configuration: .init())
}
