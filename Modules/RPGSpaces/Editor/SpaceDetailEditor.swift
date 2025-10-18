// @copyright André Trettin

import AndrenalinKit
import CoreExternalRPG
import SwiftUI
internal import UniformTypeIdentifiers

struct SpaceDetailEditor: View {
    let editController: EditController
    let model: SpaceModel
    
    @Environment(SpaceRoot.self) private var root
    @Environment(ListModel.self) private var listModel
    
    @State private var openFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.space.viewerWindowId, route: { DetailRoute.viewer($0) })

    var body: some View {
        ItemDetailRootView(selectedId: selectedModel?.id, editorAsBackground: true) {
        } editor: {
            //CachePhotoView(cacheController: root.cacheController, model: model, highResolution: false)
            if let model = selectedModel {
                SpaceExternalHeader(editController: editController, model: model, isModal: false)
                    .id(model.id)
            }
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
    
    @ViewBuilder
    var editor: some View {
        SpacesSectionEditor(editController: editController, model: model)
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
