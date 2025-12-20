// @copyright André Trettin

import CoreRPG
import SwiftUI

struct TableDetailEditor: View {
    let editController: EditController
    let model: TableModel
    
    @Environment(TableRootModel.self) private var root

    @State private var detailHeaderModel = DetailHeaderModel()
    @State private var externalHeaderModel = ExternalHeaderModel()
    
    var body: some View {
        @Bindable var model = model
        DetailEditor(editController: editController) {
            HeaderEditor(editController: editController)
            
            ListTypeEditor(editController: editController)

            SpecialEditor(editController: editController)

#if !os(macOS)
            TableEntrySectionEditor(editController: editController)
#endif
        } headerView: {
            TableDetailHeader(editController: editController, model: model)
#if !os(macOS)
                .ignoresSafeArea(.container, edges: .top)
#endif
        } extHeaderView: {
            TableExternalHeader(editController: editController)
        } extContentView: {
#if !os(tvOS)
            TableEntryEditor(root: root, editController: editController)
#endif
        }
        .environment(detailHeaderModel)
        .environment(externalHeaderModel)
        .onChange(of: model.entries, initial: true) {
            externalHeaderModel.minHeight = Double(model.entries.count * 128)
        }
    }
}

struct TableExternalHeader: View {
    let editController: EditController

    @Environment(ExternalHeaderModel.self) private var externalHeaderModel

    var body: some View {
        ViewerRootView(model: editController.model, showTopImage: false) {
            externalHeaderModel.showExtHeader = false
        }
    }
}

#Preview {
    TableDetailEditor(editController: .preview, model: .preview)
        .environment(TableRootModel.preview)
}
