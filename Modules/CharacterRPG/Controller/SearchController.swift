// @copyright André Trettin

import CoreRPG
import Foundation

struct SearchController: Sendable {
    let itemController: ItemController
}

extension SearchController: SearchControllable {
    var itemControllable: any ItemControllable { itemController }
}

// MARK: - Global search (from Game Views / Controller)

extension SearchController {
    /// Full module-wide search across all visible root characters and folders.
    ///
    /// Filtering rules:
    /// - `groupId == nil` — excludes hidden sub-values that belong to a character (`groupId != nil`)
    /// - `displayState == DisplayStateMask.fullVisible.rawValue` — excludes archived/hidden items
    /// - `parentId` is ignored here because it is used for folder nesting; a character inside a folder
    ///   still has `groupId == nil` and must appear in search results.
    ///
    /// Search scope per item type:
    /// - **Regular characters** (`!specialCategory`): name and description only — entries are not
    ///   searched in the list view.
    /// - **Folders / collections** (`specialCategory`): delegates to `result()`, which checks
    ///   the folder's own name and description.
    @MainActor func globalSearchResults(searchText: String) async -> [SearchResult] {
        guard !searchText.isEmpty else { return [] }

        let itemIds = itemControllable.itemDataModel.items
        var foundResults: [SearchResult] = []

        for itemId in itemIds {
            guard !Task.isCancelled else { break }
            guard let item = await itemController.item(for: itemId),
                  item.groupId == nil,      // root characters and folders only
                  item.displayState == DisplayStateMask.fullVisible.rawValue else { continue }

            if item.specialCategory {
                // Folder / collection — its own name and description only (global = all fields)
                result(item: item, searchText: searchText, displayMode: .regular, foundResults: &foundResults)
            } else {
                // Regular character — name and description only, no entries
                guard item.name.localizedStandardContains(searchText) ||
                        item.description.localizedStandardContains(searchText) else { continue }
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
        }

        return foundResults.sortedByRelevance()
    }

    /// The visible monsters whose level or challenge rating is within
    /// `LevelSearchFilter.monsterTolerance` of the searched level and that match the rest of the
    /// search text, closest first.
    @MainActor func levelSearchResults(query: LevelSearchQuery) async -> [SearchResult] {
        guard query.filter.includes(.monster) else { return [] }

        var foundResults: [SearchResult] = []
        for itemId in itemControllable.itemDataModel.items {
            guard !Task.isCancelled else { break }
            guard let item = await itemController.item(for: itemId),
                  item.groupId == nil,
                  item.category == .monster,
                  item.displayState == DisplayStateMask.fullVisible.rawValue,
                  itemMatchesFilter(item, searchText: query.text, displayMode: .regular),
                  let rating = await rating(of: item),
                  let distance = query.filter.monsterDistance(rating: rating) else { continue }

            let textScore = query.text.isEmpty ? 100 : calculateRelevance(
                searchText: query.text,
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
                matchedContent: item.description.isEmpty ? nil : item.description,
                relevanceScore: textScore - Int((distance * 10).rounded())
            ))
        }
        return foundResults.sortedByRelevance()
    }

    /// How many value groups deep a rating is looked for: Foundry keeps it in `details`
    /// (`details.cr`, `details.level.value`).
    private static let ratingGroupDepth = 1

    /// The level or challenge rating of a character: the first value entry named Level, CR, …
    /// with a number, in its own entries, then in its value groups. A rating entry that is a group
    /// itself (`level` → `value`) holds the number in its first numeric entry. Only the
    /// character's own sub-values are searched, never a linked root character.
    @MainActor private func rating(of item: ValueModel, depth: Int = 0) async -> Double? {
        for entry in item.entries where LevelSearchQuery.isRatingEntryName(entry.name) {
            if let rating = LevelSearchQuery.rating(from: entry.value) { return rating }
            if let groupId = entry.valueId,
               let group = await itemController.item(for: groupId),
               group.groupId != nil,
               let rating = group.entries.lazy.compactMap({ LevelSearchQuery.rating(from: $0.value) }).first {
                return rating
            }
        }
        guard depth < Self.ratingGroupDepth else { return nil }
        for entry in item.entries {
            guard let groupId = entry.valueId, groupId != item.id,
                  let group = await itemController.item(for: groupId),
                  group.groupId != nil else { continue }
            if let rating = await rating(of: group, depth: depth + 1) { return rating }
        }
        return nil
    }

