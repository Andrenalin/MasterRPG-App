// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import GeneratorRPG
import SwiftUI

/// The single-character "Extract Information" sheet: title, description and tags generated from
/// the character's values, the same on-device extraction as Table, Map and Adventure.
struct CharacterExtractionDestination: View {
    let itemId: UUID

    @Environment(CharacterRootModel.self) private var root

    var body: some View {
        let model = root.itemController.itemOrEmpty(for: itemId)
        let visibleEntries = model.entries.filter { !$0.isGroupHidden }
        if visibleEntries.isEmpty {
            ContentUnavailableView {
                Label {
                    Text("No Entries", bundle: .module)
                } icon: {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                }
            } description: {
                Text("This character has no entries to analyze.", bundle: .module)
            }
        } else {
            TextSummaryExtractionView(
                module: .value,
                entriesText: TextSummaryExtractionFormatter.formatEntries(
                    title: String(localized: "Character", bundle: .module),
                    name: model.name,
                    // Values are formulas and links to other values; the model needs the labels,
                    // not the link URLs, which would only use up its input budget.
                    entries: visibleEntries.map { ($0.name.withoutLink(), $0.content.withoutLink()) }
                )
            ) { content, selection in
                root.editController.applyExtractedContent(content, to: itemId, selection: selection)
            }
        }
    }
}

#Preview(traits: .mockData) {
    CharacterExtractionDestination(itemId: ValueModel.previewId)
}

#endif
