// @copyright André Trettin

import SwiftUI

struct RuleMetadataEditor: View {
    let root: RuleRootModel
    let model: RuleModel

    var body: some View {
        Section {
            TextField("Source Identifier", text: binding(\.sourceIdentifier))
            TextField("System", text: binding(\.systemTitle))
            TextField("System ID", text: binding(\.systemID))
            TextField("Version", text: binding(\.systemVersion))
            TextField("Package", text: binding(\.packageName))
            TextField("Package Identifier", text: binding(\.packageIdentifier))
            TextField("Document ID", text: binding(\.documentID))
            TextField("Document Type", text: binding(\.documentType))
            TextField("Subtype", text: binding(\.subtype))
            TextField("Rule Category", text: binding(\.ruleCategory))
            TextField("Image Path", text: binding(\.imagePath))
            if model.sourcePayload != nil {
                LabeledContent("Normalized Source") {
                    Label("Retained", systemImage: "checkmark.shield")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Rule Source", bundle: .ruleModule)
        } footer: {
            if model.sourcePayload != nil {
                Text(
                    "Editing source labels does not alter the retained normalized Foundry payload.",
                    bundle: .ruleModule
                )
            }
        }
    }

    private func binding(
        _ keyPath: WritableKeyPath<RuleSourceMetadata, String>
    ) -> Binding<String> {
        Binding {
            model.sourceMetadata[keyPath: keyPath]
        } set: { value in
            var metadata = model.sourceMetadata
            metadata[keyPath: keyPath] = value
            root.editController.reset(sourceMetadata: metadata, itemId: model.id)
        }
    }
}

#Preview(traits: .mockData) {
    RuleMetadataEditor(root: .preview, model: .preview)
}