    /// A folder or collection matches by its own name and description. The characters inside it
    /// are found by the main loop in `globalSearchResults`.
    @MainActor private func result(item: ValueModel, searchText: String, displayMode: ListDisplayModel.DisplayMode, foundResults: inout [SearchResult]) {
        guard itemMatchesFilter(item, searchText: searchText, displayMode: displayMode) else { return }
        foundResults.append(makeResult(item: item, searchText: searchText, displayMode: displayMode))
    }
}

// MARK: - List search (from ListRootView / FolderListController)

extension SearchController {
    @MainActor func listSearchResults(searchText: String, listMode: ListDisplayModel.ListMode, displayMode: ListDisplayModel.DisplayMode, focusId: UUID?) async -> [SearchResult] {
        switch listMode {
        case .list:
            return await listModeCharacterResults(searchText: searchText, displayMode: displayMode)
        case .folder:
            return await folderModeCharacterResults(searchText: searchText, focusId: focusId, displayMode: displayMode)
        }
    }

    /// Flat list: root characters only (`groupId == nil`).
    /// Excludes specialCategory items (groups/folders) — they only appear in folder mode.
    @MainActor private func listModeCharacterResults(searchText: String, displayMode: ListDisplayModel.DisplayMode) async -> [SearchResult] {
        let itemIds = itemControllable.itemDataModel.items
        var foundResults: [SearchResult] = []
        for itemId in itemIds {
            guard !Task.isCancelled else { break }
            guard let item = await itemController.item(for: itemId),
                  item.groupId == nil,
                  item.displayState == DisplayStateMask.fullVisible.rawValue,
                  !item.specialCategory else { continue }
            guard itemMatchesFilter(item, searchText: searchText, displayMode: displayMode) else { continue }
            foundResults.append(makeResult(item: item, searchText: searchText, displayMode: displayMode))
        }
        if searchText.isEmpty {
            return foundResults.sorted { $0.itemName.localizedCompare($1.itemName) == .orderedAscending }
        }
        return foundResults.sortedByRelevance()
    }

    /// Folder tree: hierarchical results rooted at focusId or all root-level items.
    @MainActor private func folderModeCharacterResults(searchText: String, focusId: UUID?, displayMode: ListDisplayModel.DisplayMode, includeTags: Bool = true) async -> [SearchResult] {
        if let focusId {
            guard let folder = await itemController.item(for: focusId) else { return [] }
            var results: [SearchResult] = []
            for entry in folder.entries {
                guard !Task.isCancelled else { break }
                if let node = await buildCharacterFolderNode(itemId: entry.childId, searchText: searchText, displayMode: displayMode, parentEntryId: entry.id, includeTags: includeTags) {
                    results.append(node)
                }
            }
            if searchText.isEmpty {
                if folder.category == .folder {
                    results.sort { $0.itemName.localizedCompare($1.itemName) == .orderedAscending }
                }
            } else {
                results = results.sortedByRelevance()
            }
            return results
        } else {
            let allIds = itemControllable.itemDataModel.items
            var results: [SearchResult] = []
            for itemId in allIds {
                guard !Task.isCancelled else { break }
                guard let item = await itemController.item(for: itemId),
                      item.groupId == nil,
                      item.parentId == nil,
                      item.displayState == DisplayStateMask.fullVisible.rawValue else { continue }
                if let node = await buildCharacterFolderNode(itemId: itemId, searchText: searchText, displayMode: displayMode, includeTags: includeTags) {
                    results.append(node)
                }
            }
            if searchText.isEmpty {
                return results.sorted { $0.itemName.localizedCompare($1.itemName) == .orderedAscending }
            }
            return results.sortedByRelevance()
        }
    }

