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
        return foundResults.sorted { $0.relevanceScore > $1.relevanceScore }
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
            if searchText.isEmpty && folder.category == .folder {
                results.sort { $0.itemName.localizedCompare($1.itemName) == .orderedAscending }
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
            return results
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
            for entry in item.entries {
                guard !Task.isCancelled else { break }
                if let child = await buildCharacterFolderNode(itemId: entry.childId, searchText: searchText, displayMode: displayMode, parentEntryId: entry.id) {
                    childNodes.append(child)
                }
            }
            guard itemMatches || !childNodes.isEmpty else { return nil }
            if searchText.isEmpty && item.category == .folder {
                childNodes.sort { $0.itemName.localizedCompare($1.itemName) == .orderedAscending }
            }
            var node = characterResult(item: item, searchText: searchText, displayMode: displayMode, parentEntryId: parentEntryId)
            node.children = childNodes
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
            return await folderModeCharacterResults(searchText: searchText.isEmpty ? " " : searchText, focusId: focusId, displayMode: displayMode)
        case .list:
            return await inspectorSearchResults(searchText: searchText, parentId: focusId, displayMode: displayMode)
        }
    }

    /// Inspector search used by `SearchLinkController`.
    ///
    /// - `parentId != nil`: scoped to the given character. All results carry that character's
    ///   `itemId` so the UI navigates back to the character, not into a sub-value group.
    /// - `parentId == nil`: walks all root characters (`groupId == nil`, `displayState == 0`).
    func inspectorSearchResults(searchText: String, parentId: UUID?, displayMode: ListDisplayModel.DisplayMode = .medium) async -> [SearchResult] {
        guard !searchText.isEmpty else { return [] }
        var foundResults: [SearchResult] = []
        if let parentId {
            guard let character = await itemController.item(for: parentId) else { return [] }
            await characterInspectorResult(character: character, searchText: searchText, displayMode: displayMode, foundResults: &foundResults)
            return foundResults // not sorting!
        } else {
            let itemIds = await itemControllable.itemDataModel.items
            for itemId in itemIds {
                guard !Task.isCancelled else { break }
                guard let character = await itemController.item(for: itemId),
                      character.groupId == nil,
                      character.displayState == 0 else { continue }
                await characterInspectorResult(character: character, searchText: searchText, displayMode: displayMode, foundResults: &foundResults)
            }
            return foundResults.sorted { $0.relevanceScore > $1.relevanceScore }
        }
    }

    /// Inspector search scoped to a single character (legacy helper).
    func inspectorSearchResults(searchText: String, characterId: UUID) async -> [SearchResult] {
        await inspectorSearchResults(searchText: searchText, parentId: characterId)
    }

    /// Searches `character` name/description and all entries at every level of the value tree.
    /// Item-level match respects `displayMode`; entry content is always searched in full.
    private func characterInspectorResult(character: ValueModel, searchText: String, displayMode: ListDisplayModel.DisplayMode, foundResults: inout [SearchResult]) async {
        if characterMatchesFilter(character, searchText: searchText, displayMode: displayMode) {
            foundResults.append(characterResult(item: character, searchText: searchText, displayMode: displayMode))
        }
        await searchValueEntries(of: character, characterId: character.id, characterName: character.name, searchText: searchText, displayMode: displayMode, foundResults: &foundResults)
    }

    /// Walks all entries of `item`, appending hits with `characterId`/`characterName` as the result
    /// anchor. Recurses into sub-value groups via `entry.valueId`.
    /// compact → name only; medium/regular → name + content
    private func searchValueEntries(of item: ValueModel, characterId: UUID, characterName: String, searchText: String, displayMode: ListDisplayModel.DisplayMode, foundResults: inout [SearchResult]) async {
        for entry in item.entries {
            guard !Task.isCancelled else { break }

            let entryMatches = entry.name.localizedStandardContains(searchText)
                || (displayMode != .compact && entry.content.localizedStandardContains(searchText))

            if entryMatches {
                foundResults.append(SearchResult(
                    itemId: characterId,
                    itemName: characterName,
                    module: itemControllable.config.module,
                    category: item.category,
                    entryId: entry.id,
                    entryName: entry.name,
                    matchedContent: displayMode != .compact && !entry.content.isEmpty ? entry.content : nil,
                    relevanceScore: calculateRelevance(
                        searchText: searchText,
                        itemName: characterName,
                        entryName: entry.name,
                        content: displayMode != .compact ? entry.content : nil,
                        isItemMatch: false
                    )
                ))
            }

            if let subValueId = entry.valueId {
                guard let subValue = await itemController.item(for: subValueId) else { continue }
                await searchValueEntries(of: subValue, characterId: characterId, characterName: characterName, searchText: searchText, displayMode: displayMode, foundResults: &foundResults)
            }
        }
    }
}
