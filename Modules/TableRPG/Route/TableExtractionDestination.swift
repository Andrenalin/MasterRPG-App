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
            TextSummaryExtractionView(
                module: .table,
                entriesText: TextSummaryExtractionFormatter.formatEntries(
                    title: String(localized: "Table", bundle: .module),
                    name: model.name,
                    entries: model.entries.map { ($0.name, $0.content) }
                )
            ) { content, selection in
                root.editController.applyExtractedContent(content, to: itemId, selection: selection, forceSave: true)
            }
        }
    }
}

#Preview(traits: .mockData) {
    TableExtractionDestination(itemId: TableModel.previewId)
}

#endif
