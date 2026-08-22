// @copyright André Trettin

import Foundation
import Observation

public protocol SearchControllable: Sendable  {
    var itemControllable: any ItemControllable { get }

    @MainActor func globalSearchResults(searchText: String) async -> [SearchResult]
    @MainActor func listSearchResults(searchText: String, listMode: ListDisplayModel.ListMode, displayMode: ListDisplayModel.DisplayMode, focusId: UUID?) async -> [SearchResult]
    @MainActor func inspectorSearchResults(searchText: String, listMode: ListDisplayModel.ListMode, displayMode: ListDisplayModel.DisplayMode, focusId: UUID?) async -> [SearchResult]
}

// MARK: - Global Search from Game View

public extension SearchControllable {
    @MainActor func globalSearchResults(searchText: String) async -> [SearchResult] {
        guard searchText.isEmpty == false else { return [] }
        
        let itemIds = itemControllable.itemDataModel.items
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
}

// MARK: - List Search from ListRootView

public extension SearchControllable {
    @MainActor func listSearchResults(searchText: String, listMode: ListDisplayModel.ListMode, displayMode: ListDisplayModel.DisplayMode, focusId: UUID?) async -> [SearchResult] {
        switch listMode {
        case .list:
            return listModeResults(searchText: searchText, displayMode: displayMode)
        case .folder:
            return await folderModeResults(searchText: searchText, focusId: focusId, displayMode: displayMode)
        }
    }

    // List mode: flat results, folders/collections excluded.
    // Empty search → alphabetical; non-empty → relevance order.
    @MainActor private func listModeResults(searchText: String, displayMode: ListDisplayModel.DisplayMode) -> [SearchResult] {
        let itemIds = itemControllable.itemDataModel.items
        var results: [SearchResult] = []
        for itemId in itemIds {
            guard let item = itemControllable.itemSync(for: itemId),
                  item.displayState == 0,
                  !item.specialCategory else { continue }
            guard itemMatchesFilter(item, searchText: searchText, displayMode: displayMode) else { continue }
            results.append(makeResult(item: item, searchText: searchText, displayMode: displayMode))
        }
        if searchText.isEmpty {
            return results.sorted { $0.itemName.localizedCompare($1.itemName) == .orderedAscending }
        }
        return results.sortedByRelevance()
    }

    // Folder mode: hierarchical results rooted at focusId (or global root when nil).
    // Empty search → alphabetical (folders) / entry order (collections).
    // Non-empty search → relevance order at every level.
    // searchEntries: when true (inspector), non-special items also search entry name+content
    //   and return matching entries as result.children (same as inspectorBatchListResults).
    // includeTags: when false (inspector), tag matching is skipped even in regular display mode.
    // Not `private`: also called from `SearchControllable+Inspector.swift`'s `inspectorSearchResults`.
    @MainActor func folderModeResults(searchText: String, focusId: UUID?, displayMode: ListDisplayModel.DisplayMode, searchEntries: Bool = false, includeTags: Bool = true) async -> [SearchResult] {
        if let focusId {
            guard let folder = await itemControllable.item(for: focusId) else { return [] }
            var results: [SearchResult] = []
            for entry in folder.entries {
                guard !Task.isCancelled else { break }
                let entryId = entry.id == entry.childId ? entry.id.childPath(of: folder.id) : entry.id
                if let node = await buildFolderTreeNode(itemId: entry.childId, searchText: searchText, displayMode: displayMode, parentEntryId: entryId, searchEntries: searchEntries, includeTags: includeTags) {
                    results.append(node)
                }
            }
            if searchText.isEmpty {
                if folder.category == .folder {
                    results.sort { $0.itemName.localizedCompare($1.itemName) == .orderedAscending }
                }
                // collections keep entry order
            } else {
                results = results.sortedByRelevance()
            }
            return results
        } else {
            let allIds = itemControllable.itemDataModel.items
            var results: [SearchResult] = []
            for itemId in allIds {
                guard !Task.isCancelled else { break }
                guard let item = await itemControllable.item(for: itemId),
                      item.parentId == nil else { continue }
                if let node = await buildFolderTreeNode(itemId: itemId, searchText: searchText, displayMode: displayMode, searchEntries: searchEntries, includeTags: includeTags) {
                    results.append(node)
                }
            }
            if searchText.isEmpty {
                return results.sorted { $0.itemName.localizedCompare($1.itemName) == .orderedAscending }
            }
            return results.sortedByRelevance()
        }
    }

