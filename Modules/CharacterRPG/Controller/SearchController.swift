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
    /// - `displayState == 0` — excludes archived/hidden items
    /// - `parentId` is ignored here because it is used for folder nesting; a character inside a folder
    ///   still has `groupId == nil` and must appear in search results.
    ///
    /// Search scope per item type:
    /// - **Regular characters** (`!specialCategory`): name and description only — entries are not
    ///   searched in the list view.
    /// - **Folders / collections** (`specialCategory`): delegates to `result()` which searches
    ///   the collection's children entries.
    func globalSearchResults(searchText: String) async -> [SearchResult] {
        guard !searchText.isEmpty else { return [] }
        
        let itemIds = await itemControllable.itemDataModel.items
        var foundResults: [SearchResult] = []
        
        for itemId in itemIds {
            guard !Task.isCancelled else { break }
            guard let item = await itemController.item(for: itemId),
                  item.groupId == nil,      // root characters and folders only
                  item.displayState == 0 else { continue }
            
            if item.specialCategory {
                // Folder / collection — search its children entries (global = all fields)
                await result(item: item, searchText: searchText, displayMode: .regular, foundResults: &foundResults)
            } else {
                // Regular character — name and description only, no entries
                guard item.name.localizedCaseInsensitiveContains(searchText) ||
                        item.description.localizedCaseInsensitiveContains(searchText) else { continue }
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
        
        return foundResults.sorted { $0.relevanceScore > $1.relevanceScore }
    }
    
    // displayMode: .regular in global search so all fields are covered.
    private func result(item: ValueModel, searchText: String, displayMode: ListDisplayModel.DisplayMode, foundResults: inout [SearchResult]) async {
        if characterMatchesFilter(item, searchText: searchText, displayMode: displayMode) {
            foundResults.append(characterResult(item: item, searchText: searchText, displayMode: displayMode))
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
                    await result(item: item, searchText: searchText, displayMode: .regular, foundResults: &foundResults)
                }
            }
        }
    }
}

// MARK: - List search (from ListRootView / FolderListController)

extension SearchController {
    func listSearchResults(searchText: String, listMode: ListDisplayModel.ListMode, displayMode: ListDisplayModel.DisplayMode, focusId: UUID?) async -> [SearchResult] {
        switch listMode {
        case .list:
            return await listModeCharacterResults(searchText: searchText, displayMode: displayMode)
        case .folder:
            return await folderModeCharacterResults(searchText: searchText, focusId: focusId, displayMode: displayMode)
        }
    }

    /// Flat list: root characters and groups (`groupId == nil`).
    /// Includes specialCategory items (groups/folders) since they are meaningful navigation nodes.
    private func listModeCharacterResults(searchText: String, displayMode: ListDisplayModel.DisplayMode) async -> [SearchResult] {
        let itemIds = await itemControllable.itemDataModel.items
        var foundResults: [SearchResult] = []
        for itemId in itemIds {
            guard !Task.isCancelled else { break }
            guard let item = await itemController.item(for: itemId),
                  item.groupId == nil,
                  item.displayState == 0 else { continue }
            if item.specialCategory {
                await result(item: item, searchText: searchText, displayMode: displayMode, foundResults: &foundResults)
            } else {
                guard characterMatchesFilter(item, searchText: searchText, displayMode: displayMode) else { continue }
                foundResults.append(characterResult(item: item, searchText: searchText, displayMode: displayMode))
            }
        }
        if searchText.isEmpty {
            return foundResults.sorted { $0.itemName.localizedCompare($1.itemName) == .orderedAscending }
        }
        return foundResults.sortedByRelevance()
    }

