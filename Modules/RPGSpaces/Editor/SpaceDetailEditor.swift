// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct SpaceDetailEditor: View {
    let editController: EditController
    let model: SpaceModel
    
    @Environment(SpaceRoot.self) private var root

    @State private var detailHeaderModel = DetailHeaderModel(minHeight: 144, maxHeight: 400, maxHeightFromScreenHeight: true)
    @State private var externalHeaderModel = ExternalHeaderModel()
    
    var body: some View {
        @Bindable var model = model
        DetailEditor(editController: editController) {
            HeaderEditor(editController: editController)
            
            FileLocationEditor(editController: editController, fileStore: root.fileUrlDataController, fileUrlBinding: $model.fileUrl)
            
            SpacesSectionEditor(editController: editController, model: model)
        } headerView: {
            SpaceEditor(editController: editController)
#if !os(macOS)
                .ignoresSafeArea(.container, edges: .top)
#endif
                .id(model.id)
        } extHeaderView: {
            SpaceExternalHeader(editController: editController, model: model)
        }
        .focusedSceneValue(\.selectedSpace, $model.id)
        .environment(detailHeaderModel)
        .environment(externalHeaderModel)
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
