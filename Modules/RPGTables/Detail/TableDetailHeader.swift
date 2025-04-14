// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct TableDetailHeader: View {
    let editController: EditController
    let model: TableModel
    let size: CGSize
    let topMargin: CGFloat
    let inline: Bool
    
#if os(visionOS) || os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif
    @Environment(TableRoot.self) private var root
    
    @State private var isReading = false
    
    var body: some View {
        VStack {
            Image(systemName: NetworkModules.table.icon)
                .font(.system(size: size.height - valueFor(iOS: topMargin, macOS: 16, tvOS: topMargin, visionOS: topMargin)))
                .frame(height: size.height - valueFor(iOS: topMargin, macOS: 16, tvOS: topMargin, visionOS: topMargin), alignment: .center)
                .foregroundStyle(.white)
                .opacity(0.3)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .overlay(alignment: .center) {
            @Bindable var model = model
            BlurText(text: model.name, color: .teal)
                .font(.largeTitle)
        }
#if os(iOS)
        .toolbar {
            ToolbarItem {
                if inline == false {
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
        .padding(.top, valueFor(iOS: topMargin / 2, macOS: 0, tvOS: topMargin / 2, visionOS: topMargin / 2))
        .frame(height: size.height, alignment: .center)
        .sheetFullScreen(isPresented: $isReading) {
            if isReading {
                tableSheetView
            }
        }
    }
    
    var tableSheetView: some View {
        TableSheet(model: editController.model, showTopImage: false, dismissAction: nil)
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
    TableDetailHeader(editController: .preview, model: .preview, size: CGSize(width: 320, height: 600), topMargin: 64, inline: false)
        .environment(TableRoot.preview)
    
}
