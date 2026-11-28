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

    /// The same text the batch analyzes (`compactText(for:)`): markdown links reduced to their labels.
    private func formatEntries(_ model: AdventureModel) -> String {
        TextSummaryExtractionFormatter.formatEntries(
            title: "Adventure",
            name: model.name,
            entries: model.entries.map { ($0.name.withoutLink(), $0.content.withoutLink()) }
        )
    }
}

#Preview(traits: .mockData) {
    AdventureExtractionDestination(itemId: AdventureModel.previewId)
}
#endif
