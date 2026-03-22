// @copyright André Trettin

import CoreRPG
import Foundation

struct SearchController: Sendable {
    let itemController: ItemController
}

extension SearchController: SearchControllable {
    var itemControllable: any ItemControllable { itemController }
    
    func searchItems(searchText: String) async -> [SearchResult] {
        guard searchText.isEmpty == false else { return [] }
        
        let itemIds = await itemControllable.itemDataModel.items
        var foundResults: [SearchResult] = []

        for itemId in itemIds {
            guard !Task.isCancelled else { break }

            guard let item = await itemController.item(for: itemId), item.parentId == nil else { continue }
            await result(item: item, searchText: searchText, foundResults: &foundResults)
        }

        // Sort by relevance score (highest first)
        return foundResults.sorted { $0.relevanceScore > $1.relevanceScore }
    }
    
    func result(item: ValueModel, searchText: String, foundResults: inout [SearchResult]) async {
        // Check if item matches search
        let itemMatches = item.filter(filter: searchText, includeEntries: false)

        if itemMatches {
            let relevance = calculateRelevance(
                searchText: searchText,
                itemName: item.name,
                entryName: nil,
                content: item.description,
                isItemMatch: true
            )
            foundResults.append(SearchResult(
                itemId: item.id,
                itemName: item.name,
                module: itemControllable.config.module,
                category: item.category,
                entryId: nil,
                entryName: nil,
                matchedContent: item.description.isEmpty ? nil : item.description,
                relevanceScore: relevance
            ))
        }

        if !item.specialCategory {
            // Search through entries
            for entry in item.entries {
                guard !Task.isCancelled else { break }

                if entry.filter(with: searchText) {
                    let relevance = calculateRelevance(
                        searchText: searchText,
                        itemName: item.name,
                        entryName: entry.name,
                        content: entry.content,
                        isItemMatch: false
                    )
                    foundResults.append(SearchResult(
                        itemId: item.id,
                        itemName: item.name,
                        module: itemControllable.config.module,
                        category: item.category,
                        entryId: entry.id,
                        entryName: entry.name,
                        matchedContent: entry.content.isEmpty ? nil : entry.content,
                        relevanceScore: relevance
                    ))
                }
                
                if let subValueId = entry.valueId {
                    guard let item = await itemController.item(for: subValueId) else { continue }
                    await result(item: item, searchText: searchText, foundResults: &foundResults)
                }
            }
        }
    }
}
