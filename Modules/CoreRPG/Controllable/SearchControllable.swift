// @copyright André Trettin

import Foundation
import Observation

public protocol SearchControllable: Sendable  {
    var itemControllable: any ItemControllable { get }

    func globalSearchResults(searchText: String) async -> [SearchResult]
    func listSearchResults(searchText: String, listMode: ListDisplayModel.ListMode, displayMode: ListDisplayModel.DisplayMode, focusId: UUID?) async -> [SearchResult]
    func inspectorSearchResults(searchText: String, listMode: ListDisplayModel.ListMode, displayMode: ListDisplayModel.DisplayMode, focusId: UUID?) async -> [SearchResult]
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
    private func folderModeResults(searchText: String, focusId: UUID?, displayMode: ListDisplayModel.DisplayMode, searchEntries: Bool = false, includeTags: Bool = true) async -> [SearchResult] {
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
            let allIds = await itemControllable.itemDataModel.items
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
    // Returns nil when neither this item nor any descendant matches the search.
    private func buildFolderTreeNode(itemId: UUID, searchText: String, displayMode: ListDisplayModel.DisplayMode, parentEntryId: UUID? = nil, searchEntries: Bool = false, includeTags: Bool = true) async -> SearchResult? {
        guard !Task.isCancelled,
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
                    let entryId = entry.id == entry.childId ? entry.id.childPath(of: item.id) : entry.id
                    if let child = await buildFolderTreeNode(itemId: entry.childId, searchText: searchText, displayMode: displayMode, parentEntryId: entryId, searchEntries: searchEntries, includeTags: includeTags) {
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
    func itemMatchesFilter(_ item: any ItemDataAccessable, searchText: String, displayMode: ListDisplayModel.DisplayMode, includeTags: Bool = true) -> Bool {
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

    func makeResult(item: any ItemDataAccessable, searchText: String, displayMode: ListDisplayModel.DisplayMode, parentEntryId: UUID? = nil) -> SearchResult {
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

// MARK: - Inspector Search from LinkItemRootView

public extension SearchControllable {
    /// Inspector search entry point.
    ///
    /// Folder mode: same tree structure as list search but with entry searching enabled —
    ///   folders preserve hierarchy, leaf items also search entry name+content and return
    ///   matching entries as `result.children`. Tags are excluded (`includeTags: false`).
    ///
    /// List mode — two paths:
    /// - Non-scoped (`focusId == nil`): `inspectorBatchListResults` — O(1) actor hops via
    ///   `MainActor.run`, handles both empty and non-empty text, no async recursion needed.
    /// - Scoped (`focusId != nil`): `inspectorScopedListResults` — async because a folder/
    ///   collection parent must recurse into its child items.
    @MainActor func inspectorSearchResults(searchText: String, listMode: ListDisplayModel.ListMode, displayMode: ListDisplayModel.DisplayMode, focusId: UUID?) async -> [SearchResult] {
        switch listMode {
        case .folder:
            // Inspector folder mode behaves like list mode for entries — same content is
            // searched, only the tree structure differs (folder hierarchy instead of flat list).
            return await folderModeResults(searchText: searchText, focusId: focusId, displayMode: displayMode, searchEntries: true, includeTags: false)
        case .list:
            if let focusId {
                return await inspectorScopedListResults(searchText: searchText, focusId: focusId, displayMode: displayMode)
            }
            return inspectorBatchListResults(searchText: searchText, displayMode: displayMode)
        }
    }

    /// Non-scoped inspector list — mirrors `listModeResults` with adaptive entry search depth.
    ///
    /// **Empty search**: all items, A→Z, `canOpen = !entries.isEmpty`.
    ///
    /// **Non-empty search (text.count < 3)**: item-level only (no entry search).
    ///
    /// **Non-empty search (text.count ≥ 3)**: two-phase:
    ///   - Phase 1: count item-level matches (no entries yet).
    ///   - Phase 2: choose entry depth based on that count:
    ///     - < 10 item matches → wide: search entry name **+ content**.
    ///     - ≥ 10 item matches → narrow: entry **name only**;
    ///       if total name hits across all items ≤ 5, also add content matches.
    ///
    /// Tags excluded (`includeTags: false`).
    @MainActor private func inspectorBatchListResults(searchText: String, displayMode: ListDisplayModel.DisplayMode) -> [SearchResult] {
        let itemIds = itemControllable.itemDataModel.items

            // ── Empty search ─────────────────────────────────────────────────────────────
            if searchText.isEmpty {
                var results: [SearchResult] = []
                for itemId in itemIds {
                    guard let item = itemControllable.itemSync(for: itemId),
                          item.displayState == 0, !item.specialCategory else { continue }
                    var result = makeResult(item: item, searchText: "", displayMode: displayMode)
                    result.canOpen = !item.entries.isEmpty
                    results.append(result)
                }
                return results.sorted { $0.itemName.localizedCompare($1.itemName) == .orderedAscending }
            }

            // ── Non-empty: gather all visible non-folder candidates ───────────────────
            var allItems: [(id: UUID, item: any ItemDataAccessable)] = []
            for itemId in itemIds {
                guard let item = itemControllable.itemSync(for: itemId),
                      item.displayState == 0, !item.specialCategory else { continue }
                allItems.append((itemId, item))
            }

            // Phase 1: item-level match count (decides entry search depth)
            let itemLevelMatchIds: Set<UUID> = Set(allItems.compactMap { pair in
                itemMatchesFilter(pair.item, searchText: searchText, displayMode: displayMode, includeTags: false)
                    ? pair.id : nil
            })

            // text < 3 chars → no entry search
            guard searchText.count >= 3 else {
                return allItems
                    .filter { itemLevelMatchIds.contains($0.id) }
                    .map { makeResult(item: $0.item, searchText: searchText, displayMode: displayMode) }
                    .sortedByRelevance()
            }

            // Phase 2: build entry children map using the chosen depth
            var entryChildrenMap: [UUID: [SearchResult]] = [:]

            if itemLevelMatchIds.count < 10 {
                // Wide: entry name + content
                for (itemId, item) in allItems {
                    var children: [SearchResult] = []
                    for entry in item.entries {
                        if entry.name.localizedStandardContains(searchText)
                            || entry.content.localizedStandardContains(searchText) {
                            children.append(SearchResult(
                                itemId: item.id, itemName: item.name,
                                module: itemControllable.config.module, category: item.category,
                                entryId: entry.id, entryName: entry.name,
                                matchedContent: entry.content.isEmpty ? nil : entry.content,
                                relevanceScore: calculateRelevance(searchText: searchText,
                                    itemName: item.name, entryName: entry.name,
                                    content: entry.content, isItemMatch: false)
                            ))
                        }
                    }
                    if !children.isEmpty { entryChildrenMap[itemId] = children }
                }
            } else {
                // Narrow: entry name first; if total ≤ 5 hits, also add content matches
                var nameOnlyMap: [UUID: [SearchResult]] = [:]
                var totalNameHits = 0
                for (itemId, item) in allItems {
                    var nameChildren: [SearchResult] = []
                    for entry in item.entries where entry.name.localizedStandardContains(searchText) {
                        nameChildren.append(SearchResult(
                            itemId: item.id, itemName: item.name,
                            module: itemControllable.config.module, category: item.category,
                            entryId: entry.id, entryName: entry.name,
                            matchedContent: entry.content.isEmpty ? nil : entry.content,
                            relevanceScore: calculateRelevance(searchText: searchText,
                                itemName: item.name, entryName: entry.name,
                                content: entry.content, isItemMatch: false)
                        ))
                    }
                    if !nameChildren.isEmpty {
                        nameOnlyMap[itemId] = nameChildren
                        totalNameHits += nameChildren.count
                    }
                }
                let expandToContent = totalNameHits <= 5
                for (itemId, item) in allItems {
                    var children = nameOnlyMap[itemId] ?? []
                    if expandToContent {
                        let seenIds = Set(children.compactMap(\.entryId))
                        for entry in item.entries where !seenIds.contains(entry.id) {
                            if entry.content.localizedStandardContains(searchText) {
                                children.append(SearchResult(
                                    itemId: item.id, itemName: item.name,
                                    module: itemControllable.config.module, category: item.category,
                                    entryId: entry.id, entryName: entry.name,
                                    matchedContent: entry.content.isEmpty ? nil : entry.content,
                                    relevanceScore: calculateRelevance(searchText: searchText,
                                        itemName: item.name, entryName: entry.name,
                                        content: entry.content, isItemMatch: false)
                                ))
                            }
                        }
                    }
                    if !children.isEmpty { entryChildrenMap[itemId] = children }
                }
            }

            // Phase 3: merge item-level matches and entry-pulled-in items
            var results: [SearchResult] = []
            for (itemId, item) in allItems {
                let itemMatches = itemLevelMatchIds.contains(itemId)
                let entryChildren = entryChildrenMap[itemId] ?? []
                guard itemMatches || !entryChildren.isEmpty else { continue }
                var result = makeResult(item: item, searchText: searchText, displayMode: displayMode)
                result.children = entryChildren.sortedByRelevance()
                result.canOpen = !item.entries.isEmpty
                results.append(result)
            }
            return results.sortedByRelevance()
    }


    /// Scoped inspector list — used when `filterId` is set (inspector is constrained to a
    /// specific parent item or collection). Async because folder/collection parents recurse
    /// into child items via `inspectorResult`.
    ///
    /// Empty text:
    ///   - `specialCategory` parent → flat list of direct child items (collection/folder members)
    ///   - Regular parent → the item itself with `canOpen = !entries.isEmpty`
    ///
    /// Non-empty text: delegates to `inspectorResult` which handles folder recursion.
    @MainActor private func inspectorScopedListResults(searchText: String, focusId: UUID, displayMode: ListDisplayModel.DisplayMode) async -> [SearchResult] {
        guard let focusedItem = await itemControllable.item(for: focusId),
              focusedItem.displayState == 0 else { return [] }

        if searchText.isEmpty {
            if focusedItem.specialCategory {
                var results: [SearchResult] = []
                for entry in focusedItem.entries {
                    guard let child = itemControllable.itemSync(for: entry.childId),
                          child.displayState == 0 else { continue }
                    var result = makeResult(item: child, searchText: "", displayMode: displayMode, parentEntryId: entry.id)
                    result.canOpen = !child.entries.isEmpty
                    results.append(result)
                }
                return results.sorted { $0.itemName.localizedCompare($1.itemName) == .orderedAscending }
            } else {
                var result = makeResult(item: focusedItem, searchText: "", displayMode: displayMode)
                result.canOpen = !focusedItem.entries.isEmpty
                return [result]
            }
        }

        var foundResults: [SearchResult] = []
        await inspectorResult(item: focusedItem, searchText: searchText, displayMode: displayMode, foundResults: &foundResults)
        return foundResults.sortedByRelevance()
    }

    /// Searches one item for the scoped inspector non-empty path.
    /// Matching entries become `result.children`; `specialCategory` items recurse into
    /// child items (needed when a collection is the focus). Folders are never added to
    /// `foundResults` — only their leaf descendants are.
    private func inspectorResult(item: any ItemDataAccessable, searchText: String, displayMode: ListDisplayModel.DisplayMode, foundResults: inout [SearchResult]) async {
        guard !Task.isCancelled else { return }

        let itemMatches = itemMatchesFilter(item, searchText: searchText, displayMode: displayMode, includeTags: false)

        var entryChildren: [SearchResult] = []
        for entry in item.entries {
            guard !Task.isCancelled else { break }

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

            if item.specialCategory,
               let childItem = await itemControllable.item(for: entry.childId) {
                await inspectorResult(item: childItem, searchText: searchText, displayMode: displayMode, foundResults: &foundResults)
            }
        }

        guard !item.specialCategory else { return }
        guard itemMatches || !entryChildren.isEmpty else { return }

        var result = makeResult(item: item, searchText: searchText, displayMode: displayMode)
        result.children = entryChildren.sortedByRelevance()
        result.canOpen = !item.entries.isEmpty
        foundResults.append(result)
    }

    /// Returns all entries of `itemId` as direct `SearchResult`s, optionally filtered by
    /// `searchText`. Called by `SearchLinkController.results(text:focusId:)` when the user
    /// toggles a non-folder item open to reveal its entries.
    @MainActor func inspectorEntryResults(searchText: String, itemId: UUID, displayMode: ListDisplayModel.DisplayMode) -> [SearchResult] {
        guard let item = itemControllable.itemSync(for: itemId) else { return [] }
        let entries = searchText.isEmpty
            ? item.entries
            : item.entries.filter {
                $0.name.localizedStandardContains(searchText) ||
                $0.content.localizedStandardContains(searchText)
            }
        return entries
            .map { entry in
                SearchResult(
                    itemId: item.id,
                    itemName: item.name,
                    module: itemControllable.config.module,
                    category: item.category,
                    entryId: entry.id,
                    entryName: entry.name,
                    matchedContent: entry.content.isEmpty ? nil : entry.content,
                    relevanceScore: 0
                )
            }
            .sorted { ($0.entryName ?? "").localizedCompare($1.entryName ?? "") == .orderedAscending }
    }
}

public extension SearchControllable {
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
    func childPath(of parentId: UUID) -> UUID {
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
