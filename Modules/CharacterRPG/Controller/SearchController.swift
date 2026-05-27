// @copyright André Trettin

import CoreRPG
import Foundation

struct SearchController: Sendable {
    let itemController: ItemController
}

extension SearchController: SearchControllable {
    var itemControllable: any ItemControllable { itemController }

    /// Protocol conformance — delegates to `listSearch` for use by the folder list.
    func searchItems(searchText: String) async -> [SearchResult] {
        await listSearch(searchText: searchText)
    }

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
    func listSearch(searchText: String) async -> [SearchResult] {
        guard !searchText.isEmpty else { return [] }

        let itemIds = await itemControllable.itemDataModel.items
        var foundResults: [SearchResult] = []

        for itemId in itemIds {
            guard !Task.isCancelled else { break }
            guard let item = await itemController.item(for: itemId),
                  item.groupId == nil,      // root characters and folders only
                  item.displayState == 0 else { continue }

            if item.specialCategory {
                // Folder / collection — search its children entries
                await result(item: item, searchText: searchText, foundResults: &foundResults)
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

    /// Inspector search scoped to a single character.
    /// Delegates to `inspectorResult` which walks the full value tree — including groups that
    /// may be `specialCategory == true` — and searches every entry at every level.
    func inspectorSearch(searchText: String, characterId: UUID) async -> [SearchResult] {
        guard !searchText.isEmpty else { return [] }
        guard let character = await itemController.item(for: characterId) else { return [] }
        var foundResults: [SearchResult] = []
        await inspectorResult(item: character, searchText: searchText, foundResults: &foundResults)
        return foundResults.sorted { $0.relevanceScore > $1.relevanceScore }
    }

    /// Inspector traversal: searches name/description **and** all entries regardless of
    /// `specialCategory`, then follows every `ValueEntryModel.valueId` link recursively.
    ///
    /// Unlike `result()`, this never skips a value's entries based on its category —
    /// character groups (which are often `specialCategory`) must be fully traversed so their
    /// entries are returned as search hits in the inspector list.
    private func inspectorResult(item: ValueModel, searchText: String, foundResults: inout [SearchResult]) async {
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

        // Entry-level matches — always searched, including inside specialCategory groups
        for entry in item.entries {
            guard !Task.isCancelled else { break }

            if entry.filter(with: searchText) {
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

            // Recurse into linked sub-values (groups / nested stat blocks)
            if let subValueId = entry.valueId {
                guard let subValue = await itemController.item(for: subValueId) else { continue }
                await inspectorResult(item: subValue, searchText: searchText, foundResults: &foundResults)
            }
        }
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
