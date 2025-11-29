// @copyright André Trettin

import AndrenalinKit
import CoreExternalRPG
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
    }
    
    func content(listController: any FolderListControllable) -> some View {
        ItemDetailRootView(detailListController: listController, selectedId: model.id, editorAsBackground: false) {
        } editor: {
            Text("Add a reference character")
            
            detailEditorView(model: model)
        } inspector: {
            LinkRootView(type: .inspector)
        }
        .overlay {
            if openFileWindowModel.showItem {
                root.viewController.inlineViewer(root: root, with: openFileWindowModel.itemId) {
                    openFileWindowModel.showItem = false
                }
            }
        }
//        .navigationDestination(for: SelectionCharacterRoute.self) { route in
//            route
//                .environment(root.editController.selectionReference)
//        }
        .environment(openFileWindowModel)
        .environment(root.folderListController.cacheListItemModel)
        .environment(root.listDisplayModel)
        .environment(root.searchModel)
        .environment(root.rootController)
        .tint(root.module.tint)
        .accentColor(root.module.tint)
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

//        root.characterRoot.viewController.selectionView(root: root.characterRoot, model: root.editController.selectionReference)
//            .onChange(of: root.editController.selectionReference.selection) {
//                withAnimation { root.editController.add(referenceId: root.editController.selectionReference.itemId, model: model) }
//            }
//            .onChange(of: model.referenceId, initial: true) {
//                withAnimation { root.editController.selectionReference.resetSelection(itemId: model.referenceId) }
//            }
    }
}

//#Preview(traits: .mockData) {
//    @Previewable @Environment(GeneratorRootModel.self) var root
//    @Previewable @Environment(ListModel.self) var listModel
//    
//    if listModel.selectedItem == nil {
//        Text("Hello")
//            .onAppear {
//                let id = root.itemController.itemDataModel.items.first ?? MockData.previewId
//                root.editController.model = root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? MockData.previewId)
//                listModel.selectedItem = ItemRowTreeModel(itemId: id, typeId: .generator)
//            }
//    } else {
//        ManagedNavigationStack {
//            DetailRootView(root: root, editController: .preview, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? MockData.previewId))
//                .preferredColorScheme(.dark)
//        }
//    }
//
//}
