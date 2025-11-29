// @copyright André Trettin

import CoreRPG
import SwiftUI

struct EntryRow: View {
    let item: ItemRowTreeModel
    let isSelected: Bool

    @Environment(WeatherRootModel.self) private var root

#if os(visionOS) || os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif

    @State private var showItem: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ImageOverlayButton(icon: root.itemController.itemDataModel.networkModule.icon) {
#if os(visionOS) || os(macOS)
                openWindow(id: WindowIdentifier.pdfViewer.rawValue, value: ItemSelection(itemId: item.model.itemId, entryId: item.model.entryId))
#else
                withAnimation { showItem.toggle() }
#endif
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .sheetFullScreen(isPresented: $showItem) {
                root.viewController.weatherWindow(root: root, selection: ItemSelection(itemId: item.model.itemId, entryId: item.model.entryId))
                    .environment(\.showGame, false)
            }

            GeometryReader { geometry in
                WeatherViewer(model: root.itemController.itemOrEmpty(for: item.model.itemId), size: geometry.size, useGame: false, isAnimating: .constant(true))
            }
            .frame(height: 250)
        }
    }
}

#Preview {
    EntryRow(item: .preview, isSelected: true)
        .environment(WeatherRootModel.preview)
}