    // Recursively builds one node of the folder tree.
    // parentEntryId: the entry.id in the parent folder/collection that links to this child —
    //   used as FolderListItemModel.id so the same item can appear in multiple collections
    //   with independent identities.
    // searchEntries: when true (inspector folder mode), also searches entry name+content for
    //   non-special items and returns matching entries as result.children. Empty search never
    //   returns entry children — canOpen is set so the user can expand on demand.
    // includeTags: forwarded to itemMatchesFilter; false for inspector (no tag matching).
    // depth: recursion guard — `addItem(itemId:parentId:)` refuses to create a folder/collection
    //   cycle at write time, but this caps recursion as defense-in-depth in case one exists
    //   anyway (e.g. imported/merged data), rather than recursing until the stack overflows.
    // Returns nil when neither this item nor any descendant matches the search.
    @MainActor private func buildFolderTreeNode(itemId: UUID, searchText: String, displayMode: ListDisplayModel.DisplayMode, parentEntryId: UUID? = nil, searchEntries: Bool = false, includeTags: Bool = true, depth: Int = 0) async -> SearchResult? {
        guard depth < FolderTreeDepthLimit.max,
              !Task.isCancelled,
              let item = await itemControllable.item(for: itemId),
              item.displayState == 0 else { return nil }

        let itemMatches = itemMatchesFilter(item, searchText: searchText, displayMode: displayMode, includeTags: includeTags)

        if item.specialCategory {
            // Lazy loading: children are only fetched during an active search.
            // For empty search the caller (FolderListControllable) expands open
            // folders directly from the item model, so we return the node with
            // no children and let the UI open/close on demand.
            var childNodes: [SearchResult] = []
            if !searchText.isEmpty {
                for entry in item.entries {
                    guard !Task.isCancelled else { break }
                    // Yield periodically so a large folder/collection tree doesn't monopolize
                    // the main actor in one unbroken stretch during a single search pass.
                    await Task.yield()
                    let entryId = entry.id == entry.childId ? entry.id.childPath(of: item.id) : entry.id
                    if let child = await buildFolderTreeNode(itemId: entry.childId, searchText: searchText, displayMode: displayMode, parentEntryId: entryId, searchEntries: searchEntries, includeTags: includeTags, depth: depth + 1) {
                        childNodes.append(child)
                    }
                }
                // Relevance order during search; collections preserve entry order.
                if item.category == .folder {
                    childNodes = childNodes.sortedByRelevance()
                }
            }
            guard itemMatches || !childNodes.isEmpty else { return nil }
            var result = makeResult(item: item, searchText: searchText, displayMode: displayMode, parentEntryId: parentEntryId)
            result.children = childNodes
            // canOpen = true when no children were returned (lazy or no matches).
            result.canOpen = childNodes.isEmpty
            return result
        } else if searchEntries {
            // Inspector folder mode: also search entries and return matching ones as children.
            // Empty search: never return entry children — set canOpen so user can expand.
            var entryChildren: [SearchResult] = []
            if !searchText.isEmpty {
                for entry in item.entries {
                    if entry.name.localizedStandardContains(searchText)
                        || entry.content.localizedStandardContains(searchText) {
                        entryChildren.append(SearchResult(
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
                }
            }
            guard itemMatches || !entryChildren.isEmpty else { return nil }
            var result = makeResult(item: item, searchText: searchText, displayMode: displayMode, parentEntryId: parentEntryId)
            result.children = entryChildren.sortedByRelevance()
            result.canOpen = !item.entries.isEmpty
            return result
        } else {
            guard itemMatches else { return nil }
            return makeResult(item: item, searchText: searchText, displayMode: displayMode, parentEntryId: parentEntryId)
        }
    }

    // Returns true when item should be included for the given search text and display mode.
    // compact  → name only
    // medium   → name + description
    // regular  → name + description + tags (tags excluded for inspector via includeTags: false)
    @MainActor func itemMatchesFilter(_ item: any ItemDataAccessable, searchText: String, displayMode: ListDisplayModel.DisplayMode, includeTags: Bool = true) -> Bool {
        guard !searchText.isEmpty else { return true }
        if item.name.localizedStandardContains(searchText) { return true }
        if displayMode != .compact {
            if item.description.localizedStandardContains(searchText) { return true }
        }
        if displayMode == .regular && includeTags {
            if item.tags.contains(where: { $0.localizedStandardContains(searchText) }) { return true }
        }
        return false
    }

    @MainActor func makeResult(item: any ItemDataAccessable, searchText: String, displayMode: ListDisplayModel.DisplayMode, parentEntryId: UUID? = nil) -> SearchResult {
        let description: String? = displayMode != .compact ? (item.description.isEmpty ? nil : item.description) : nil
        var score = searchText.isEmpty ? 100 : calculateRelevance(
            searchText: searchText,
            itemName: item.name,
            entryName: nil,
            content: description,
            isItemMatch: true
        )
        if displayMode == .regular && !searchText.isEmpty,
           item.tags.contains(where: { $0.localizedStandardContains(searchText) }) {
            score += 8
        }
        return SearchResult(
            itemId: item.id,
            itemName: item.name,
            module: itemControllable.config.module,
            category: item.category,
            entryId: parentEntryId,
            entryName: nil,
            matchedContent: description,
            relevanceScore: score
        )
    }
}

// Inspector Search from LinkItemRootView (`inspectorSearchResults`, `inspectorResult`, …) lives in
// `SearchControllable+Inspector.swift`.

public extension SearchControllable {
    func calculateRelevance(searchText: String, itemName: String, entryName: String?, content: String?, isItemMatch: Bool) -> Int {
        var score = 0
        
        // Item name exact match (highest priority).
        // `.diacriticInsensitive` + an explicit `locale:` keeps this tier consistent with
        // `localizedStandardContains` below it — without them, an accented name (e.g. "Café")
        // would fail to score as an exact/prefix match against a plain-ASCII query ("cafe")
        // and silently fall through to the lower, generic-contains tier instead.
        if itemName.compare(searchText, options: [.caseInsensitive, .diacriticInsensitive], range: nil, locale: .current) == .orderedSame {
            score += 100
        } else if itemName.range(of: searchText, options: [.caseInsensitive, .anchored, .diacriticInsensitive], locale: .current) != nil {
            // Prefix match
            score += 50
        } else if itemName.localizedStandardContains(searchText) {
            score += 25
        }

        // Entry name match (medium priority)
        if let entryName {
            if entryName.compare(searchText, options: [.caseInsensitive, .diacriticInsensitive], range: nil, locale: .current) == .orderedSame {
                score += 80
            } else if entryName.range(of: searchText, options: [.caseInsensitive, .anchored, .diacriticInsensitive], locale: .current) != nil {
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

// MARK: - Path identity for link-entry types

extension UUID {
    /// Returns a stable, path-unique UUID for "this UUID as a child of parentId".
    ///
    /// Needed for entry models where `entry.id == entry.childId` (AdventureEntryModel,
    /// MapEntryModel, etc.). Without this, the same item appearing at root level (entryId=nil
    /// → FolderListItemModel.id = itemId) and as a collection child (entryId = entry.id = itemId
    /// → same id) produces duplicate SwiftUI identifiers.
    ///
    /// XOR of the two UUID byte arrays is deterministic and produces a value distinct
    /// from both inputs (since parentId ≠ childId, the XOR is never zero).
    public func childPath(of parentId: UUID) -> UUID {
        let p = parentId.uuid, s = uuid
        return UUID(uuid: (
            p.0  ^ s.0,  p.1  ^ s.1,  p.2  ^ s.2,  p.3  ^ s.3,
            p.4  ^ s.4,  p.5  ^ s.5,  p.6  ^ s.6,  p.7  ^ s.7,
            p.8  ^ s.8,  p.9  ^ s.9,  p.10 ^ s.10, p.11 ^ s.11,
            p.12 ^ s.12, p.13 ^ s.13, p.14 ^ s.14, p.15 ^ s.15
        ))
    }
}

// MARK: - SearchResult sorting

public extension Array where Element == SearchResult {
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
