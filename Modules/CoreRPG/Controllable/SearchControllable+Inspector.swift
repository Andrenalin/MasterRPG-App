// @copyright André Trettin

import Foundation

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
    /// - Parameter depth: recursion guard — see `FolderTreeDepthLimit`.
    @MainActor private func inspectorResult(item: any ItemDataAccessable, searchText: String, displayMode: ListDisplayModel.DisplayMode, foundResults: inout [SearchResult], depth: Int = 0) async {
        guard depth < FolderTreeDepthLimit.max, !Task.isCancelled else { return }

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
                // Yield periodically so a large collection tree doesn't monopolize the main
                // actor in one unbroken stretch during a single search pass.
                await Task.yield()
                await inspectorResult(item: childItem, searchText: searchText, displayMode: displayMode, foundResults: &foundResults, depth: depth + 1)
            }
        }

        guard !item.specialCategory else { return }
        guard itemMatches || !entryChildren.isEmpty else { return }

        var result = makeResult(item: item, searchText: searchText, displayMode: displayMode)
        result.children = entryChildren.sortedByRelevance()
        result.canOpen = !item.entries.isEmpty
        foundResults.append(result)
    }

}
