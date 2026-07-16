// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import SwiftUI

struct TextSummaryUpdateView: View {
    let content: TableSummaryAnalysis
    let module: NetworkModules
    @Binding var selectedProperties: TextSummaryPropertySelection

    var body: some View {
        Form {
            Section {
                Text("Select which extracted values to apply on the \(String(localized: module.localizedTitle).lowercased()).", bundle: .module)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $selectedProperties.applyTitle) {
                    Text(verbatim: content.title)
                        .font(.body)
                }
            } header: {
                Text("Title", bundle: .module)
            }

            Section {
                Toggle(isOn: $selectedProperties.applyDescription) {
                    Text(verbatim: content.description)
                        .font(.body)
                        .lineLimit(3)
                }
            } header: {
                Text("Description", bundle: .module)
            }

            if !content.tags.isEmpty {
                Section {
                    Toggle(isOn: $selectedProperties.applyTags) {
                        FlowLayout(spacing: 8) {
                            ForEach(content.tags, id: \.self) { tag in
                                Text(verbatim: tag)
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor.opacity(0.2))
                                    .clipShape(.capsule)
                            }
                        }
                    }
                } header: {
                    Text("Tags", bundle: .module)
                }
            }
        }
#if os(macOS)
        .formStyle(.grouped)
#endif
    }
}

#Preview {
    @Previewable @State var selectedProperties = TextSummaryPropertySelection()

    TextSummaryUpdateView(
        content: TableSummaryAnalysis(
            title: "Forgotten Shrine Encounters",
            description: "Potential discoveries and dangers within an ancient shrine.",
            tags: ["ruins", "mystery"]
        ),
        module: .table,
        selectedProperties: $selectedProperties
    )
}

#endif
