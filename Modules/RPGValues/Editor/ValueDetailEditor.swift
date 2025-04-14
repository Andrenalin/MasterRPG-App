// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct ValueDetailEditor: View {
    let editController: EditController
    let model: ValueModel

    @Environment(ValueRoot.self) private var root
    @Environment(\.wideMode) private var wideMode
    
    @State private var changeChildModel = ChangeChildModel()
    @State private var changeGeneratorModel = ChangeGeneratorModel()

    var body: some View {
        //        let _ = Self._printChanges()
        @Bindable var model = model
        DetailEditor(editController: editController) {
            HeaderEditor(editController: editController)
            
            PhotoSelectionEditor(editController: editController)

            SpecialEditor(editController: editController)

#if !os(macOS)
            ValueEntrySectionEditor(editController: editController, changeChildModel: changeChildModel, changeGeneratorModel: changeGeneratorModel)
#endif
        } headerView: { size, safeTopMargin, isInline in
            ValueDetailHeader(model: model, size: size, topMargin: safeTopMargin, inline: isInline)
        } extHeaderView: { dismiss in
            CharacterSheet(model: editController.model, showTopImage: false, dismissAction: dismiss)
        } extContentView: {
#if !os(tvOS)
            ValueEntryEditor(root: root, editController: editController, changeChildModel: changeChildModel)
#endif
        } extContentHeight: { screenHeight in
            let minHeight = Double(model.entries.count * 128)
            return min(max(minHeight, screenHeight * 0.5), screenHeight)
        } heightCalculator: { size in
            (144, min(size.height * 0.35, 400))
        }
        .modifier(ChangeChildEditorViewModifier(editController: editController, model: changeChildModel))
        .modifier(ChangeGeneratorEditorViewModifier(model: changeGeneratorModel))
        .focusedSceneValue(\.selectedValue, $model.id)
    }
    
    private var photoId: Binding<UUID> {
        Binding { model.photoId ?? UUID() } set: { _ in }
    }
}

#Preview {
    ValueDetailEditor(editController: .preview, model: .preview)
        .environment(ValueRoot.preview)
}
