// @copyright André Trettin

import CoreRPG
import SwiftUI
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
public struct SearchRootView: View {
    public init(root: GameRoot, searchText: String = "") {
        self.root = root
        self._searchController = State(initialValue: SearchController(root: root, searchText: searchText))
    }

    let root: GameRoot

    @State private var searchController: SearchController
    @State private var selection: UUID?

    let modules: [NetworkModules] = [.adventure, .audio, .value, .dice, .map, .pdf, .photo, .space, .table, .weather]
    
    public var body: some View {
        NavigationSplitView {
            searchResultsList
                .navigationTitle("Search Results")
                .searchable(text: $searchController.searchText, prompt: "Search items and entries")
                .task(id: searchController.searchText) {
                    await searchController.performSearch()
                }
        } detail: {
            if let selection {
            
//                ItemDetailRootView(
//                    detailListController: root.folderListControllable,
//                    selectedModel: root.itemControllable.itemOrEmpty(for: selection)
//                ) {
//                    root.viewControllable.header(for: selection)
//                } editor: {
//                    root.viewControllable.editor(for: selection)
//                } inspector: {
//                    root.viewControllable.inspector(for: selection)
//                }
//                .id(selection)
                Text("Found something")
            } else {
                ContentUnavailableView {
                    Label("No Selection", systemImage: "magnifyingglass")
                } description: {
                    Text("Select a search result to view details")
                }
            }
        }
    }
}

private extension SearchRootView {
    @ViewBuilder var searchResultsList: some View {
        if searchController.isSearching {
            ProgressView("Searching...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if searchController.searchText.isEmpty {
            ContentUnavailableView {
                Label("Search", systemImage: "magnifyingglass")
            } description: {
                Text("Enter text to search across all items and entries")
            }
        } else if searchController.results.isEmpty {
            ContentUnavailableView.search(text: searchController.searchText)
        } else {
            List(modules, id: \.self) { module in
                Section(module.title) {
                    ForEach(searchController.results[module, default: []]) { result in
                        SearchResultRow(result: result, root: root)
                            .tag(result.itemId)
                    }
                }
                .sectionIndexLabel(module.title.prefix(1))
            }
        }
    }
}

// MARK: - Search Result Row

private struct SearchResultRow: View {
    let result: SearchResult
    let root: GameRoot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: itemRootController.configurable.module.icon)
                    .foregroundStyle(itemRootController.configurable.module.tint)

                Text(result.itemName)
                    .font(.headline)

                if !result.categoryName.isEmpty {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(result.categoryName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let entryName = result.entryName {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(entryName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let matchedContent = result.matchedContent {
                Text(matchedContent)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
    
    var itemRootController: ItemRootController {
        switch result.module {
        case .adventure:
            root.adventureRoot.rootController
        case .audio:
            root.audioRoot.rootController
        case .value:
            root.characterRoot.rootController
        case .dice:
            root.diceRoot.rootController
        case .map:
            root.mapRoot.rootController
        case .pdf:
            root.pdfRoot.rootController
        case .photo:
            root.photoRoot.rootController
        case .space:
            root.spaceRoot.rootController
        case .table:
            root.tableRoot.rootController
        case .weather:
            root.weatherRoot.rootController
        default:
            root.adventureRoot.rootController
        }
    }
}

// MARK: - Search Controller

@MainActor
@Observable
private final class SearchController {
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
            
            let foundResults = await searchAllItems()
            
            guard !Task.isCancelled else { return }
            
            results = foundResults
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
            guard !Task.isCancelled, foundResults.count < 5 else { break }

            guard let item = await moduleRoot.itemControllable.item(for: itemId) else { continue }

            // Check if item matches search
            let itemMatches = item.filter(filter: searchText, includeEntries: false)

            if itemMatches {
                foundResults.append(SearchResult(
                    itemId: item.id,
                    itemName: item.name,
                    module: moduleRoot.configurable.module,
                    categoryName: item.category.title,
                    entryId: nil,
                    entryName: nil,
                    matchedContent: item.description.isEmpty ? nil : item.description
                ))
            }

            if !item.specialCategory {
                // Search through entries
                for entry in item.entries {
                    guard !Task.isCancelled else { break }
                    
                    if entry.filter(with: searchText) {
                        foundResults.append(SearchResult(
                            itemId: item.id,
                            itemName: item.name,
                            module: moduleRoot.configurable.module,
                            categoryName: item.category.title,
                            entryId: entry.id,
                            entryName: entry.name,
                            matchedContent: entry.content.isEmpty ? nil : entry.content
                        ))
                    }
                }
            }
        }

        return foundResults
    }
}

// MARK: - Search Result Model

private struct SearchResult: Identifiable {
    let itemId: UUID
    let itemName: String
    let module: NetworkModules
    let categoryName: String
    let entryId: UUID?
    let entryName: String?
    let matchedContent: String?

    var id: String {
        if let entryId {
            return "\(itemId.uuidString)-\(entryId.uuidString)"
        }
        return itemId.uuidString
    }
}

// MARK: - Preview

//#Preview {
//    SearchRootView(root: .preview)
//}
