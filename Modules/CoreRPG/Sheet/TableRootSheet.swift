// @copyright André Trettin

import SwiftUI

public struct TableRootSheet<ImageContent: View>: View {
    public init(linkController: LinkRootController, model: SheetModel, searchModel: SearchModel, showImage: Bool, dismissAction: (() -> Void)? = nil, @ViewBuilder imageContent: @escaping (CGSize) -> ImageContent = { _ in EmptyView() }) {
        self.model = model
        self.showImage = showImage
        self.dismissAction = dismissAction
        self.imageContent = imageContent
        self._tableSheetModel = State(wrappedValue: TableSheetModel(linkController: linkController, sheetModel: model, searchModel: searchModel))
    }
    
    let model: SheetModel
    let showImage: Bool
    let dismissAction: (() -> Void)?
    let imageContent: (CGSize) -> ImageContent
    
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
