// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailEditorView: View {
    let root: CharacterRootModel
    let model: ValueModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        DetailSelectionEditorView(root: root, model: model)
            // `onChange(initial:)` rather than `.task`: `.task` swallowed updates further down.
            // The cost is one extra sheet reset on start, which is harmless (the reset is
            // idempotent). See CODE_AUDIT_Character §9.16 and CODE_AUDIT_18 §9.6.
            .onChange(of: model.id, initial: true) {
                root.editorLinkModel.characterSelectionModel.onlyChildrenFrom <=> model.id
                root.editController.editorModel.sheetRootModel?.reset(itemId: model.id)
            }

        if let rootModel = root.editController.editorModel.sheetRootModel {
            SheetRootEditorView(
                root: root.rootController,
                sheetRootModel: rootModel,
                headerTitle: String(localized: "Values", bundle: .module),
                linkTypes: LinkCharacterModuleTransferable.self
            )
        }
    }
}

#Preview(traits: .mockData) { DetailEditorView(root: .preview, model: .preview) }
