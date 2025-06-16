// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct PhotoDetailEditor: View {
    let editController: EditController
    let model: PhotoModel

    @Environment(PhotoRoot.self) private var root

    @State private var detailHeaderModel = DetailHeaderModel(minHeight: 144, maxHeight: 400, maxHeightFromScreenHeight: true)
    @State private var externalHeaderModel = ExternalHeaderModel()
    
    var body: some View {
        let _ = Self._printChanges()
        @Bindable var model = model
        DetailEditor(editController: editController) {
            HeaderEditor(editController: editController)
            
            PhotoSectionEditor(editController: editController, model: model)

            PhotosSectionEditor(editController: editController)
        } headerView: {
            PhotoEditor(editController: editController)
#if !os(macOS)
                .ignoresSafeArea(.container, edges: .top)
#endif
                .id(model.id)
        } extHeaderView: {
            PhotoExternalHeader(model: model)
        }
        .focusedSceneValue(\.selectedPhoto, $model.id)
        .environment(detailHeaderModel)
        .environment(externalHeaderModel)
    }
}

struct PhotoExternalHeader: View {
    let model: PhotoModel

    @Environment(ExternalHeaderModel.self) private var externalHeaderModel

    var body: some View {
        RootImageViewer(model: model, size: CGSize(width: 360, height: 400), toolBarModel: GameToolBarModel(), isGame: false) {
            externalHeaderModel.showExtHeader = false
        }
        .id(model.id)
    }
}

#Preview {
    NavigationStack {
        PhotoDetailEditor(editController: .preview, model: .preview)
            .environment(PhotoRoot.previewWithData)
            .environment(ListModel.preview)
            .environment(\.locale, Locale(identifier: "de"))
            .environment(SelectionSheetLinkModel())
    }
}
