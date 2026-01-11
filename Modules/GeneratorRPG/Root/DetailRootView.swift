// @copyright André Trettin

import CoreRPG

import SwiftUI

struct DetailRootView: View {
    let root: GeneratorRootModel
    let model: GeneratorModel

    var body: some View {
        DetailListView(root: root, model: model)
            .detailInspectorModifier(folderListControllable: root.folderListController)
    }
}

struct DetailListView: View {
    init(root: GeneratorRootModel, model: GeneratorModel) {
        self.root = root
        self.model = model
        let listController = root.folderListController.copy(parentModel: model) as! FolderListController
        self._detailFolderListController = State(wrappedValue: listController)
    }
    
    let root: GeneratorRootModel
    let model: GeneratorModel
    
    @Environment(\.navigator) private var navigator
    
    @State private var detailFolderListController: FolderListController
    @State private var openFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.generator.viewerWindowId, canShow: true, route: { DetailRoute.viewer($0) })

    @State private var selection: ItemSelectionModel = ItemSelectionModel()
    
    var body: some View {
        content(listController: detailFolderListController)
            .onChange(of: detailFolderListController.listModel.subFolderRoute) {
                guard let subItemId = detailFolderListController.listModel.subFolderRoute else { return }
                navigator.navigate(to: GeneratorDetailRoute.folder(subItemId), method: .push)
                detailFolderListController.listModel.subFolderRoute = nil
            }
            .onChange(of: model.id, initial: true) {
                root.editController.setCurrentItem(to: ItemRowTreeModel(itemId: model.id, typeId: root.config.module))
            }
    }
    
    func content(listController: any FolderListControllable) -> some View {
        ItemDetailRootView(detailListController: listController, selectedModel: model, editorAsBackground: false) {
        } editor: {
            Text("Add a reference character")
            
            detailEditorView(model: model)
        } inspector: {
            LinkRootView(type: .inspector)
                .environment(selection)
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
        .tint(root.configurable.module.tint)
        .accentColor(root.configurable.module.tint)
    }
    
    @ViewBuilder
    func detailEditorView(model: GeneratorModel) -> some View {
        @Bindable var model = model
        Picker(selection: $model.genType) {
            ForEach(GeneratorModel.GenType.allCases) { genType in
                Text(genType.title)
                    .tag(genType)
            }
        } label: {
            Text("Generation Type")
        }
    }
}
