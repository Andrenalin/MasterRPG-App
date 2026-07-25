// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailEditorView: View {
    let root: AdventureRootModel
    let model: AdventureModel

    var body: some View {
        DetailSelectionEditorView(root: root, model: model)
            .onChange(of: model.id, initial: true) {
                root.editController.editorModel.sheetRootModel?.reset(itemId: model.id)
            }

        if let rootModel = root.editController.editorModel.sheetRootModel {
            SheetRootEditorView(
                root: root.rootController,
                sheetRootModel: rootModel,
                headerTitle: String(localized: "Sections", bundle: .module).localizedString,
                linkTypes: LinkAdventureModuleTransferable.self
            )
        }
    }
}

#Preview(traits: .mockData) { DetailEditorView(root: .preview, model: .preview) }