    /// Recursively builds one folder-tree node, filtering sub-values (`groupId != nil`).
    /// - Parameter depth: recursion guard — see `FolderTreeDepthLimit`.
    @MainActor private func buildCharacterFolderNode(itemId: UUID, searchText: String, displayMode: ListDisplayModel.DisplayMode, parentEntryId: UUID? = nil, includeTags: Bool = true, depth: Int = 0) async -> SearchResult? {
        guard depth < FolderTreeDepthLimit.max,
              !Task.isCancelled,
              let item = await itemController.item(for: itemId),
              item.groupId == nil,
              item.displayState == DisplayStateMask.fullVisible.rawValue else { return nil }

        let itemMatches = itemMatchesFilter(item, searchText: searchText, displayMode: displayMode, includeTags: includeTags)

        if item.specialCategory {
            var childNodes: [SearchResult] = []
            if !searchText.isEmpty {
                for entry in item.entries {
                    guard !Task.isCancelled else { break }
                    // Yield periodically so a large folder/collection tree doesn't monopolize
                    // the main actor in one unbroken stretch during a single search pass.
                    await Task.yield()
                    if let child = await buildCharacterFolderNode(itemId: entry.childId, searchText: searchText, displayMode: displayMode, parentEntryId: entry.id, includeTags: includeTags, depth: depth + 1) {
                        childNodes.append(child)
                    }
                }
                if item.category == .folder {
                    childNodes = childNodes.sortedByRelevance()
                }
            }
            guard itemMatches || !childNodes.isEmpty else { return nil }
            var node = makeResult(item: item, searchText: searchText, displayMode: displayMode, parentEntryId: parentEntryId)
            node.children = childNodes
            node.canOpen = childNodes.isEmpty && !item.entries.isEmpty
            return node
        } else {
            guard itemMatches else { return nil }
            return makeResult(item: item, searchText: searchText, displayMode: displayMode, parentEntryId: parentEntryId)
        }
    }
}

// MARK: - Inspector search (from LinkListItemView / FolderListController)

