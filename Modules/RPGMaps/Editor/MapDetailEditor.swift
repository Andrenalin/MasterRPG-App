// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct MapDetailEditor: View {
    let editController: EditController
    let model: MapModel

    @Environment(MapRoot.self) private var root
    
    var body: some View {
        @Bindable var model = model
        //let _ = Self._printChanges()

        DetailEditor(editController: editController) {

            HeaderEditor(editController: editController)
            
            PhotoSelectionEditor(editController: editController)

            DisplayConfigEditor(editController: editController)

            SpecialEditor(editController: editController)

#if !os(macOS)
            MapEntrySectionEditor(editController: editController)
            
            MapPinSectionEditor(editController: editController)
#endif
        } headerView: { size, safeTopMargin, isInline in
            AnimatedHeaderMap(editController: editController, size: size, topMargin: safeTopMargin, inline: isInline)
        } extHeaderView: { dismiss in
            MapSheet(model: editController.model, showTopImage: false, dismissAction: dismiss)
                .environment(\.showGame, false)
        } extContentView: {
#if !os(tvOS)
            MapEntryEditor(root: root, editController: editController)

            MapPinEditor(root: root, editController: editController)
#endif
        } extContentHeight: { screenHeight in
            let minHeight = Double(model.entries.count * 128 + model.mapPins.count * 64)
            return min(max(minHeight, screenHeight * 0.5), screenHeight)
        } heightCalculator: { size in
            (144, min(size.height * 0.35, 400))
        }
        .focusedSceneValue(\.selectedMap, $model.id)
    }
}

#Preview {
    MapDetailEditor(editController: .preview, model: .preview)
        .environment(MapRoot.previewWithData)
        .environment(ListModel.preview)
}
