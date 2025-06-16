// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct PhotoDetailEditor: View {
    let editController: EditController
    let model: PhotoModel

    @Environment(PhotoRoot.self) private var root
    
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
        } heightCalculator: { size in
            (144, min(size.height * 0.35, 400))
        }
        .focusedSceneValue(\.selectedPhoto, $model.id)
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
