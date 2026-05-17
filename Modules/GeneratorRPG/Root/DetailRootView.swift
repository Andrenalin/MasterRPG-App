// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailRootView: View {
    let root: GeneratorRootModel
    let model: GeneratorModel

    var body: some View {
        DetailListView(root: root, model: model)
            .detailInspectorModifier(root: root.rootController)
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
        ItemDetailRootView(
            root: root.rootController,
            detailListController: listController,
            selectedModel: model,
            openFileWindowModel: root.openFileWindowModel,
            configuration: .init(editorAsBackground: false, hasOverlay: false, hasEntryEditor: false),
            linkTypes: EmptyLinkTransferable.self
        ) {
            Text("Add a reference character")

            detailEditorView(model: model)
        } overlay: {
            EmptyView()
        }
        .overlay {
            if root.openFileWindowModel.showItem {
                root.viewController.viewer(root: root, itemId: root.openFileWindowModel.itemId, configuration: ViewerConfiguration(closeButton: true)) {
                    root.openFileWindowModel.showItem = false
                }
            }
        }
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
