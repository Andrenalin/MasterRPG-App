// @copyright André Trettin

import CoreRPG
import CoreExternalRPG
import SwiftUI

struct DetailRootView: View {
    let root: PdfRootModel
    let model: PdfModel
    
    var body: some View {
        DetailListView(root: root, model: model)
            .detailInspectorModifier(folderListControllable: root.folderListController)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(PdfRootModel.self) var root
    @Previewable @Environment(ListModel.self) var listModel
    
    if listModel.selectedItem == nil {
        Text("Hello")
            .onAppear {
                let id = root.itemController.itemDataModel.items.first ?? PdfRootModel.previewSpaceId
                root.editController.model = root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? PdfRootModel.previewSpaceId)
                listModel.selectedItem = ItemRowTreeModel(itemId: id, typeId: root.module)
            }
    } else {
        ManagedNavigationStack {
            DetailRootView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? PdfRootModel.previewSpaceId))
                .preferredColorScheme(.dark)
        }
    }
}
