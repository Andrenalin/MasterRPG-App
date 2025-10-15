// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct MapEntryMapEditButton: View {
    let editController: EditController
    let entrySectionEditorModel: EntrySectionEditorModel<MapModel>

    @Environment(MapRoot.self) private var root
    @Environment(EntrySectionSelectionModel.self) private var entrySectionSelectionModel
    @Environment(SelectionSheetLinkModel.self) private var selectionModel

    @State private var showMapEditor = false

    var body: some View {
        Button {
            withAnimation {
                editController.editorModel.currentEntryId = entryId
                showMapEditor.toggle()
            }
        } label: {
            Label { Text("Edit Entry Map", bundle: .module) } icon: { Image(systemName: "pencil") }
        }
        .onChange(of: showMapEditor) {
            if showMapEditor {
                selectionModel.selectionFullView = AnyView(mapEditView)
                selectionModel.idealSize = editController.model.mapIdealSize
                showMapEditor = false
                withAnimation { selectionModel.selectionFullScreen = true }
            }
        }
    }

    private var mapEditView: some View {
        RootEditCanvasMap(editController: editController)
            .environment(root)
#if os(iOS)
            .statusBar(hidden: true)
#endif
    }

    private var entryId: UUID {
        entrySectionSelectionModel.id
    }
}
