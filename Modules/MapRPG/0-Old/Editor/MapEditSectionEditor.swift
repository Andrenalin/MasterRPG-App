// @copyright André Trettin

import CoreRPG
import SwiftUI

struct MapEditSectionEditor: View {
    let editController: EditController
    
    @Environment(MapRootModel.self) private var root

    @State private var isReading = false
    @State private var isPlaying = false

#if os(visionOS) || os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif

    var body: some View {
        HStack {
            ImageOverlayButton(icon: "book\(isReading ? ".fill": "")") {
#if os(visionOS) || os(macOS)
                openWindow(id: WindowIdentifier.mapBookViewer.rawValue, value: ItemSelection(itemId: editController.model.id, entryId: nil))
#else
                isReading.toggle()
#endif
            }

            ImageOverlayButton(icon: "map\(isPlaying ? ".fill" : "")") {
                withAnimation { editController.editorModel.currentEntryId = nil }
#if os(visionOS) || os(macOS)
                openWindow(id: WindowIdentifier.mapEditor.rawValue)
#else
                isPlaying.toggle()
#endif
            }
        }
        .sheetFullScreen(isPresented: $isPlaying, idealSize: editController.model.mapIdealSize) {
            MapEditWindow(editController: editController)
#if os(iOS)
                .statusBar(hidden: true)
                .persistentSystemOverlays(.hidden)
#endif
        }
        .sheetFullScreen(isPresented: $isReading, idealSize: editController.model.mapIdealSize) {
            MapSheet(model: editController.model, showTopImage: true, dismissAction: nil)
                .environment(root)
                .environment(\.showGame, false)
        }
    }
}
