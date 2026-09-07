// @copyright André Trettin

import SwiftUI

struct RuleSourceDisclosureView: View, Equatable {
    let metadata: RuleSourceMetadata

    var body: some View {
#if os(tvOS)
        VStack(alignment: .leading) {
            Label {
                Text("Rule Source", bundle: .ruleModule)
            } icon: {
                Image(systemName: "shippingbox")
            }
            RuleSourceMetadataGrid(metadata: metadata)
        }
        .padding()
#else
        DisclosureGroup {
            RuleSourceMetadataGrid(metadata: metadata)
        } label: {
            Label {
                Text("Rule Source", bundle: .ruleModule)
            } icon: {
                Image(systemName: "shippingbox")
            }
        }
        .padding()
#endif
    }
}

private struct RuleSourceMetadataGrid: View {
    let metadata: RuleSourceMetadata

    var body: some View {
        Grid(alignment: .leading) {
            RuleSourceMetadataRow(title: "Source Identifier", value: metadata.sourceIdentifier)
            RuleSourceMetadataRow(title: "System", value: metadata.systemTitle)
            RuleSourceMetadataRow(title: "System ID", value: metadata.systemID)
            RuleSourceMetadataRow(title: "Version", value: metadata.systemVersion)
            RuleSourceMetadataRow(title: "Package", value: metadata.packageName)
            RuleSourceMetadataRow(title: "Package Identifier", value: metadata.packageIdentifier)
            RuleSourceMetadataRow(title: "Document ID", value: metadata.documentID)
            RuleSourceMetadataRow(title: "Document Type", value: metadata.documentType)
            RuleSourceMetadataRow(title: "Subtype", value: metadata.subtype)
            RuleSourceMetadataRow(title: "Category", value: metadata.ruleCategory)
            RuleSourceMetadataRow(title: "Image Path", value: metadata.imagePath)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RuleSourceMetadataRow: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        if !value.isEmpty {
            GridRow {
                Text(title)
                    .foregroundStyle(.secondary)
#if os(tvOS)
                Text(verbatim: value)
#else
                Text(verbatim: value)
                    .textSelection(.enabled)
#endif
            }
        }
    }
}

#Preview {
    RuleSourceDisclosureView(metadata: RuleModel.preview.sourceMetadata)
}
