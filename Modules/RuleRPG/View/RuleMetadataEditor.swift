// @copyright André Trettin

import SwiftUI

struct RuleMetadataEditor: View {
    let root: RuleRootModel
    let model: RuleModel

    var body: some View {
        Section {
            TextField(
                String(localized: "Source Identifier", bundle: .ruleModule),
                text: binding(\.sourceIdentifier)
            )
            TextField(
                String(localized: "System", bundle: .ruleModule),
                text: binding(\.systemTitle)
            )
            TextField(
                String(localized: "System ID", bundle: .ruleModule),
                text: binding(\.systemID)
            )
            TextField(
                String(localized: "Version", bundle: .ruleModule),
                text: binding(\.systemVersion)
            )
            TextField(
                String(localized: "Package", bundle: .ruleModule),
                text: binding(\.packageName)
            )
            TextField(
                String(localized: "Package Identifier", bundle: .ruleModule),
                text: binding(\.packageIdentifier)
            )
            TextField(
                String(localized: "Document ID", bundle: .ruleModule),
                text: binding(\.documentID)
            )
            TextField(
                String(localized: "Document Type", bundle: .ruleModule),
                text: binding(\.documentType)
            )
            TextField(
                String(localized: "Subtype", bundle: .ruleModule),
                text: binding(\.subtype)
            )
            TextField(
                String(localized: "Rule Category", bundle: .ruleModule),
                text: binding(\.ruleCategory)
            )
            TextField(
                String(localized: "Image Path", bundle: .ruleModule),
                text: binding(\.imagePath)
            )
            if model.sourcePayload != nil {
                LabeledContent(
                    String(localized: "Normalized Source", bundle: .ruleModule)
                ) {
                    Label(
                        String(localized: "Retained", bundle: .ruleModule),
                        systemImage: "checkmark.shield"
                    )
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
