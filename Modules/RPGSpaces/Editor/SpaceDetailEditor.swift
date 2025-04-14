// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct SpaceDetailEditor: View {
    let editController: EditController
    let model: SpaceModel
    
    @Environment(SpaceRoot.self) private var root
    
    var body: some View {
        @Bindable var model = model
        DetailEditor(editController: editController) {
            HeaderEditor(editController: editController)
            
            FileLocationEditor(editController: editController, fileStore: root.fileUrlDataController, fileUrlBinding: $model.fileUrl)
            
            SpacesSectionEditor(editController: editController, model: model)
        } headerView: { size, safeTopMargin, isInline in
            SpaceEditor(editController: editController, size: size, topMargin: safeTopMargin, inline: isInline)
#if !os(macOS)
                .ignoresSafeArea(.container, edges: .top)
#endif
                .id(model.id)
        } extHeaderView: { dismiss in
            extSpaceHeaderView(dismiss: dismiss)
        } heightCalculator: { size in
            (144, min(size.height * 0.35, 400))
        }
        .focusedSceneValue(\.selectedSpace, $model.id)
    }
    
    @ViewBuilder
    func extSpaceHeaderView(dismiss: @escaping () -> Void) -> some View {
#if os(tvOS)
        extSpaceHeaderQuickLookView(dismiss: dismiss)
#else
        SpaceViewer(root: root, id: model.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomTrailing) {
                ImageOverlayButton(icon: "xmark", action: dismiss)
                    .padding()
            }
#endif
    }
    
    func extSpaceHeaderQuickLookView(dismiss: @escaping () -> Void) -> some View {
        SpaceEditor(editController: editController, size: CGSize(width: 400, height: 400), topMargin: 0, inline: false)
#if !os(tvOS)
            .overlay {
                SpaceQuickLook(root: root, item: ItemSelection(itemId: model.id, entryId: nil), startLoading: true, gameMode: true, dismiss: dismiss)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
#endif
    }
}

#Preview {
    SpaceDetailEditor(editController: .preview, model: .preview)
        .environment(SpaceRoot.preview)
        .environment(ListModel.preview)
}
