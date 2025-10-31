// @copyright André Trettin

import AndrenalinKit
import CoreExternalRPG
import SwiftUI
import UniformTypeIdentifiers

struct SpaceDetailEditor: View {
    let editController: EditController
    let model: SpaceModel
    
    @Environment(SpaceRoot.self) private var root
    @Environment(ListModel.self) private var listModel
    
    @State private var openFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.space.viewerWindowId, route: { DetailRoute.viewer($0) })

    var body: some View {
        ItemDetailRootView(selectedId: selectedModel?.id, editorAsBackground: true) {
        } editor: {
            if let model = selectedModel {
                SpaceDetailObjectViewer(editController: editController, model: model)
            }
        } inspector: {
            LinkRootView(type: .inspector)
        }
        .onChange(of: listModel.selectedItem, initial: true) {
            update()
        }
        .environment(openFileWindowModel)
        .environment(CacheItemListModel())
        .environment(root.listDisplayModel)
        .environment(root.searchModel)
        .environment(root.rootController)
        .tint(NetworkModules.space.tint)
        .accentColor(NetworkModules.space.tint)
    }
    
    var selectedModel: SpaceModel? {
        guard let itemId = listModel.selectedItem?.model.itemId else { return nil }
        return root.itemController.itemOrEmpty(for: itemId)
    }
    
    func update() {
        if let item = listModel.selectedItem {
            if editController.editorModel.currentItemId != item.model.itemId || editController.editorModel.currentEntryId != item.model.entryId {
                editController.setCurrentItem(to: item)
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
            SpaceDetailEditor(editController: .preview, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? SpaceRoot.previewSpaceId))
                .preferredColorScheme(.dark)
        }
    }
    
}
