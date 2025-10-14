// @copyright André Trettin

import AndrenalinKit
import SwiftUI
internal import UniformTypeIdentifiers

struct SpaceDetailEditor: View {
    let editController: EditController
    let model: SpaceModel
    
    @Environment(SpaceRoot.self) private var root
    @Environment(ListModel.self) private var listModel
    
    @State private var openFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.space.linkWindowId, route: { DetailRoute.viewer($0) })

    var body: some View {
        ItemDetailRootView(selectedId: selectedModel?.id) {
        } editor: {
            editor
#if !os(tvOS)
//            if let model = selectedModel {
                SpaceExternalHeader(editController: editController, model: model)
                //SpaceViewer(root: root, model: model)
                    .id(model.id)
                    .frame(minHeight: 800)
//            }
#endif
        }
        .environment(openFileWindowModel)
        .environment(CacheItemListModel())
        .environment(root.listDisplayModel)
        .environment(root.searchModel)
        .environment(root.rootController)
        .environment(ExternalHeaderModel())
        .id(model.id)
    }
    
    var selectedModel: SpaceModel? {
        guard let itemId = listModel.selectedItem?.model.itemId else { return nil }
        return root.itemController.itemOrEmpty(for: itemId)
    }
    
    @ViewBuilder
    var editor: some View {
        @Bindable var model = model
        
        HeaderEditor(editController: editController)

        FileLocationEditor(editController: editController, fileStore: root.fileUrlDataController, fileUrlBinding: $model.fileUrl)

        SpacesSectionEditor(editController: editController, model: model)
    }
}

struct SpaceExternalHeader: View {
    let editController: EditController
    let model: SpaceModel

    @Environment(SpaceRoot.self) private var root
    @Environment(ExternalHeaderModel.self) private var externalHeaderModel

    var body: some View {
#if os(tvOS)
        SpaceEditor(editController: editController)
            .environment(DetailHeaderModel(size: CGSize(width: 400, height: 400)))
#else
        SpaceViewer(root: root, id: model.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomTrailing) {
                ImageOverlayButton(icon: "xmark") {
                    externalHeaderModel.showExtHeader = false
                }
                .padding()
            }
#endif
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(SpaceRoot.self) var root
    
    SpaceDetailEditor(editController: .preview, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? SpaceRoot.previewSpaceId))
        .preferredColorScheme(.dark)
        .onAppear {
            root.editController(type: .main).model = root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? SpaceRoot.previewSpaceId)
        }
}
