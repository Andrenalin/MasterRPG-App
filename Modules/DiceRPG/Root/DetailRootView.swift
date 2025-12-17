// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailRootView: View {
    let root: DiceRootModel
    let model: DiceModel

    var body: some View {
        DetailListView(root: root, model: model)
            .detailInspectorModifier(folderListControllable: root.folderListController)
    }
}

struct DetailListView: View {
    init(root: DiceRootModel, model: DiceModel) {
        self.root = root
        self.model = model
        let listController = root.folderListController.copy(parentModel: model) as! FolderListController
        self._detailFolderListController = State(wrappedValue: listController)
    }
    
    let root: DiceRootModel
    let model: DiceModel
    
    @Environment(\.navigator) private var navigator
    
    @State private var detailFolderListController: FolderListController
    @State private var openFileWindowModel = OpenFileWindowModel()
    
    var body: some View {
        content(listController: detailFolderListController)
            .onChange(of: detailFolderListController.listModel.subFolderRoute) {
                guard let subItemId = detailFolderListController.listModel.subFolderRoute else { return }
                navigator.navigate(to: DiceDetailRoute.folder(subItemId), method: .push)
                detailFolderListController.listModel.subFolderRoute = nil
            }
    }
    
    func content(listController: any FolderListControllable) -> some View {
        ItemDetailRootView(detailListController: listController, selectedModel: model, editorAsBackground: false) {
        } editor: {
            detailEditorView()
        } overlay: {
            diceOverlay
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
    func detailEditorView() -> some View {
        DiceEditor(model: root.editController.model)
        DiceOptionEditor(model: root.editController.model)
        CoupEditor(model: root.editController.model)
        FumbleEditor(model: root.editController.model)
        RerollEditor(model: root.editController.model)
        SpecialOptionEditor(model: root.editController.model)
    }

    @ViewBuilder
    var diceOverlay: some View {
        GlassEffectContainerView {
            DiceViewer(model: model, isEditor: false)
                .padding()
#if !os(visionOS)
        .glassEffect(.clear)
#endif
        }
        .padding()
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(DiceRootModel.self) var root
    @Previewable @Environment(ListModel.self) var listModel
    
    if listModel.selectedItem == nil {
        Text("Hello")
            .onAppear {
                let id = root.itemController.itemDataModel.items.first ?? DiceModel.previewId
                root.editController.model = root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? DiceModel.previewId)
                listModel.selectedItem = ItemRowTreeModel(itemId: id, typeId: .dice)
            }
    } else {
        ManagedNavigationStack {
            DetailRootView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? DiceModel.previewId))
                .preferredColorScheme(.dark)
        }
    }
}
