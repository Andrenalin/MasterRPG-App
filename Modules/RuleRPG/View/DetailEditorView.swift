// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailEditorView: View {
    let root: RuleRootModel
    let model: RuleModel

    var body: some View {
        RuleMetadataEditor(root: root, model: model)
            .onChange(of: model.id, initial: true) {
                root.editController.editorModel.sheetRootModel?.reset(itemId: model.id)
            }
        if let sheetRootModel = root.editController.editorModel.sheetRootModel {
            SheetRootEditorView(
                root: root.rootController,
                sheetRootModel: sheetRootModel,
                headerTitle: String(localized: "Rule Sections", bundle: .ruleModule),
                linkTypes: LinkRuleModuleTransferable.self
            )
        }
    }
}

#Preview(traits: .mockData) {
    DetailEditorView(root: .preview, model: .preview)
}
