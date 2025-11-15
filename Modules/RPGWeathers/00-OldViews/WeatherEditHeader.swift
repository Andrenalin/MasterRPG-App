// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct WeatherEditHeader: View {
    let editController: EditController

#if os(visionOS) || os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif
    @Environment(WeatherRootModel.self) private var root
    @Environment(DetailHeaderModel.self) private var headerModel

    @State private var isReading = false

    var body: some View {
        WeatherViewer(model: editController.model, size: headerModel.size, useGame: headerModel.isInline)
#if os(iOS)
            .toolbar {
                ToolbarItem {
                    if headerModel.isInline == false {
                        overlayBautton
                    }
                }
            }
#else
            .overlay(alignment: .topTrailing) {
                overlayBautton
                    .padding([.top, .trailing])
            }
#endif
            .sheetFullScreen(isPresented: $isReading) {
                root.viewController.weatherWindow(root: root, selection: ItemSelection(itemId: editController.model.id, entryId: nil))
            }
    }

    private var overlayBautton: some View {
        ImageOverlayButton(icon: "book\(isReading ? ".fill": "")") {
#if os(visionOS) || os(macOS)
            openWindow(id: WindowIdentifier.weatherViewer.rawValue, value: ItemSelection(itemId: editController.model.id, entryId: nil))
#else
            isReading.toggle()
#endif
        }
        .contentTransition(.symbolEffect(.replace.wholeSymbol))
    }
}

#Preview {
    WeatherEditHeader(editController: .preview)
        .environment(WeatherRootModel.preview)
        .environment(DetailHeaderModel(size: CGSize(width: 375, height: 375), isInline: false))
}
