// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import GeneratorRPG
import SwiftUI

/// The single-character "Extract Information" sheet: name, description and tags generated from
/// the character's values and portrait by `CharacterSummaryAnalyzer`.
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
                entriesText: CharacterSheetText.text(for: model, photoRoot: root.photoRoot),
                itemName: model.name,
                notice: CharacterSheetText.hasPortraitText(for: model, photoRoot: root.photoRoot)
                    ? nil
                    : LocalizedStringResource("Add a photo description and tags to improve the character information", bundle: .module)
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
