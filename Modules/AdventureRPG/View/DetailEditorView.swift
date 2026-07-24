// @copyright André Trettin

import CoreRPG
#if !os(tvOS)
import GeneratorRPG
#endif
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
#if os(tvOS)
            SheetRootEditorView(
                root: root.rootController,
                sheetRootModel: rootModel,
                headerTitle: String(localized: "Sections", bundle: .module).localizedString,
                linkTypes: LinkAdventureModuleTransferable.self
            )
#else
            SheetRootEditorView(
                root: root.rootController,
                sheetRootModel: rootModel,
                headerTitle: String(localized: "Sections", bundle: .module).localizedString,
                linkTypes: LinkAdventureModuleTransferable.self,
                configuration: .init(showsAIAssistant: true),
                aiAssistantContent: {
                    SheetAIAssistantContent(
                        module: root.configurable.module,
                        itemId: model.id,
                        rootModel: rootModel
                    )
                }
            )
#endif
        }
    }
}

#Preview(traits: .mockData) { DetailEditorView(root: .preview, model: .preview) }
