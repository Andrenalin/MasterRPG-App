// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct ValueDetailEditor: View {
    let editController: EditController
    let model: ValueModel

    @Environment(CharacterRootModel.self) private var root
    @Environment(\.wideMode) private var wideMode
    
    @State private var changeChildModel = ChangeChildModel()
    @State private var changeGeneratorModel = ChangeGeneratorModel()
    @State private var detailHeaderModel = DetailHeaderModel(minHeight: 144, maxHeight: 400, maxHeightFromScreenHeight: true)
    @State private var externalHeaderModel = ExternalHeaderModel()

    var body: some View {
        let _ = Self._printChanges()
        @Bindable var model = model
        DetailEditor(editController: editController) {
            HeaderEditor(editController: editController)
            
            PhotoSelectionEditor(editController: editController)

            SpecialEditor(editController: editController)

#if !os(macOS)
            ValueEntrySectionEditor(editController: editController, changeChildModel: changeChildModel, changeGeneratorModel: changeGeneratorModel)
#endif
        } headerView: {
            ValueDetailHeader(model: model)
        } extHeaderView: {
            ValueExternalHeader(editController: editController)
        } extContentView: {
#if !os(tvOS)
            ValueEntryEditor(root: root, editController: editController, changeChildModel: changeChildModel)
#endif
        }
        .modifier(ChangeChildEditorViewModifier(editController: editController, model: changeChildModel))
        .modifier(ChangeGeneratorEditorViewModifier(model: changeGeneratorModel))
        .environment(detailHeaderModel)
        .environment(externalHeaderModel)
        .onChange(of: model.entries, initial: true) {
            externalHeaderModel.minHeight = Double(model.entries.count * 128)
        }
    }
}

struct ValueExternalHeader: View {
    let editController: EditController

    @Environment(ExternalHeaderModel.self) private var externalHeaderModel

    var body: some View {
        CharacterSheet(model: editController.model, showTopImage: false) {
            externalHeaderModel.showExtHeader = false
        }
    }
}
#Preview {
    ValueDetailEditor(editController: .preview, model: .preview)
        .environment(CharacterRootModel.preview)
}
