// @copyright André Trettin

import SwiftUI

public struct TableRootSheet: View {
    public init(root: ItemRootController, itemId: UUID, module: NetworkModules, configuration: ViewerConfiguration, dismissAction: (() -> Void)? = nil) {
        self.root = root
        self.configuration = configuration
        self.dismissAction = dismissAction
        let model = root.itemControllable.itemOrEmpty(for: itemId)
        self._tableSheetModel = State(wrappedValue: TableFirstSheetModel(linkControllable: root.linkControllable.rootLinkControllable, parent: nil, model: model, level: 0, module: module))
    }
        
    let root: ItemRootController
    let configuration: ViewerConfiguration
    let dismissAction: (() -> Void)?

    @Environment(AppWindowSizeModel.self) private var appSizeModel
    @Environment(AppGameStateModel.self) private var appGameStateModel

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) var dismiss

    @State private var tableSheetModel: TableFirstSheetModel
    
    public var body: some View {
        TableSheetView(root: root, model: tableSheetModel)
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
            .navigationTitle(Text(tableSheetModel.sheetModel.name))
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
    }
}
