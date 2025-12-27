// @copyright André Trettin

import SwiftUI

public struct TableRootSheet<ImageContent: View>: View {
    public init(root: ItemRootController, model: SheetModel, windowMode: Bool = false, dismissAction: (() -> Void)? = nil, @ViewBuilder imageContent: @escaping (CGSize) -> ImageContent) {
        self.root = root
        self.model = model
        self.windowMode = windowMode
        self.dismissAction = dismissAction
        self.imageContent = imageContent
        self._tableSheetModel = State(wrappedValue: TableSheetModel(linkControllable: root.linkControllable, sheetModel: model))
    }
    
    public init(root: ItemRootController, model: SheetModel, windowMode: Bool = false, dismissAction: (() -> Void)? = nil) where ImageContent == EmptyView {
        self.root = root
        self.model = model
        self.windowMode = windowMode
        self.dismissAction = dismissAction
        self.imageContent = { _ in EmptyView() }
        self._tableSheetModel = State(wrappedValue: TableSheetModel(linkControllable: root.linkControllable, sheetModel: model))
    }
    
    let root: ItemRootController
    let model: SheetModel
    let windowMode: Bool
    let dismissAction: (() -> Void)?
    let imageContent: (CGSize) -> ImageContent
    
    @Environment(\.appSizeMode) private var appSizeMode
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.showGame) private var showGame
    @Environment(\.dismiss) var dismiss

    @State private var tableSheetModel: TableSheetModel
    
    public var body: some View {
        TableSheetView(root: root, model: tableSheetModel, windowMode: windowMode, dismissAction: dismissAction, imageContent: imageContent)
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
            .navigationTitle(Text(model.name))
            .onChange(of: model, initial: true) {
                resetModels()
            }
    }
    
    func resetModels() {
        withAnimation {
            tableSheetModel.resetModel(model: model)
        }
    }
}

private extension TableRootSheet {
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        if shouldShowCloseButton {
            ToolbarItem(placement: .cancellationAction) {
                closeButton
            }
        }
    }
    
    var shouldShowCloseButton: Bool {
        valueFor(iOS: (!showGame && appSizeMode == .compact) || dismissAction != nil, macOS: false, tvOS: dismissAction != nil, visionOS: dismissAction != nil)
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
