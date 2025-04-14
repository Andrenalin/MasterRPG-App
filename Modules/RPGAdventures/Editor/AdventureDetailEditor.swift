// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct AdventureDetailEditor: View {
    let editController: EditController
    let model: AdventureModel

    @Environment(AdventureRoot.self) private var root
    @Environment(\.wideMode) private var wideMode
    
    var body: some View {
        @Bindable var model = model
//        let _ = Self._printChanges()
//        let _ = print("AdventureDetailEditor: \(Unmanaged.passUnretained(editController.cacheItemListModel).toOpaque())")
        
        DetailEditor(editController: editController) {
            HeaderEditor(editController: editController)

            PhotoSelectionEditor(editController: editController)
            
            SpecialEditor(editController: editController)

#if !os(macOS)
            AdventureEntrySectionEditor(editController: editController)
#endif
        } headerView: { size, safeTopMargin, isInline in
            AdventureDetailHeader(editController: editController, model: model, size: size, topMargin: safeTopMargin, inline: isInline)
#if !os(macOS)
                .ignoresSafeArea(.container, edges: .top)
#endif
        } extHeaderView: { dismiss in
            AdventureSheet(model: editController.model, showImage: false, dismissAction: dismiss)
        } extContentView: {
#if !os(tvOS)
            AdventureEntryEditor(root: root, editController: editController)
#endif
        } extContentHeight: { screenHeight in
            let minHeight = Double(model.entries.count * 128)
            return min(max(minHeight, screenHeight * 0.5), screenHeight)
        } heightCalculator: { size in
            (144, min(size.height * 0.35, 400))
        }
        .focusedSceneValue(\.selectedAdventure, $model.id)
    }
    
    private var photoId: Binding<UUID> {
        Binding { model.photoId ?? UUID() } set: { _ in }
    }
}

#Preview {
    AdventureDetailEditor(editController: .preview, model: .preview)
        .environment(AdventureRoot.previewWithData)
        .environment(ListModel.preview)
}
