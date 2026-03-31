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
        var score = 0

        // Item name exact match (highest priority)
        if itemName.compare(searchText, options: .caseInsensitive) == .orderedSame {
            score += 100
        } else if itemName.range(of: searchText, options: [.caseInsensitive, .anchored]) != nil {
            // Prefix match
            score += 50
        } else if itemName.localizedStandardContains(searchText) {
            score += 25
        }

        // Entry name match (medium priority)
        if let entryName {
            if entryName.compare(searchText, options: .caseInsensitive) == .orderedSame {
                score += 80
            } else if entryName.range(of: searchText, options: [.caseInsensitive, .anchored]) != nil {
                // Prefix match
                score += 40
            } else if entryName.localizedStandardContains(searchText) {
                score += 20
            }
        }

        // Content match (lower priority)
        if let content, content.localizedStandardContains(searchText) {
            score += 10
        }

        // Boost item matches over entry matches
        if isItemMatch && entryName == nil {
            score += 15
        }

        return score
    }

    func searchInSheet(itemId: UUID, searchText: String, includeLinks: Bool = true) async -> SheetSearchResult {
        guard !searchText.isEmpty else {
            return SheetSearchResult(matchedEntries: [], expandedLinks: [:])
        }

        guard let item = await itemControllable.item(for: itemId) else {
            return SheetSearchResult(matchedEntries: [], expandedLinks: [:])
        }

        var matchedEntries: [SheetEntryMatch] = []
        var expandedLinks: [UUID: [UUID]] = [:]  // entryId -> [linked itemIds to expand]

        // Search through all entries
        for entry in item.entries {
            guard !Task.isCancelled else { break }

            var matchLocations: [SheetMatchLocation] = []

            // Check entry name
            if entry.name.localizedStandardContains(searchText) {
                matchLocations.append(.name)
            }

            // Check entry content
            if entry.content.localizedStandardContains(searchText) {
                matchLocations.append(.content)
            }

            // If includeLinks, search within linked items
            if includeLinks {
                
                let linkedItemIds = await extractLinkedItemIds(from: entry.content)

                for linkedItemId in linkedItemIds {
                    guard !Task.isCancelled else { break }

                    if let linkedItem = await itemControllable.item(for: linkedItemId) {
                        // Search in linked item
                        let linkHasMatch = await searchInLinkedItem(linkedItem, searchText: searchText)

                        if linkHasMatch {
                            // Mark that this link should be expanded
                            var links = expandedLinks[entry.id] ?? []
                            links.append(linkedItemId)
                            expandedLinks[entry.id] = links

                            // Add as link match location
                            matchLocations.append(.link(linkedItemId))
                        }
                    }
                }
            }

            // If we found any matches, add this entry to results
            if !matchLocations.isEmpty {
                let relevance = calculateSheetRelevance(
                    searchText: searchText,
                    entryName: entry.name,
                    content: entry.content,
                    matchLocations: matchLocations
                )

                matchedEntries.append(SheetEntryMatch(
                    entryId: entry.id,
                    entryName: entry.name,
                    matchLocations: matchLocations,
                    relevanceScore: relevance
                ))
            }
        }

        // Sort by relevance
        matchedEntries.sort { $0.relevanceScore > $1.relevanceScore }

        return SheetSearchResult(matchedEntries: matchedEntries, expandedLinks: expandedLinks)
    }

    // MARK: - Private Helper Methods

    private func extractLinkedItemIds(from content: String) async -> [UUID] {
        // Use existing LinkReplaceController to extract all links
        let links = await LinkReplaceController.links(for: content)

        // Extract item IDs from the links
        return links.map { $0.itemId }
    }

    private func searchInLinkedItem(_ item: any ItemDataAccessable, searchText: String) async -> Bool {
        // Check item name
        if item.name.localizedStandardContains(searchText) {
            return true
        }

        // Check item description
        if item.description.localizedStandardContains(searchText) {
            return true
        }

        // Check entries
        for entry in item.entries {
            if entry.name.localizedStandardContains(searchText) ||
               entry.content.localizedStandardContains(searchText) {
                return true
            }
        }

        return false
    }

    private func calculateSheetRelevance(
        searchText: String,
        entryName: String,
        content: String,
        matchLocations: [SheetMatchLocation]
    ) -> Int {
        var score = 0

        // Base score from match locations
        for location in matchLocations {
            switch location {
            case .name:
                score += 100
            case .content:
                score += 50
            case .link:
                score += 30  // Lower priority for matches in links
            }
        }

        // Entry name relevance
        if entryName.compare(searchText, options: .caseInsensitive) == .orderedSame {
            score += 80
        } else if entryName.range(of: searchText, options: [.caseInsensitive, .anchored]) != nil {
            score += 40
        }

        // Content relevance
        if content.localizedStandardContains(searchText) {
            score += 20
        }

        return score
    }
}

// MARK: - Sheet Search Result Models

public struct SheetSearchResult: Sendable {
    public let matchedEntries: [SheetEntryMatch]
    public let expandedLinks: [UUID: [UUID]]  // entryId -> [itemIds to expand]

    public init(matchedEntries: [SheetEntryMatch], expandedLinks: [UUID: [UUID]]) {
        self.matchedEntries = matchedEntries
        self.expandedLinks = expandedLinks
    }
}

public struct SheetEntryMatch: Identifiable, Sendable {
    public let entryId: UUID
    public let entryName: String
    public let matchLocations: [SheetMatchLocation]
    public let relevanceScore: Int

    public var id: UUID { entryId }

    public init(entryId: UUID, entryName: String, matchLocations: [SheetMatchLocation], relevanceScore: Int) {
        self.entryId = entryId
        self.entryName = entryName
        self.matchLocations = matchLocations
        self.relevanceScore = relevanceScore
    }
}

public enum SheetMatchLocation: Equatable, Sendable {
    case name
    case content
    case link(UUID)  // UUID of the linked item where match was found
}
