// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import GeneratorRPG
import SwiftUI

struct MapExtractionDestination: View {
    let itemId: UUID

    @Environment(MapRootModel.self) private var root

    var body: some View {
        let model = root.itemController.itemOrEmpty(for: itemId)
        let visibleEntries = model.entries.filter { !$0.isHexGrid }
        if visibleEntries.isEmpty {
            ContentUnavailableView {
                Label {
                    Text("No Rooms", bundle: .module)
                } icon: {
                    Image(systemName: "mappin.slash")
                }
            } description: {
                Text("This map has no rooms to analyze.", bundle: .module)
            }
        } else {
            TextSummaryExtractionView(
                module: .map,
                entriesText: formatEntries(model, entries: visibleEntries)
            ) { content, selection in
                root.editController.applyExtractedContent(content, to: itemId, selection: selection)
            }
        }
    }

    private func formatEntries(_ model: MapModel, entries: [MapEntryModel]) -> String {
        var lines: [String] = []
        if !model.name.isEmpty {
            lines.append("Map: \(model.name)")
            lines.append("")
        }
        for entry in entries {
            lines.append(entry.content.isEmpty ? "- \(entry.name)" : "- \(entry.name): \(entry.content)")
        }
        return lines.joined(separator: "\n")
    }
}

#Preview(traits: .mockData) {
    MapExtractionDestination(itemId: MapModel.previewEmptyId)
}
#endif
