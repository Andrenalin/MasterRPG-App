// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import GeneratorRPG
import SwiftUI

struct AdventureExtractionDestination: View {
    let itemId: UUID

    @Environment(AdventureRootModel.self) private var root

    var body: some View {
        let model = root.itemController.itemOrEmpty(for: itemId)
        if model.entries.isEmpty {
            ContentUnavailableView {
                Label {
                    Text("No Entries", bundle: .module)
                } icon: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
            } description: {
                Text("This adventure has no entries to analyze.", bundle: .module)
            }
        } else {
            TextSummaryExtractionView(module: .adventure, entriesText: formatEntries(model)) { content, selection in
                root.editController.applyExtractedContent(content, to: itemId, selection: selection)
            }
        }
    }

    private func formatEntries(_ model: AdventureModel) -> String {
        var lines: [String] = []
        if !model.name.isEmpty {
            lines.append("Adventure: \(model.name)")
            lines.append("")
        }
        for entry in model.entries {
            lines.append(entry.content.isEmpty ? "- \(entry.name)" : "- \(entry.name): \(entry.content)")
        }
        return lines.joined(separator: "\n")
    }
}

#Preview(traits: .mockData) {
    AdventureExtractionDestination(itemId: AdventureModel.previewId)
}
#endif
