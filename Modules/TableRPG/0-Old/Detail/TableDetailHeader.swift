// @copyright André Trettin

import CoreRPG
import SwiftUI

struct TableDetailHeader: View {
    let editController: EditController
    let model: TableModel

#if os(visionOS) || os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif
    @Environment(TableRootModel.self) private var root
    @Environment(DetailHeaderModel.self) private var headerModel

    @State private var isReading = false
    
    var body: some View {
        VStack {
            Image(systemName: NetworkModules.table.icon)
                .font(.system(size: headerModel.size.height - valueFor(iOS: headerModel.topSafeAreaHeight, macOS: 16, tvOS: headerModel.topSafeAreaHeight, visionOS: headerModel.topSafeAreaHeight)))
                .frame(height: headerModel.size.height - valueFor(iOS: headerModel.topSafeAreaHeight, macOS: 16, tvOS: headerModel.topSafeAreaHeight, visionOS: headerModel.topSafeAreaHeight), alignment: .center)
                .foregroundStyle(.white)
                .opacity(0.3)
        }
        .frame(maxWidth: .infinity, alignment: .center)
//        .overlay(alignment: .center) {
//            @Bindable var model = model
//            BlurText(text: model.name, color: .teal)
//                .font(.largeTitle)
//        }
#if os(iOS)
        .toolbar {
            ToolbarItem {
                if headerModel.isInline == false {
                    overlayButton
                }
            }
        }
#else
        .overlay(alignment: .topTrailing) {
            overlayButton
            
                .padding(.trailing, valueFor(iOS: 16, macOS: 16, tvOS: 16, visionOS: 24))
        }
#endif
        .padding(.top, valueFor(iOS: headerModel.topSafeAreaHeight / 2, macOS: 0, tvOS: headerModel.topSafeAreaHeight / 2, visionOS: headerModel.topSafeAreaHeight / 2))
        .frame(height: headerModel.size.height, alignment: .center)
        .sheetFullScreen(isPresented: $isReading) {
            if isReading {
                tableSheetView
            }
        }
    }
    
    var tableSheetView: some View {
        ViewerRootView(model: editController.model, showTopImage: false, dismissAction: nil)
            .environment(root)
            .environment(\.showGame, false)
    }
    
    private var overlayButton: some View {
        ImageOverlayButton(icon: "book\(isReading ? ".fill": "")") {
#if os(visionOS) || os(macOS)
            openWindow(id: WindowIdentifier.tableViewer.rawValue, value: ItemSelection(itemId: editController.model.id, entryId: nil))
#else
            isReading.toggle()
#endif
        }
        .contentTransition(.symbolEffect(.replace.wholeSymbol))
    }
}

#Preview {
    TableDetailHeader(editController: .preview, model: .preview)
        .environment(TableRootModel.preview)
        .environment(DetailHeaderModel(size: CGSize(width: 375, height: 64), topSafeAreaHeight: 0))
}
