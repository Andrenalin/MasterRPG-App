// @copyright André Trettin

import Foundation
import Observation

public protocol SearchControllable: Sendable  {
    var itemControllable: any ItemControllable { get }
    
    func searchItems(searchText: String) async -> [SearchResult]
    func calculateRelevance(searchText: String, itemName: String, entryName: String?, content: String?, isItemMatch: Bool) -> Int
}

public extension SearchControllable {
    func searchItems(searchText: String) async -> [SearchResult] {
        guard searchText.isEmpty == false else { return [] }
        
        let itemIds = await itemControllable.itemDataModel.items
        var foundResults: [SearchResult] = []

        for itemId in itemIds {
            guard !Task.isCancelled else { break }

            guard let item = await itemControllable.item(for: itemId) else { continue }

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
                }
            }
        }

        // Sort by relevance score (highest first)
        return foundResults.sorted { $0.relevanceScore > $1.relevanceScore }
    }
    
    func calculateRelevance(searchText: String, itemName: String, entryName: String?, content: String?, isItemMatch: Bool) -> Int {
        let search = searchText.lowercased()
        var score = 0

        // Item name exact match (highest priority)
        if itemName.lowercased() == search {
            score += 100
        } else if itemName.lowercased().hasPrefix(search) {
            score += 50
        } else if itemName.lowercased().contains(search) {
            score += 25
        }

        // Entry name match (medium priority)
        if let entryName {
            if entryName.lowercased() == search {
                score += 80
            } else if entryName.lowercased().hasPrefix(search) {
                score += 40
            } else if entryName.lowercased().contains(search) {
                score += 20
            }
        }

        // Content match (lower priority)
        if let content {
            if content.lowercased().contains(search) {
                score += 10
            }
        }

        // Boost item matches over entry matches
        if isItemMatch && entryName == nil {
            score += 15
        }

        return score
    }
}
