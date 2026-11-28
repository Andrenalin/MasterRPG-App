// @copyright André Trettin

import CoreRPG
import Foundation

/// The shared `SearchControllable` search plus the level search ("level 4 adventures"), which
/// reads the level an adventure is written for from its level tag or its text.
struct SearchController: Sendable {
    let itemController: ItemController
}

extension SearchController: SearchControllable {
    var itemControllable: any ItemControllable { itemController }

    /// The visible adventures written for the searched level that also match the rest of the
    /// search text. An adventure for a narrow range ("level 4") comes before a wide band ("1-4").
    @MainActor func levelSearchResults(query: LevelSearchQuery) async -> [SearchResult] {
        guard query.filter.includes(.adventure) else { return [] }

        var results: [SearchResult] = []
        for itemId in itemController.itemDataModel.items {
            guard !Task.isCancelled else { break }
            guard let item = await itemController.item(for: itemId),
                  item.displayState == DisplayStateMask.fullVisible.rawValue,
                  !item.specialCategory,
                  itemMatchesFilter(item, searchText: query.text, displayMode: .regular),
                  let levels = AdventurePartyFacts.adventureLevels(tags: item.tags, name: item.name, description: item.description),
                  query.filter.matchesAdventure(levels: levels) else { continue }

            let textScore = query.text.isEmpty ? 100 : calculateRelevance(
                searchText: query.text,
                itemName: item.name,
                entryName: nil,
                content: item.description,
                isItemMatch: true
            )
            results.append(SearchResult(
                itemId: item.id,
                itemName: item.name,
                module: itemController.config.module,
                category: item.category,
                matchedContent: item.description.isEmpty ? nil : item.description,
                relevanceScore: textScore - (levels.count - 1)
            ))
        }
        return results.sortedByRelevance()
    }
}
