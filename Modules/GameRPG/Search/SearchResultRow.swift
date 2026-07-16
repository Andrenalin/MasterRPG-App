// @copyright André Trettin

import CoreRPG
import SwiftUI
import AdventureRPG
import MapRPG
import TableRPG
import AudioRPG
import CharacterRPG
import PdfRPG
import DiceRPG
import PhotoRPG
import WeatherRPG
import SpaceRPG

struct SearchResultRow: View {
    let result: SearchResult
    let root: GameRoot

    var body: some View {
        let controller = root.rootController(for: result.module)
        let module = controller.configurable.module

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: module.icon)
                    .foregroundStyle(module.tint)

                Text(result.itemName)
                    .font(.headline)

                Text(verbatim: "·")
                    .foregroundStyle(.secondary)
                Image(systemName: result.category.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
            }

            if let entryName = result.entryName,
               let matchedContent = result.matchedContent {
                Text(verbatim: "\(entryName): \(matchedContent)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if let matchedContent = result.matchedContent {
                Text(matchedContent)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview("Item Result") {
    List {
        SearchResultRow(
            result: SearchResult(
                itemId: GamePreviewData.searchItemID,
                itemName: "Dragon's Lair",
                module: .adventure,
                category: .entry,
                entryId: nil,
                entryName: nil,
                matchedContent: "A dangerous cave filled with treasure and a fearsome dragon guarding its hoard.",
                relevanceScore: 85
            ),
            root: .previewFixture()
        )
    }
}

#Preview("Entry Result") {
    List {
        SearchResultRow(
            result: SearchResult(
                itemId: GamePreviewData.searchItemID,
                itemName: "Spellbook of Mysteries",
                module: .pdf,
                category: .collection,
                entryId: GamePreviewData.searchEntryID,
                entryName: "Fireball Spell",
                matchedContent: "A devastating fire spell that creates an explosion dealing massive damage to all creatures in the area.",
                relevanceScore: 92
            ),
            root: .previewFixture()
        )
    }
}

#Preview("Multiple Results") {
    let root = GameRoot.previewFixture()
    List {
        SearchResultRow(
            result: SearchResult(
                itemId: GamePreviewData.searchItemID,
                itemName: "Ancient Map",
                module: .map,
                category: .entry,
                entryId: nil,
                entryName: nil,
                matchedContent: nil,
                relevanceScore: 65
            ),
            root: root
        )

        SearchResultRow(
            result: SearchResult(
                itemId: GamePreviewData.secondSearchItemID,
                itemName: "Character Sheet",
                module: .value,
                category: .folder,
                entryId: GamePreviewData.secondSearchEntryID,
                entryName: "Strength Score",
                matchedContent: "Base strength value: 16",
                relevanceScore: 78
            ),
            root: root
        )

        SearchResultRow(
            result: SearchResult(
                itemId: GamePreviewData.photoID,
                itemName: "Battle Music",
                module: .audio,
                category: .collection,
                entryId: nil,
                entryName: nil,
                matchedContent: "Epic orchestral music for combat encounters",
                relevanceScore: 50
            ),
            root: root
        )
    }
}
