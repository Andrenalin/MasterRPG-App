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
        .tint(root.configurable.module.tint)
        .accentColor(root.configurable.module.tint)
    }
    
    @ViewBuilder
    func detailEditorView() -> some View {
        DiceEditor(model: model)
        DiceOptionEditor(model: model)
        CoupEditor(model: model)
        FumbleEditor(model: model)
        RerollEditor(model: model)
        SpecialOptionEditor(model: model)
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
    ManagedNavigationStack {
        DetailRootView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? DiceModel.previewId))
            .preferredColorScheme(.dark)
    }
}