extension SearchController {
    @MainActor func inspectorSearchResults(searchText: String, listMode: ListDisplayModel.ListMode, displayMode: ListDisplayModel.DisplayMode, focusId: UUID?) async -> [SearchResult] {
        switch listMode {
        case .folder:
            return await folderModeCharacterResults(searchText: searchText, focusId: focusId, displayMode: displayMode, includeTags: false)
        case .list:
            if let focusId {
                // Sub-value items (groupId != nil) are group-entry sub-values, not root characters.
                // Return their entries as direct flat results so loadChildrenViaSearch can place
                // them as children of the group entry row — not wrapped in a character result.
                guard let item = await itemController.item(for: focusId) else { return [] }
                if item.groupId != nil {
                    let entries = searchText.isEmpty
                        ? item.entries
                        : item.entries.filter {
                            $0.name.localizedStandardContains(searchText) ||
                            $0.content.localizedStandardContains(searchText)
                        }
                    return entries
                        .map { entry in
                            SearchResult(
                                itemId: focusId,
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
                // Root character: return it as root item with its entries as children.
                return await focusedCharacterInspector(characterId: focusId, searchText: searchText)
            }
            // No focus: CoreRPG-compatible inspector (entries as children, CharacterRPG filters).
            return await inspectorSearchResults(searchText: searchText, parentId: nil, displayMode: displayMode)
        }
    }

    // MARK: - Focused character inspector

    /// Always returns the character. If searchText is empty all entries are children.
    /// If searchText is set, matching entries are children. A group entry also matches
    /// when its sub-value name or one of its sub-entries matches; included group entries
    /// carry the sub-value's entries so API consumers can inspect the full group.
    @MainActor private func focusedCharacterInspector(characterId: UUID, searchText: String) async -> [SearchResult] {
        guard let character = await itemController.item(for: characterId) else { return [] }

        var entryChildren: [SearchResult] = []
        for entry in character.entries {
            guard !Task.isCancelled else { break }

            if searchText.isEmpty {
                var entryResult = makeEntryResult(for: entry, characterId: characterId, characterName: character.name)
                if let subValueId = entry.valueId,
                   let subValue = await itemController.item(for: subValueId) {
                    // Use subValueId as itemId for sub-entries so the view resolves
                    // model?[subEntry.id] against the sub-value model (which owns them),
                    // not the character model (which only has the group-entry link).
                    entryResult.children = subValue.entries.map {
                        makeEntryResult(for: $0, characterId: subValueId, characterName: subValue.name)
                    }
                }
                entryChildren.append(entryResult)
            } else {
                let entryNameMatch    = entry.name.localizedStandardContains(searchText)
                let entryContentMatch = entry.content.localizedStandardContains(searchText)
                var subValueNameMatch = false
                var subEntryMatch = false
                var subEntries: [SearchResult] = []

                if let subValueId = entry.valueId,
                   let subValue = await itemController.item(for: subValueId) {
                    subValueNameMatch = subValue.name.localizedStandardContains(searchText)
                    for subEntry in subValue.entries {
                        if subEntry.name.localizedStandardContains(searchText) ||
                           subEntry.content.localizedStandardContains(searchText) {
                            subEntryMatch = true
                        }
                        // Use subValueId as itemId — see empty-search comment above.
                        subEntries.append(
                            makeEntryResult(for: subEntry, characterId: subValueId, characterName: subValue.name)
                        )
                    }
                }

                guard entryNameMatch || entryContentMatch || subValueNameMatch || subEntryMatch else { continue }
                var entryResult = makeEntryResult(for: entry, characterId: characterId, characterName: character.name)
                entryResult.children = subEntries
                entryChildren.append(entryResult)
            }
        }

        var result = makeResult(item: character, searchText: "", displayMode: .medium)
        result.children = entryChildren
        // Signal appendToFlat to start this item expanded so entries are visible
        // immediately — the user opened the inspector to see this character's sheet,
        // not to see a closed chevron.
        result.shouldOpen = !entryChildren.isEmpty
        return [result]
    }

    @MainActor private func makeEntryResult(for entry: ValueEntryModel, characterId: UUID, characterName: String) -> SearchResult {
        var result = SearchResult(
            itemId: characterId,
            itemName: characterName,
            module: itemControllable.config.module,
            category: .value,
            entryId: entry.id,
            entryName: entry.name,
            matchedContent: entry.content.isEmpty ? nil : entry.content,
            relevanceScore: 100
        )
        if let subValueId = entry.valueId {
            // Group entry: has sub-entries in a linked sub-value item.
            // canOpen shows the chevron; childFocusId directs loadChildrenViaSearch to the
            // sub-value item instead of the parent character (which would load all entries).
            result.canOpen = true
            result.childFocusId = subValueId
        }
        return result
    }

    /// Inspector search used by `SearchLinkController`.
    ///
    /// - `parentId != nil`: scoped to the given character. All results carry that character's
    ///   `itemId` so the UI navigates back to the character, not into a sub-value group.
    /// - `parentId == nil`: walks all root characters (`groupId == nil`, not a folder/collection,
    ///   `displayState == DisplayStateMask.fullVisible.rawValue`).
    ///
    /// Empty search is handled properly:
    /// - `parentId != nil`, empty → delegates to `focusedCharacterInspector` (all entries shown)
    /// - `parentId == nil`, empty → all root characters, A→Z, with raw results kept non-expandable
    @MainActor func inspectorSearchResults(searchText: String, parentId: UUID?, displayMode: ListDisplayModel.DisplayMode = .medium) async -> [SearchResult] {
        var foundResults: [SearchResult] = []
        if let parentId {
            if searchText.isEmpty {
                return await focusedCharacterInspector(characterId: parentId, searchText: "")
            }
            guard let character = await itemController.item(for: parentId) else { return [] }
            await characterInspectorResult(character: character, searchText: searchText, displayMode: displayMode, foundResults: &foundResults)
            return foundResults
        } else {
            // Unscoped common inspector: characters are items for linking only.
            // Do not return entry children or mark raw results as expandable.
            let itemIds = itemControllable.itemDataModel.items
            for itemId in itemIds {
                guard !Task.isCancelled else { break }
                guard let character = await itemController.item(for: itemId),
                      character.groupId == nil,
                      // A folder or collection is no character: the flat link/selection list
                      // shows folders only in folder mode (same rule as `listModeCharacterResults`).
                      !character.specialCategory,
                      character.displayState == DisplayStateMask.fullVisible.rawValue else { continue }
                if searchText.isEmpty {
                    foundResults.append(makeResult(item: character, searchText: "", displayMode: displayMode))
                } else {
                    // Match at item level only. Entry exploration happens on explicit toggle.
                    guard itemMatchesFilter(character, searchText: searchText, displayMode: displayMode, includeTags: false) else { continue }
                    foundResults.append(makeResult(item: character, searchText: searchText, displayMode: displayMode))
                }
            }
            if searchText.isEmpty {
                return foundResults.sorted { $0.itemName.localizedCompare($1.itemName) == .orderedAscending }
            }
            return foundResults.sortedByRelevance()
        }
    }

    /// Searches `character` at item-level (displayMode-aware) and all entries (always name+content).
    /// Matching entries become children of the character result, not flat siblings.
    @MainActor private func characterInspectorResult(character: ValueModel, searchText: String, displayMode: ListDisplayModel.DisplayMode, foundResults: inout [SearchResult]) async {
        let characterMatches = itemMatchesFilter(character, searchText: searchText, displayMode: displayMode, includeTags: false)
        var entryChildren: [SearchResult] = []
        await collectValueEntries(of: character, characterId: character.id, characterName: character.name, searchText: searchText, into: &entryChildren)
        guard characterMatches || !entryChildren.isEmpty else { return }
        var result = makeResult(item: character, searchText: searchText, displayMode: displayMode)
        result.children = entryChildren.sortedByRelevance()
        foundResults.append(result)
    }

    /// Collects matching entries from `item` into `entryChildren`.
    /// Inspector always searches entry name + content, regardless of displayMode.
    /// Recurses into sub-value groups via `entry.valueId`.
    /// - Parameter depth: recursion guard against a cyclic `valueId` chain — see CODE_AUDIT_Character §5.3.
    @MainActor private func collectValueEntries(of item: ValueModel, characterId: UUID, characterName: String, searchText: String, into entryChildren: inout [SearchResult], depth: Int = 0) async {
        guard depth < FolderTreeDepthLimit.max else { return }

        for entry in item.entries {
            guard !Task.isCancelled else { break }

            let entryMatches = entry.name.localizedStandardContains(searchText)
                            || entry.content.localizedStandardContains(searchText)

            if entryMatches {
                entryChildren.append(entryHit(itemId: characterId, itemName: characterName, category: item.category, entryId: entry.id, entryName: entry.name, content: entry.content, searchText: searchText))
            }

            if let subValueId = entry.valueId {
                guard let subValue = await itemController.item(for: subValueId) else { continue }
                await collectValueEntries(of: subValue, characterId: characterId, characterName: characterName, searchText: searchText, into: &entryChildren, depth: depth + 1)
            }
        }
    }
}
