// @copyright André Trettin

import AndrenalinKit
import CoreExternalRPG
import SwiftUI

struct DetailRootView: View {
    init(root: DiceRootModel, editController: EditController, model: DiceModel, isSubFolder: Bool) {
        self.root = root
        self.editController = editController
        self.model = model
        self.isSubFolder = isSubFolder
        let listController = root.folderListController.copy(parentModel: model) as! FolderListController
        self._detailFolderListController = State(wrappedValue: listController)
    }
    
    let root: DiceRootModel
    let editController: EditController
    let model: DiceModel
    let isSubFolder: Bool
    
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
        ItemDetailRootView(detailListController: listController, selectedId: model.id, editorAsBackground: false) {
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
        DiceEditor(model: model)
        DiceOptionEditor(model: model)
        CoupEditor(model: model)
        OldFumbleEditor(editController: editController)
        OLdRerollEditor(editController: editController)
        OLdSpecialOptionEditor(editController: editController)
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
            DetailRootView(root: root, editController: .preview, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? DiceModel.previewId), isSubFolder: false)
                .preferredColorScheme(.dark)
        }
    }
}
