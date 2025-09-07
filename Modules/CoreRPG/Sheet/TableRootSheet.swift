// @copyright André Trettin

import SwiftUI

public struct TableRootSheet<ImageContent: View>: View {
    public init(linkControllable: any LinkControllable, model: SheetModel, showImage: Bool, dismissAction: (() -> Void)? = nil, @ViewBuilder imageContent: @escaping (CGSize) -> ImageContent = { _ in EmptyView() }) {
        self.model = model
        self.showImage = showImage
        self.dismissAction = dismissAction
        self.imageContent = imageContent
        self._tableSheetModel = State(wrappedValue: TableSheetModel(linkControllable: linkControllable, sheetModel: model))
    }
    
    let model: SheetModel
    let showImage: Bool
    let dismissAction: (() -> Void)?
    let imageContent: (CGSize) -> ImageContent
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var tableSheetModel: TableSheetModel
    @State private var searchText: String = ""
    
    public var body: some View {
        TableSheetView(model: tableSheetModel, showImage: showImage, dismissAction: dismissAction, imageContent: imageContent)
            .environment(\.colorScheme, colorScheme)
#if os(macOS) || os(visionOS)
            .padding(.top)
#else
            .background(colorScheme == .dark ? Color.black.ignoresSafeArea() : Color.white.ignoresSafeArea())
#endif
#if os(visionOS)
            .glassBackgroundEffect()
#endif
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
