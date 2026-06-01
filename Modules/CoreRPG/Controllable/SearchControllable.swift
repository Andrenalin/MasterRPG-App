// @copyright André Trettin

import Foundation
import Observation

public protocol SearchControllable: Sendable  {
    var itemControllable: any ItemControllable { get }

    func globalSearchResults(searchText: String) async -> [SearchResult]
    func calculateRelevance(searchText: String, itemName: String, entryName: String?, content: String?, isItemMatch: Bool) -> Int
    
    func listSearchResults(searchText: String, parentId: UUID?) async -> [SearchResult]
    func inspectorSearchResults(searchText: String, parentId: UUID?) async -> [SearchResult]
}

// MARK: - Global Search from Game View

public extension SearchControllable {
    func globalSearchResults(searchText: String) async -> [SearchResult] {
        guard searchText.isEmpty == false else { return [] }
        
        let itemIds = await itemControllable.itemDataModel.items
        var foundResults: [SearchResult] = []
        
        for itemId in itemIds {
            guard !Task.isCancelled else { break }
            
            guard let item = await itemControllable.item(for: itemId),
                  item.displayState == 0 else { continue }
            
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
            
        }
        
        return foundResults.sortedByRelevance()
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
}

// MARK: - List Search from ListRootView

public extension SearchControllable {
    func listSearchResults(searchText: String, parentId: UUID?) async -> [SearchResult] {

        var foundResults: [SearchResult] = []
        let itemIds: [UUID]
        if let parentId {
            itemIds = [parentId]
        } else {
            itemIds = await itemControllable.itemDataModel.items
        }
        
        for itemId in itemIds {
            guard !Task.isCancelled else { break }
            
            guard let item = await itemControllable.item(for: itemId),
                  item.displayState == 0 else { continue }

            // Check if item matches search
            let itemMatches = searchText.isEmpty ? true : item.filter(filter: searchText, includeEntries: false)
            
            if itemMatches {
                let relevance = searchText.isEmpty ? 100 : calculateRelevance(
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
            
        }
        
        return foundResults.sortedByRelevance()
    }
}

// MARK: - Inspector Search from LinkItemRootView

public extension SearchControllable {
    func inspectorSearchResults(searchText: String, parentId: UUID?) async -> [SearchResult] {
        guard !searchText.isEmpty else { return [] }
        let itemIds: [UUID]
        if let parentId {
            itemIds = [parentId]
        } else {
            itemIds =  await itemControllable.itemDataModel.items
        }
        var foundResults: [SearchResult] = []
        
        for itemId in itemIds {
            guard !Task.isCancelled else { break }
            
            guard let item = await itemControllable.item(for: itemId),
                  item.displayState == 0 else { continue }
            
            await inspectorResult(item: item, searchText: searchText, foundResults: &foundResults)
        }
        
        return foundResults.sortedByRelevance()
    }

    /// Searches `item` name/description and all its entries.
    /// For `specialCategory` items, recurses into child items via `entry.childId`.
    private func inspectorResult(item: any ItemDataAccessable, searchText: String, foundResults: inout [SearchResult]) async {
        guard !Task.isCancelled else { return }

        // Item-level match (name / description)
        if item.filter(filter: searchText, includeEntries: false) {
            foundResults.append(SearchResult(
                itemId: item.id,
                itemName: item.name,
                module: itemControllable.config.module,
                category: item.category,
                entryId: nil,
                entryName: nil,
                matchedContent: item.description.isEmpty ? nil : item.description,
                relevanceScore: calculateRelevance(
                    searchText: searchText,
                    itemName: item.name,
                    entryName: nil,
                    content: item.description,
                    isItemMatch: true
                )
            ))
        }

        // Entry-level search — always included (both regular items and folders)
        for entry in item.entries {
            guard !Task.isCancelled else { break }

            // Check name and content explicitly; entry.filter(with:) defaults to name-only
            // but module types may override it to include more fields.
            let entryMatches = entry.name.localizedCaseInsensitiveContains(searchText)
                            || entry.content.localizedCaseInsensitiveContains(searchText)

            if entryMatches {
                foundResults.append(SearchResult(
                    itemId: item.id,
                    itemName: item.name,
                    module: itemControllable.config.module,
                    category: item.category,
                    entryId: entry.id,
                    entryName: entry.name,
                    matchedContent: entry.content.isEmpty ? nil : entry.content,
                    relevanceScore: calculateRelevance(
                        searchText: searchText,
                        itemName: item.name,
                        entryName: entry.name,
                        content: entry.content,
                        isItemMatch: false
                    )
                ))
            }

            // For folder / collection items follow childId into child items
            if item.specialCategory,
               let childItem = await itemControllable.item(for: entry.childId) {
                await inspectorResult(item: childItem, searchText: searchText, foundResults: &foundResults)
            }
        }
    }
}

// MARK: - SearchResult sorting

extension Array where Element == SearchResult {
    // Primary: relevance descending. Tiebreaker: item name alphabetical.
    // Without the tiebreaker, equal-scored results fall back to Core Data iteration order
    // (arbitrary), making list-mode search appear unsorted even when scores are computed.
    func sortedByRelevance() -> [SearchResult] {
        sorted { a, b in
            if a.relevanceScore != b.relevanceScore {
                return a.relevanceScore > b.relevanceScore
            }
            return a.itemName.localizedCompare(b.itemName) == .orderedAscending
        }
    }
}

// All the code below is not checked (most likely broken, not working) or unused code

public extension SearchControllable {
    func searchInSheet(
        itemId: UUID,
        searchText: String,
        includeLinks: Bool = true,
        rootManager: RootManager? = nil
    ) async -> SheetSearchResult {
        guard !searchText.isEmpty else {
            return SheetSearchResult(matchedEntries: [], expandedLinks: [:], crossModuleMatches: [:])
        }

        guard let item = await itemControllable.item(for: itemId) else {
            return SheetSearchResult(matchedEntries: [], expandedLinks: [:], crossModuleMatches: [:])
        }

        var matchedEntries: [SheetEntryMatch] = []
        var expandedLinks: [UUID: [UUID]] = [:]  // entryId -> [linked itemIds to expand]
        var crossModuleMatches: [UUID: [CrossModuleMatch]] = [:]  // entryId -> [cross-module matches]

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
                let links = await extractLinksWithModules(from: entry.content)

                for link in links {
                    guard !Task.isCancelled else { break }

                    // Determine which controllable to use based on the link's module
                    let searchControllable: (any SearchControllable)?
                    
                    if link.module == itemControllable.config.module {
                        // Same module - use current controllable
                        searchControllable = self
                    } else if let rootManager {
                        // Cross-module - get the appropriate controllable
                        searchControllable = await rootManager.rootModel(for: link.module)?.rootController.searchControllable
                    } else {
                        searchControllable = nil
                    }

                    guard let searchControllable else { continue }

                    if let linkedItem = await searchControllable.itemControllable.item(for: link.itemId) {
                        // Search in linked item (check both item and entries)
                        let linkMatchResult = await searchInLinkedItem(
                            linkedItem,
                            searchText: searchText,
                            searchControllable: searchControllable
                        )

                        if linkMatchResult.hasMatch {
                            // Mark that this link should be expanded
                            var links = expandedLinks[entry.id] ?? []
                            links.append(link.itemId)
                            expandedLinks[entry.id] = links

                            // Add as link match location
                            matchLocations.append(.link(link.itemId, link.module))

                            // Store cross-module match details if applicable
                            if link.module != itemControllable.config.module {
                                var matches = crossModuleMatches[entry.id] ?? []
                                matches.append(CrossModuleMatch(
                                    linkedItemId: link.itemId,
                                    linkedModule: link.module,
                                    matchedInItemName: linkMatchResult.matchedInItemName,
                                    matchedInItemDescription: linkMatchResult.matchedInItemDescription,
                                    matchedEntryIds: linkMatchResult.matchedEntryIds
                                ))
                                crossModuleMatches[entry.id] = matches
                            }
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

        return SheetSearchResult(
            matchedEntries: matchedEntries,
            expandedLinks: expandedLinks,
            crossModuleMatches: crossModuleMatches
        )
    }

    // MARK: - Private Helper Methods

    /// Extract linked items with their module information
    private func extractLinksWithModules(from content: String) async -> [LinkInfo] {
        // Use existing LinkReplaceController to extract all links
        let links = await LinkReplaceController.links(for: content)

        // Convert to LinkInfo with module information
        return links.map { LinkInfo(itemId: $0.itemId, module: $0.module) }
    }

    /// Legacy method for backwards compatibility
    private func extractLinkedItemIds(from content: String) async -> [UUID] {
        let links = await extractLinksWithModules(from: content)
        return links.map { $0.itemId }
    }

    /// Search in a linked item and return detailed match information
    private func searchInLinkedItem(
        _ item: any ItemDataAccessable,
        searchText: String,
        searchControllable: any SearchControllable
    ) async -> LinkedItemMatchResult {
        var matchedInItemName = false
        var matchedInItemDescription = false
        var matchedEntryIds: [UUID] = []

        // Check item name
        if item.name.localizedStandardContains(searchText) {
            matchedInItemName = true
        }

        // Check item description
        if item.description.localizedStandardContains(searchText) {
            matchedInItemDescription = true
        }

        // Check entries
        for entry in item.entries {
            if entry.name.localizedStandardContains(searchText) ||
               entry.content.localizedStandardContains(searchText) {
                matchedEntryIds.append(entry.id)
            }
        }

        return LinkedItemMatchResult(
            matchedInItemName: matchedInItemName,
            matchedInItemDescription: matchedInItemDescription,
            matchedEntryIds: matchedEntryIds
        )
    }

    /// Legacy method for backwards compatibility
    private func searchInLinkedItem(_ item: any ItemDataAccessable, searchText: String) async -> Bool {
        let result = await searchInLinkedItem(item, searchText: searchText, searchControllable: self)
        return result.hasMatch
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
            case .link(_, let module):
                // Cross-module links get slightly lower priority
                score += (module == itemControllable.config.module) ? 30 : 25
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

// MARK: - Supporting Types

/// Information about a link with its module
struct LinkInfo: Sendable {
    let itemId: UUID
    let module: NetworkModules
}

/// Result of searching in a linked item
struct LinkedItemMatchResult: Sendable {
    let matchedInItemName: Bool
    let matchedInItemDescription: Bool
    let matchedEntryIds: [UUID]

    var hasMatch: Bool {
        matchedInItemName || matchedInItemDescription || !matchedEntryIds.isEmpty
    }
}

// MARK: - Sheet Search Result Models

public struct SheetSearchResult: Sendable {
    public let matchedEntries: [SheetEntryMatch]
    public let expandedLinks: [UUID: [UUID]]  // entryId -> [itemIds to expand]
    public let crossModuleMatches: [UUID: [CrossModuleMatch]]  // entryId -> cross-module details

    public init(
        matchedEntries: [SheetEntryMatch],
        expandedLinks: [UUID: [UUID]],
        crossModuleMatches: [UUID: [CrossModuleMatch]] = [:]
    ) {
        self.matchedEntries = matchedEntries
        self.expandedLinks = expandedLinks
        self.crossModuleMatches = crossModuleMatches
    }
}

public struct CrossModuleMatch: Sendable {
    public let linkedItemId: UUID
    public let linkedModule: NetworkModules
    public let matchedInItemName: Bool
    public let matchedInItemDescription: Bool
    public let matchedEntryIds: [UUID]

    public init(
        linkedItemId: UUID,
        linkedModule: NetworkModules,
        matchedInItemName: Bool,
        matchedInItemDescription: Bool,
        matchedEntryIds: [UUID]
    ) {
        self.linkedItemId = linkedItemId
        self.linkedModule = linkedModule
        self.matchedInItemName = matchedInItemName
        self.matchedInItemDescription = matchedInItemDescription
        self.matchedEntryIds = matchedEntryIds
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
    case link(UUID, NetworkModules)  // UUID of the linked item, module it belongs to
}
