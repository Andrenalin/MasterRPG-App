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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: itemRootController.configurable.module.icon)
                    .foregroundStyle(itemRootController.configurable.module.tint)

                Text(result.itemName)
                    .font(.headline)

                if !result.categoryName.isEmpty {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(result.categoryName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let entryName = result.entryName {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(entryName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let matchedContent = result.matchedContent {
                Text(matchedContent)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    var itemRootController: ItemRootController {
        switch result.module {
        case .adventure:
            root.adventureRoot.rootController
        case .audio:
            root.audioRoot.rootController
        case .value:
            root.characterRoot.rootController
        case .dice:
            root.diceRoot.rootController
        case .map:
            root.mapRoot.rootController
        case .pdf:
            root.pdfRoot.rootController
        case .photo:
            root.photoRoot.rootController
        case .space:
            root.spaceRoot.rootController
        case .table:
            root.tableRoot.rootController
        case .weather:
            root.weatherRoot.rootController
        default:
            root.adventureRoot.rootController
        }
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
                categoryName: "Dungeons",
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
                categoryName: "Magic Items",
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
                categoryName: "World Maps",
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
                categoryName: "Players",
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
                categoryName: "Soundtracks",
                entryId: nil,
                entryName: nil,
                matchedContent: "Epic orchestral music for combat encounters",
                relevanceScore: 50
            ),
            root: GameRoot.preview
        )
    }
}
