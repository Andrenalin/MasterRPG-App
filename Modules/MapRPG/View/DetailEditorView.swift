// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

struct DetailEditorView: View {
    let root: MapRootModel
    let model: MapModel

    var body: some View {
        DetailSelectionEditorView(root: root, model: model)
            .onChange(of: model.id, initial: true) {
                root.editController.editorModel.sheetRootModel?.reset(itemId: model.id)
            }

        DisplayConfigEditor(model: model)

        if let sheetRootModel = root.editController.editorModel.sheetRootModel {
            SheetRootEditorView(
                root: root.rootController,
                sheetRootModel: sheetRootModel,
                headerTitle: String(localized: "Rooms", bundle: .module).localizedString,
                linkTypes: LinkMapModuleTransferable.self
            )
        }
    }
}

#Preview(traits: .mockData) {
    let root = MapRootModel.previewFixture()
    DetailEditorView(
        root: root,
        model: root.itemController.itemOrEmpty(for: MapModel.previewId)
    )
    .environment(root)
}
