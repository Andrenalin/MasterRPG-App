// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct MapDetailEditor: View {
    let editController: EditController
    let model: MapModel

    @Environment(MapRootModel.self) private var root
    
    @State private var detailHeaderModel = DetailHeaderModel(minHeight: 144, maxHeight: 400, maxHeightFromScreenHeight: true)
    @State private var externalHeaderModel = ExternalHeaderModel()

    var body: some View {
        @Bindable var model = model
        //let _ = Self._printChanges()

        DetailEditor(editController: editController) {

            HeaderEditor(editController: editController)
            
            PhotoSelectionEditor(editController: editController)

            DisplayConfigEditor(editController: editController)

            SpecialEditor(editController: editController)

#if !os(macOS)
            MapEntrySectionEditor(editController: editController)
            
            MapPinSectionEditor(editController: editController)
#endif
        } headerView: {
            AnimatedHeaderMap(editController: editController)
        } extHeaderView: {
            MapExternalHeader(editController: editController)
        } extContentView: {
#if !os(tvOS)
            MapEntryEditor(root: root, editController: editController)

            MapPinEditor(root: root, editController: editController)
#endif
        }
        .environment(detailHeaderModel)
        .environment(externalHeaderModel)
        .onChange(of: model.entries, initial: true) {
            externalHeaderModel.minHeight = Double(model.entries.count * 128)
        }
    }
}

struct MapExternalHeader: View {
    let editController: EditController

    @Environment(ExternalHeaderModel.self) private var externalHeaderModel

    var body: some View {
        MapSheet(model: editController.model, showTopImage: false) {
            externalHeaderModel.showExtHeader = false
        }
        .environment(\.showGame, false)
    }
}

#Preview {
    MapDetailEditor(editController: .preview, model: .preview)
        .environment(MapRootModel.previewWithData)
        .environment(ListModel.preview)
}
