// @copyright André Trettin

import AndrenalinKit
import CoreExternalRPG
import SwiftUI

struct DetailRootView: View {
    let editController: EditController
    let model: SpaceModel
    
    @Environment(SpaceRoot.self) private var root
    
    @State private var openFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.space.viewerWindowId, route: { DetailRoute.viewer($0) })

    var body: some View {
        ItemDetailRootView(detailListController: root.folderListController.copy(parentModel: selectedModel), selectedId: selectedModel?.id, editorAsBackground: true) {
        } editor: {
            if let model = selectedModel {
                SpaceDetailObjectViewer(editController: editController, model: model)
            }
        } inspector: {
            LinkRootView(type: .inspector)
        }
        .onChange(of: root.folderListController.listModel.selectedItemId, initial: true) {
            update()
        }
        .overlay {
            if openFileWindowModel.showItem {
                root.viewController.inlineViewer(root: root, with: openFileWindowModel.itemId) {
                    openFileWindowModel.showItem = false
                }
            }
        }
        .environment(openFileWindowModel)
        .environment(root.folderListController.cacheListItemModel)
        .environment(root.listDisplayModel)
        .environment(root.searchModel)
        .environment(root.rootController)
        .tint(NetworkModules.space.tint)
        .accentColor(NetworkModules.space.tint)
    }
    
    var selectedModel: SpaceModel? {
        root.folderListController.selectedModel(for: nil) as? SpaceModel
    }

    func update() {
        if let item = root.folderListController.listModel.selectedModel as? SpaceModel {
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

struct SpaceDetailObjectViewer: View {
    let editController: EditController
    let model: SpaceModel
    
    @Environment(SpaceRoot.self) private var root
    @Environment(GroupItemSelectionModel.self) private var selection
    
    var body: some View {
        SpaceExternalHeader(editController: editController, model: selectedModel, isModal: false)
            .id(selectedModel.id)
    }
    
    private var selectedModel: SpaceModel {
        guard let itemId = selection.selectedItem else { return model }
        return root.itemController.itemOrEmpty(for: itemId)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(SpaceRoot.self) var root
    @Previewable @Environment(ListModel.self) var listModel
    
    if listModel.selectedItem == nil {
        Text("Hello")
            .onAppear {
                let id = root.itemController.itemDataModel.items.first ?? SpaceRoot.previewSpaceId
                root.editController(type: .main).model = root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? SpaceRoot.previewSpaceId)
                listModel.selectedItem = ItemRowTreeModel(itemId: id, typeId: .space)
            }
    } else {
        ManagedNavigationStack {
            DetailRootView(editController: .preview, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? SpaceRoot.previewSpaceId))
                .preferredColorScheme(.dark)
        }
    }
}
