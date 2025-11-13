// @copyright André Trettin

import AndrenalinKit
import CoreExternalRPG
import SwiftUI

struct PdfDetailEditor: View {
    let editController: EditController
    let model: PdfModel

    @Environment(PdfRoot.self) private var root

    @State private var openFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.space.viewerWindowId, route: { DetailRoute.viewer($0) })

    var body: some View {
        ItemDetailRootView(detailListController: root.folderListController.copy(parentModel: selectedModel), selectedId: selectedModel?.id, editorAsBackground: true) {
        } editor: {
            if let model = selectedModel {
                PdfDetailObjectViewer(editController: editController, model: model)
            }
        } inspector: {
            LinkRootView(type: .inspector)
        }
        .onChange(of: root.folderListController.listModel.selectedItemId, initial: true) {
            update()
        }
        .environment(openFileWindowModel)
        .environment(root.folderListController.cacheListItemModel)
        .environment(root.listDisplayModel)
        .environment(root.searchModel)
        .environment(root.rootController)
        .tint(NetworkModules.pdf.tint)
        .accentColor(NetworkModules.pdf.tint)
    }
    
    var selectedModel: PdfModel? {
        root.folderListController.selectedModel(for: nil) as? PdfModel
    }

    func update() {
        if let item = root.folderListController.listModel.selectedModel as? PdfModel {
            if editController.editorModel.currentItemId != item.id {
                editController.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .space))
            }
        } else {
            if editController.editorModel.currentItemId != nil {
                editController.resetCurrentItem(with: "save".localizedString)
            }
        }
    }
}

struct PdfDetailObjectViewer: View {
    let editController: EditController
    let model: PdfModel
    
    @Environment(PdfRoot.self) private var root
    @Environment(GroupItemSelectionModel.self) private var selection
    
    var body: some View {
        PdfDetailViewer(item: ItemRowTreeModel(itemId: model.id, typeId: .pdf))
            .id(selectedModel.id)
    }
    
    private var selectedModel: PdfModel {
        guard let itemId = selection.selectedItem else { return model }
        return root.itemController.itemOrEmpty(for: itemId)
    }
}

#Preview {
    PdfDetailEditor(editController: PdfRoot.previewWithData.editController(type: .main), model: .preview)
        .environment(PdfRoot.previewWithData)
        .environment(ListModel.preview)
        .environment(SelectionSheetLinkModel())
}
