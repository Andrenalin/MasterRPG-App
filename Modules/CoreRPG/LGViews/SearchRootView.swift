// @copyright André Trettin

import SwiftUI

@MainActor
public struct SearchRootView: View {
    public init(root: ItemRootController, searchText: String = "") {
        self.root = root
        self._searchController = State(initialValue: SearchController(root: root, searchText: searchText))
    }

    let root: ItemRootController

    @State private var searchController: SearchController
    @State private var selection: UUID?

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
            List(selection: $selection) {
                ForEach(searchController.results) { result in
                    SearchResultRow(result: result, root: root)
                        .tag(result.itemId)
                }
            }
        }
    }
}

// MARK: - Search Result Row

private struct SearchResultRow: View {
    let result: SearchResult
    let root: ItemRootController

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: root.configurable.module.icon)
                    .foregroundStyle(root.configurable.module.tint)

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
}

// MARK: - Search Controller

@MainActor
@Observable
private final class SearchController {
    init(root: ItemRootController, searchText: String = "") {
        self.root = root
        self.searchText = searchText
        self.results = []
        self.isSearching = false
    }

    let root: ItemRootController

    var searchText: String
    var results: [SearchResult] = []
    var isSearching = false

    private var searchTask: Task<Void, Never>?

    func performSearch() async {
        // Cancel any ongoing search
        searchTask?.cancel()

        guard !searchText.isEmpty else {
            results = []
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

    private func searchAllItems() async -> [SearchResult] {
        let itemIds = await root.itemControllable.itemDataModel.items
        var foundResults: [SearchResult] = []

        for itemId in itemIds {
            guard !Task.isCancelled else { break }

            guard let item = await root.itemControllable.item(for: itemId) else { continue }

            // Check if item matches search
            let itemMatches = item.filter(searchText)

            if itemMatches {
                foundResults.append(SearchResult(
                    itemId: item.id,
                    itemName: item.name,
                    categoryName: item.category.title,
                    entryId: nil,
                    entryName: nil,
                    matchedContent: item.description.isEmpty ? nil : item.description
                ))
            }

            // Search through entries
            for entry in item.entries {
                guard !Task.isCancelled else { break }

                if entry.filter(with: searchText) {
                    foundResults.append(SearchResult(
                        itemId: item.id,
                        itemName: item.name,
                        categoryName: item.category.title,
                        entryId: entry.id,
                        entryName: entry.name,
                        matchedContent: entry.content.isEmpty ? nil : entry.content
                    ))
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
