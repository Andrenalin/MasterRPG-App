// @copyright André Trettin

import CoreRPG

import SwiftUI

struct DetailRootView: View {
    let root: SpaceRootModel
    let model: SpaceModel

    var body: some View {
        DetailListView(root: root, model: model)
            .detailInspectorModifier(folderListControllable: root.folderListController)
    }
}

struct DetailListView: View {
    init(root: SpaceRootModel, model: SpaceModel) {
        self.root = root
        self.model = model
        let listController = root.folderListController.copy(parentModel: model) as! FolderListController
        self._detailFolderListController = State(wrappedValue: listController)
    }
    
    let root: SpaceRootModel
    let model: SpaceModel

    @Environment(\.navigator) private var navigator
    
    @State private var detailFolderListController: FolderListController
    @State private var openFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.space.viewerWindowId, route: { DetailRoute.viewer($0) })

    var body: some View {
        content(listController: detailFolderListController)
            .onChange(of: detailFolderListController.listModel.subFolderRoute) {
                guard let subItemId = detailFolderListController.listModel.subFolderRoute else { return }
                navigator.navigate(to: SpaceDetailRoute.folder(subItemId), method: .push)
                detailFolderListController.listModel.subFolderRoute = nil
            }
    }
    
    func content(listController: any FolderListControllable) -> some View {
        ItemDetailRootView(detailListController: listController, selectedModel: model, editorAsBackground: true) {
        } editor: {
            SpaceDetailObjectViewer(editController: root.editController, model: model)
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
        .tint(root.module.tint)
        .accentColor(root.module.tint)
    }
}

struct SpaceDetailObjectViewer: View {
    let editController: EditController
    let model: SpaceModel
    
    @Environment(SpaceRootModel.self) private var root
    @Environment(GroupItemSelectionModel.self) private var selection
    
    var body: some View {
        ViewerRootView(model: selectedModel, externalViewer: false)
            .id(selectedModel.id)
    }
    
    private var selectedModel: SpaceModel {
        guard let itemId = selection.selectedItem else { return model }
        return root.itemController.itemOrEmpty(for: itemId)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(SpaceRootModel.self) var root
    @Previewable @Environment(ListModel.self) var listModel
    
    if listModel.selectedItem == nil {
        Text("Hello")
            .onAppear {
                let id = root.itemController.itemDataModel.items.first ?? SpaceRootModel.previewSpaceId
                root.editController.model = root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? SpaceRootModel.previewSpaceId)
                listModel.selectedItem = ItemRowTreeModel(itemId: id, typeId: .space)
            }
    } else {
        ManagedNavigationStack {
            DetailRootView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? SpaceRootModel.previewSpaceId))
                .preferredColorScheme(.dark)
        }
    }
}
