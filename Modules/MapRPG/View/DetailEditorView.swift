// @copyright André Trettin

import CoreRPG
#if !os(tvOS)
import GeneratorRPG
#endif
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
#if os(tvOS)
            SheetRootEditorView(
                root: root.rootController,
                sheetRootModel: sheetRootModel,
                headerTitle: String(localized: "Rooms", bundle: .module).localizedString,
                linkTypes: LinkMapModuleTransferable.self
            )
#else
            SheetRootEditorView(
                root: root.rootController,
                sheetRootModel: sheetRootModel,
                headerTitle: String(localized: "Rooms", bundle: .module).localizedString,
                linkTypes: LinkMapModuleTransferable.self,
                configuration: .init(showsAIAssistant: true),
                aiAssistantContent: {
                    SheetAIAssistantContent(
                        module: root.configurable.module,
                        itemId: model.id,
                        rootModel: sheetRootModel
                    )
                }
            )
#endif
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