    /// Folder tree: hierarchical results rooted at focusId or all root-level items.
    private func folderModeCharacterResults(searchText: String, focusId: UUID?, displayMode: ListDisplayModel.DisplayMode) async -> [SearchResult] {
        if let focusId {
            guard let folder = await itemController.item(for: focusId) else { return [] }
            var results: [SearchResult] = []
            for entry in folder.entries {
                guard !Task.isCancelled else { break }
                if let node = await buildCharacterFolderNode(itemId: entry.childId, searchText: searchText, displayMode: displayMode, parentEntryId: entry.id) {
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
            let allIds = await itemControllable.itemDataModel.items
            var results: [SearchResult] = []
            for itemId in allIds {
                guard !Task.isCancelled else { break }
                guard let item = await itemController.item(for: itemId),
                      item.groupId == nil,
                      item.parentId == nil,
                      item.displayState == 0 else { continue }
                if let node = await buildCharacterFolderNode(itemId: itemId, searchText: searchText, displayMode: displayMode) {
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
    private func buildCharacterFolderNode(itemId: UUID, searchText: String, displayMode: ListDisplayModel.DisplayMode, parentEntryId: UUID? = nil) async -> SearchResult? {
        guard !Task.isCancelled,
              let item = await itemController.item(for: itemId),
              item.groupId == nil,
              item.displayState == 0 else { return nil }

        let itemMatches = characterMatchesFilter(item, searchText: searchText, displayMode: displayMode)

        if item.specialCategory {
            var childNodes: [SearchResult] = []
            if !searchText.isEmpty {
                for entry in item.entries {
                    guard !Task.isCancelled else { break }
                    if let child = await buildCharacterFolderNode(itemId: entry.childId, searchText: searchText, displayMode: displayMode, parentEntryId: entry.id) {
                        childNodes.append(child)
                    }
                }
                if item.category == .folder {
                    childNodes = childNodes.sortedByRelevance()
                }
            }
            guard itemMatches || !childNodes.isEmpty else { return nil }
            var node = characterResult(item: item, searchText: searchText, displayMode: displayMode, parentEntryId: parentEntryId)
            node.children = childNodes
            node.canOpen = childNodes.isEmpty
            return node
        } else {
            guard itemMatches else { return nil }
            return characterResult(item: item, searchText: searchText, displayMode: displayMode, parentEntryId: parentEntryId)
        }
    }

    private func characterMatchesFilter(_ item: ValueModel, searchText: String, displayMode: ListDisplayModel.DisplayMode) -> Bool {
        guard !searchText.isEmpty else { return true }
        if item.name.localizedStandardContains(searchText) { return true }
        if displayMode != .compact {
            if item.description.localizedStandardContains(searchText) { return true }
        }
        if displayMode == .regular {
            if item.tags.contains(where: { $0.localizedStandardContains(searchText) }) { return true }
        }
        return false
    }

    private func characterResult(item: ValueModel, searchText: String, displayMode: ListDisplayModel.DisplayMode, parentEntryId: UUID? = nil) -> SearchResult {
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

// MARK: - Inspector search (from LinkListItemView / FolderListController)

extension SearchController {
    func inspectorSearchResults(searchText: String, listMode: ListDisplayModel.ListMode, displayMode: ListDisplayModel.DisplayMode, focusId: UUID?) async -> [SearchResult] {
        switch listMode {
        case .folder:
            // Pass searchText directly — folderModeCharacterResults / buildCharacterFolderNode
            // handle empty search correctly (characterMatchesFilter returns true for all items).
            // The old " " trick only matched items whose names contained a space.
            return await folderModeCharacterResults(searchText: searchText, focusId: focusId, displayMode: displayMode)
        case .list:
            if let focusId {
                // Sub-value items (groupId != nil) are group-entry sub-values, not root characters.
                // Return their entries as direct flat results so loadChildrenViaSearch can place
                // them as children of the group entry row — not wrapped in a character result.
                if let item = await itemController.item(for: focusId), item.groupId != nil {
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
    /// If searchText is set, only entries that match (name, content, or sub-value name) are children.
    /// For each included entry whose valueId points to a sub-value, the sub-value's own entries
    /// are added as children of that entry result.
    private func focusedCharacterInspector(characterId: UUID, searchText: String) async -> [SearchResult] {
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
                var subEntryMatch     = false   // bug fix: also search sub-entry names/content
                var subEntries: [SearchResult] = []

                if let subValueId = entry.valueId,
                   let subValue = await itemController.item(for: subValueId) {
                    subValueNameMatch = subValue.name.localizedStandardContains(searchText)
                    for subEntry in subValue.entries {
                        if subEntry.name.localizedStandardContains(searchText) ||
                           subEntry.content.localizedStandardContains(searchText) {
                            subEntryMatch = true
                        }
                    }
                    // Use subValueId as itemId — see empty-search comment above.
                    subEntries = subValue.entries.map {
                        makeEntryResult(for: $0, characterId: subValueId, characterName: subValue.name)
                    }
                }

                guard entryNameMatch || entryContentMatch || subValueNameMatch || subEntryMatch else { continue }
                var entryResult = makeEntryResult(for: entry, characterId: characterId, characterName: character.name)
                entryResult.children = subEntries
                entryChildren.append(entryResult)
            }
        }

        var result = characterResult(item: character, searchText: "", displayMode: .medium)
        result.children = entryChildren
        // Signal appendToFlat to start this item expanded so entries are visible
        // immediately — the user opened the inspector to see this character's sheet,
        // not to see a closed chevron.
        result.shouldOpen = !entryChildren.isEmpty
        return [result]
    }

    private func makeEntryResult(for entry: ValueEntryModel, characterId: UUID, characterName: String) -> SearchResult {
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
    /// - `parentId == nil`: walks all root characters (`groupId == nil`, `displayState == 0`).
    /// Inspector search used by `SearchLinkController`.
    ///
    /// Empty search is now handled properly (was `guard !searchText.isEmpty else { return [] }`
    /// which caused the inspector to show nothing on first appear):
    /// - `parentId != nil`, empty → delegates to `focusedCharacterInspector` (all entries shown)
    /// - `parentId == nil`, empty → all root characters, A→Z, `canOpen = !entries.isEmpty`
    func inspectorSearchResults(searchText: String, parentId: UUID?, displayMode: ListDisplayModel.DisplayMode = .medium) async -> [SearchResult] {
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
            // Never return entry children and never set canOpen — the user links to a character,
            // not to individual entries. Entry exploration requires the focused inspector.
            let itemIds = await itemControllable.itemDataModel.items
            for itemId in itemIds {
                guard !Task.isCancelled else { break }
                guard let character = await itemController.item(for: itemId),
                      character.groupId == nil,
                      character.displayState == 0 else { continue }
                if searchText.isEmpty {
                    foundResults.append(characterResult(item: character, searchText: "", displayMode: displayMode))
                    // canOpen intentionally omitted (defaults false) — no entry expansion in common inspector
                } else {
                    // Match at item level only — entries are not shown in the common inspector
                    guard characterMatchesFilter(character, searchText: searchText, displayMode: displayMode) else { continue }
                    foundResults.append(characterResult(item: character, searchText: searchText, displayMode: displayMode))
                }
            }
            if searchText.isEmpty {
                return foundResults.sorted { $0.itemName.localizedCompare($1.itemName) == .orderedAscending }
            }
            return foundResults.sortedByRelevance()
        }
    }

    /// Inspector search scoped to a single character (legacy helper).
    func inspectorSearchResults(searchText: String, characterId: UUID) async -> [SearchResult] {
        await inspectorSearchResults(searchText: searchText, parentId: characterId)
    }

    /// Searches `character` at item-level (displayMode-aware) and all entries (always name+content).
    /// Matching entries become children of the character result, not flat siblings.
    private func characterInspectorResult(character: ValueModel, searchText: String, displayMode: ListDisplayModel.DisplayMode, foundResults: inout [SearchResult]) async {
        let characterMatches = characterMatchesFilter(character, searchText: searchText, displayMode: displayMode)
        var entryChildren: [SearchResult] = []
        await collectValueEntries(of: character, characterId: character.id, characterName: character.name, searchText: searchText, into: &entryChildren)
        guard characterMatches || !entryChildren.isEmpty else { return }
        var result = characterResult(item: character, searchText: searchText, displayMode: displayMode)
        result.children = entryChildren.sortedByRelevance()
        foundResults.append(result)
    }

    /// Collects matching entries from `item` into `entryChildren`.
    /// Inspector always searches entry name + content, regardless of displayMode.
    /// Recurses into sub-value groups via `entry.valueId`.
    private func collectValueEntries(of item: ValueModel, characterId: UUID, characterName: String, searchText: String, into entryChildren: inout [SearchResult]) async {
        for entry in item.entries {
            guard !Task.isCancelled else { break }

            let entryMatches = entry.name.localizedStandardContains(searchText)
                            || entry.content.localizedStandardContains(searchText)

            if entryMatches {
                entryChildren.append(SearchResult(
                    itemId: characterId,
                    itemName: characterName,
                    module: itemControllable.config.module,
                    category: item.category,
                    entryId: entry.id,
                    entryName: entry.name,
                    matchedContent: entry.content.isEmpty ? nil : entry.content,
                    relevanceScore: calculateRelevance(
                        searchText: searchText,
                        itemName: characterName,
                        entryName: entry.name,
                        content: entry.content,
                        isItemMatch: false
                    )
                ))
            }

            if let subValueId = entry.valueId {
                guard let subValue = await itemController.item(for: subValueId) else { continue }
                await collectValueEntries(of: subValue, characterId: characterId, characterName: characterName, searchText: searchText, into: &entryChildren)
            }
        }
    }
}
