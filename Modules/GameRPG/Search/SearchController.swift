// @copyright André Trettin

import CoreRPG
import Foundation
import AdventureRPG
import MapRPG
import TableRPG
import AudioRPG
import CharacterRPG
import PdfRPG
import DiceRPG
import PhotoRPG
import WeatherRPG
import SpaceRPG

@MainActor
@Observable
final class SearchController {
    init(root: GameRoot, searchText: String = "") {
        self.root = root
        self.searchText = searchText
        self.results = [:]
        self.isSearching = false
    }

    let root: GameRoot

    var searchText: String
    var results: [NetworkModules: [SearchResult]] = [:]
    var isSearching = false

    private var searchTask: Task<Void, Never>?

    func performSearch() async {
        // Cancel any ongoing search
        searchTask?.cancel()

        guard !searchText.isEmpty else {
            results = [:]
            return
        }

        let searchTask = Task {
            isSearching = true
            defer { isSearching = false }

            // Small delay to debounce rapid typing
            try? await Task.sleep(for: .milliseconds(300))

            guard !Task.isCancelled else { return }

            results = await searchAllItems()
        }

        self.searchTask = searchTask
        await searchTask.value
    }

    private func searchAllItems() async -> [NetworkModules: [SearchResult]] {
        var result: [NetworkModules: [SearchResult]] = [:]
        result[.adventure] = await searchItems(in: root.adventureRoot.rootController)
        result[.audio] = await searchItems(in: root.audioRoot.rootController)
        result[.value] = await searchItems(in: root.characterRoot.rootController)
        result[.dice] = await searchItems(in: root.diceRoot.rootController)
        result[.map] = await searchItems(in: root.mapRoot.rootController)
        result[.pdf] = await searchItems(in: root.pdfRoot.rootController)
        result[.photo] = await searchItems(in: root.photoRoot.rootController)
        result[.space] = await searchItems(in: root.spaceRoot.rootController)
        result[.table] = await searchItems(in: root.tableRoot.rootController)
        result[.weather] = await searchItems(in: root.weatherRoot.rootController)

        return result
    }

    private func searchItems(in moduleRoot: ItemRootController) async -> [SearchResult] {

        let itemIds = moduleRoot.itemControllable.itemDataModel.items
        var foundResults: [SearchResult] = []

        for itemId in itemIds {
            guard !Task.isCancelled else { break }

            guard let item = await moduleRoot.itemControllable.item(for: itemId) else { continue }

            // Check if item matches search
            let itemMatches = item.filter(filter: searchText, includeEntries: false)

            if itemMatches {
                let relevance = SearchResult.calculateRelevance(
                    searchText: searchText,
                    itemName: item.name,
                    entryName: nil,
                    content: item.description,
                    isItemMatch: true
                )
                foundResults.append(SearchResult(
                    itemId: item.id,
                    itemName: item.name,
                    module: moduleRoot.configurable.module,
                    categoryName: item.category.title,
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
                        let relevance = SearchResult.calculateRelevance(
                            searchText: searchText,
                            itemName: item.name,
                            entryName: entry.name,
                            content: entry.content,
                            isItemMatch: false
                        )
                        foundResults.append(SearchResult(
                            itemId: item.id,
                            itemName: item.name,
                            module: moduleRoot.configurable.module,
                            categoryName: item.category.title,
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
}
