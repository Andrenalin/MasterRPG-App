// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailEditorView: View {
    let root: CharacterRootModel
    let model: ValueModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        DetailSelectionEditorView(root: root, model: model)
            // TODO: .task swallows updates further down, causing a double creation on
            // start — accepted for now. See CODE_AUDIT_Character §9.16.
            .onChange(of: model.id, initial: true) {
                root.editorLinkModel.characterSelectionModel.onlyChildrenFrom <=> model.id
                root.editController.editorModel.sheetRootModel?.reset(itemId: model.id)
            }

        if let rootModel = root.editController.editorModel.sheetRootModel {
            SheetRootEditorView(
                root: root.rootController,
                sheetRootModel: rootModel,
                headerTitle: String(localized: "Values", bundle: .module).localizedString,
                linkTypes: LinkCharacterModuleTransferable.self
            )
        }
    }
}

#Preview(traits: .mockData) { DetailEditorView(root: .preview, model: .preview) }
