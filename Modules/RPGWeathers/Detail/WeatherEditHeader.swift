// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct WeatherEditHeader: View {
    let editController: EditController
    let size: CGSize
    let topMargin: CGFloat
    let inline: Bool
    
#if os(visionOS) || os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif
    @Environment(WeatherRoot.self) private var root

    @State private var isReading = false

    var body: some View {
        WeatherViewer(model: editController.model, size: size, useGame: inline)
#if os(iOS)
            .toolbar {
                ToolbarItem {
                    if inline == false {
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
                root.viewController.weatherWindow(selection: ItemSelection(itemId: editController.model.id, entryId: nil))
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
    WeatherEditHeader(editController: .preview, size: CGSize(width: 375, height: 375), topMargin: 64, inline: false)
        .environment(WeatherRoot.preview)
}
