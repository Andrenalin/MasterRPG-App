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

                Text("·")
                    .foregroundStyle(.secondary)
                Image(systemName: result.category.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
            }

            if let entryName = result.entryName,
               let matchedContent = result.matchedContent {
                Text("\(entryName): \(matchedContent)")
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
                itemId: UUID(),
                itemName: "Dragon's Lair",
                module: .adventure,
                category: .entry,
                entryId: nil,
                entryName: nil,
                matchedContent: "A dangerous cave filled with treasure and a fearsome dragon guarding its hoard.",
                relevanceScore: 85
            ),
            root: GameRoot.preview
        )
    }
}

#Preview("Entry Result") {
    List {
        SearchResultRow(
            result: SearchResult(
                itemId: UUID(),
                itemName: "Spellbook of Mysteries",
                module: .pdf,
                category: .collection,
                entryId: UUID(),
                entryName: "Fireball Spell",
                matchedContent: "A devastating fire spell that creates an explosion dealing massive damage to all creatures in the area.",
                relevanceScore: 92
            ),
            root: GameRoot.preview
        )
    }
}

#Preview("Multiple Results") {
    List {
        SearchResultRow(
            result: SearchResult(
                itemId: UUID(),
                itemName: "Ancient Map",
                module: .map,
                category: .entry,
                entryId: nil,
                entryName: nil,
                matchedContent: nil,
                relevanceScore: 65
            ),
            root: GameRoot.preview
        )

        SearchResultRow(
            result: SearchResult(
                itemId: UUID(),
                itemName: "Character Sheet",
                module: .value,
                category: .folder,
                entryId: UUID(),
                entryName: "Strength Score",
                matchedContent: "Base strength value: 16",
                relevanceScore: 78
            ),
            root: GameRoot.preview
        )

        SearchResultRow(
            result: SearchResult(
                itemId: UUID(),
                itemName: "Battle Music",
                module: .audio,
                category: .collection,
                entryId: nil,
                entryName: nil,
                matchedContent: "Epic orchestral music for combat encounters",
                relevanceScore: 50
            ),
            root: GameRoot.preview
        )
    }
}
