// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import GeneratorRPG
import SwiftUI

struct TableExtractionDestination: View {
    let itemId: UUID

    @Environment(TableRootModel.self) private var root

    var body: some View {
        let model = root.itemController.itemOrEmpty(for: itemId)
        if model.entries.isEmpty {
            ContentUnavailableView {
                Label {
                    Text("No Entries", bundle: .module)
                } icon: {
                    Image(systemName: "tablecells.badge.ellipsis")
                }
            } description: {
                Text("This table has no entries to analyze.", bundle: .module)
            }
        } else {
            TextSummaryExtractionView(module: .table, entriesText: formatEntries(model)) { content, selection in
                root.editController.applyExtractedContent(content, to: itemId, selection: selection)
            }
        }
    }

    private func formatEntries(_ model: TableModel) -> String {
        var lines: [String] = []
        if !model.name.isEmpty {
            let tableLabel = String(localized: "Table", bundle: .module)
            lines.append("\(tableLabel): \(model.name)")
            lines.append("")
        }
        for entry in model.entries {
            lines.append(entry.content.isEmpty ? "- \(entry.name)" : "- \(entry.name): \(entry.content)")
        }
        return lines.joined(separator: "\n")
    }
}

#Preview(traits: .mockData) {
    TableExtractionDestination(itemId: TableModel.previewId)
}

#endif
