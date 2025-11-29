// @copyright André Trettin

import CoreRPG

import SwiftUI
import DiceRPG
import PhotoRPG

struct DetailRootView: View {
    let root: MapRootModel
    let model: MapModel
    
    var body: some View {
        DetailListView(root: root, model: model)
            .detailInspectorModifier(folderListControllable: root.folderListController)
    }
}

struct DetailListView: View {
    init(root: MapRootModel, model: MapModel) {
        self.root = root
        self.model = model
        let listController = root.folderListController.copy(parentModel: model) as! FolderListController
        self._detailFolderListController = State(wrappedValue: listController)
    }
    
    let root: MapRootModel
    let model: MapModel
    
    @Environment(\.navigator) private var navigator
    
    @State private var detailFolderListController: FolderListController
    @State private var openFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.map.viewerWindowId, canShow: true, route: { DetailRoute.viewer($0) })
    @State private var animate: Bool = false
    
    var body: some View {
        content(listController: detailFolderListController)
            .onChange(of: detailFolderListController.listModel.subFolderRoute) {
                guard let subItemId = detailFolderListController.listModel.subFolderRoute else { return }
                navigator.navigate(to: MapDetailRoute.folder(subItemId), method: .push)
                detailFolderListController.listModel.subFolderRoute = nil
            }
    }
    
    func content(listController: any FolderListControllable) -> some View {
        ItemDetailRootView(detailListController: listController, selectedId: model.id, editorAsBackground: false) {
        } editor: {
            detailEditorView
        } inspector: {
            EditorLinkView()
        } entryEditor: {
            EntryEditorView(editController: root.editController)
        }
        .overlay {
            if openFileWindowModel.showItem {
                root.viewController.inlineViewer(root: root, with: openFileWindowModel.itemId) {
                    openFileWindowModel.showItem = false
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .secondaryActionAll) {
                Button {
                    navigator.navigate(to: EditorRoute.quickEditor, method: .cover)
                } label: {
                    Label {
                        Text("Quick Editor", bundle: .module)
                    } icon: {
                        Image(systemName: "table.badge.more")
                    }
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
    
    @ViewBuilder
    var detailEditorView: some View {
//        root.diceRoot.viewController.selectionView(root: root.diceRoot, model: root.editController.valueEditModel.selectionDice)
//            .onChange(of: root.editController.valueEditModel.selectionDice.selection) {
//                withAnimation { root.editController.add(diceId: root.editController.valueEditModel.selectionDice.itemId, model: model) }
//            }
//            .onChange(of: model.diceId, initial: true) {
//                withAnimation { root.editController.valueEditModel.selectionDice.resetSelection(itemId: model.diceId) }
//            }
        
        EntryListView(editController: root.editController)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(MapRootModel.self) var root
    @Previewable @Environment(ListModel.self) var listModel
    
    if listModel.selectedItem == nil {
        Text("Hello")
            .onAppear {
                let id = root.itemController.itemDataModel.items.first ?? MapModel.previewId
                root.editController.model = root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? MapModel.previewId)
                listModel.selectedItem = ItemRowTreeModel(itemId: id, typeId: .space)
            }
    } else {
        ManagedNavigationStack {
            DetailRootView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? MapModel.previewId))
                .preferredColorScheme(.dark)
        }
    }
}
