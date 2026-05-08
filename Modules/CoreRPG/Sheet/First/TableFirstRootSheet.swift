// @copyright André Trettin

import SwiftUI

enum LinkHighlightTextModeOldId: Hashable {
    case name
    case description
    case entry(String)
}


public struct TableFirstRootSheet: View {
    public init(root: ItemRootController, itemId: UUID, module: NetworkModules, configuration: ViewerConfiguration, dismissAction: (() -> Void)? = nil) {
        self.root = root
        self.configuration = configuration
        self.dismissAction = dismissAction
        self._sheetRootModel = State(wrappedValue: SheetRootModel(linkControllable: root.linkControllable, sheetControllable: root.sheetControllable, itemId: itemId, isEditor: false, editorModel: root.editControllable.sheetEditorModel))
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
        SheetRootView(root: root, rootModel: sheetRootModel)
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
            .navigationTitle(Text(sheetRootModel.sheetModel.name))
    }
}

private extension TableFirstRootSheet {
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
