// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct TableDetailEditor: View {
    let editController: EditController
    let model: TableModel
    
    @Environment(TableRoot.self) private var root
    
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
        } extContentHeight: { screenHeight in
            let minHeight = Double(model.entries.count * 128)
            return min(max(minHeight, screenHeight * 0.5), screenHeight)
        } heightCalculator: { size in
            (96, 96)
        }
        .focusedSceneValue(\.selectedTable, $model.id)
    }
}

struct TableExternalHeader: View {
    let editController: EditController

    @Environment(ExternalHeaderModel.self) private var externalHeaderModel

    var body: some View {
        TableSheet(model: editController.model, showTopImage: false) {
            externalHeaderModel.showExtHeader = false
        }
    }
}

#Preview {
    TableDetailEditor(editController: .preview, model: .preview)
        .environment(TableRoot.preview)
}
