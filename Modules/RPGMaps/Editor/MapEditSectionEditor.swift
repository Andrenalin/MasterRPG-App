// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct MapEditSectionEditor: View {
    let editController: EditController
    
    @Environment(MapRoot.self) private var root

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

struct MapEditWindow: View {
    let editController: EditController

    @Environment(MapRoot.self) private var root

    var body: some View {
        @Bindable var model = editController.editorModel
        Group {
            if let listItem = model.currentListItem {
                RootEditCanvasMap(editController: editController)
                    .navigationTitle(root.itemController.nameSync(model: listItem.model))
            } else {
                Text("No Map Item is selected for editing", bundle: .module)
            }
        }
    }
}
