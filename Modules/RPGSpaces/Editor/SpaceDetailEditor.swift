// @copyright André Trettin

import AndrenalinKit
import SwiftUI
internal import UniformTypeIdentifiers

struct SpaceDetailEditor: View {
    let editController: EditController
    let model: SpaceModel
    
    @Environment(SpaceRoot.self) private var root

    @State private var openFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.space.linkWindowId, route: { DetailRoute.viewer($0) })

    var body: some View {
        ItemDetailRootView(selectedId: model.id) {
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
        .id(model.id)
    }
    
//    var selectedModel: ItemDataModel? {
//        root.listControllable.selectedModel(for: selectedId, modelContext: modelContext)
//    }
    
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

#Preview {
    SpaceDetailEditor(editController: .preview, model: .preview)
        .environment(SpaceRoot.preview)
        .environment(ListModel.preview)
}
