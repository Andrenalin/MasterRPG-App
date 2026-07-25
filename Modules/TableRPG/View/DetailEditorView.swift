// @copyright André Trettin

import CoreRPG
import DiceRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import SwiftUI

struct DetailEditorView: View {
    let root: TableRootModel
    let model: TableModel

    var body: some View {
        DetailSelectionEditorView(root: root, model: model)
            .onChange(of: model.id, initial: true) {
                root.editController.editorModel.sheetRootModel?.reset(itemId: model.id)
            }

        if let sheetRootModel = root.editController.editorModel.sheetRootModel {
#if os(tvOS)
            SheetRootEditorView(
                root: root.rootController,
                sheetRootModel: sheetRootModel,
                headerTitle: String(localized: "Entries", bundle: .module),
                linkTypes: LinkTableModuleTransferable.self
            )
#else
            SheetRootEditorView(
                root: root.rootController,
                sheetRootModel: sheetRootModel,
                headerTitle: String(localized: "Entries", bundle: .module),
                linkTypes: LinkTableModuleTransferable.self,
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
    DetailEditorView(root: .preview, model: .preview)
}
