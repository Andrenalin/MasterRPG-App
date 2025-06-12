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
        } headerView: { size, safeTopMargin, isInline in
            PhotoEditor(editController: editController, size: size, topMargin: safeTopMargin, inline: isInline)
#if !os(macOS)
                .ignoresSafeArea(.container, edges: .top)
#endif
                .id(model.id)
        } extHeaderView: { dismiss in
            RootImageViewer(model: model, size: CGSize(width: 360, height: 400), toolBarModel: GameToolBarModel(), isGame: false, dismiss: dismiss)
                .id(model.id)
        } heightCalculator: { size in
            (144, min(size.height * 0.35, 400))
        }
        .focusedSceneValue(\.selectedPhoto, $model.id)
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
