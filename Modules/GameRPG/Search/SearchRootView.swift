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

public struct SearchRootView: View {
    public init(root: GameRoot, searchText: String = "") {
        self.root = root
        self._searchController = State(initialValue: SearchController(root: root, searchText: searchText))
    }

    let root: GameRoot

    @Environment(\.locale) private var locale: Locale

    @State private var searchController: SearchController
    @State private var selection: SearchResult?
    @State private var expandedModules: Set<NetworkModules> = []

    var modules: [NetworkModules] {
        if locale.identifier.hasPrefix("de") {
            [.space, .adventure, .value, .photo, .map, .audio, .pdf, .table, .weather, .dice]
        } else {
            [.adventure, .audio, .value, .dice, .map, .pdf, .photo, .space, .table, .weather]
        }
    }

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
                Group {
                    switch selection.module {
                    case .adventure: root.adventureRoot.viewController.inlineViewer(root: root.adventureRoot, with: selection.itemId)
                    case .audio: AudioFactory.detailView(root: root.audioRoot)
                    case .dice: DiceFactory.detailView(root: root.diceRoot)
                    case .map: root.mapRoot.viewController.inlineViewer(root: root.mapRoot, with: selection.itemId)
                    case .pdf: root.pdfRoot.viewController.inlineViewer(root: root.pdfRoot, with: selection.itemId, entryId: selection.entryId, withoutBookmark: true)
                    case .photo: root.photoRoot.viewController.inlineViewer(root: root.photoRoot, with: selection.itemId)
                    case .space: root.spaceRoot.viewController.inlineViewer(root: root.spaceRoot, with: selection.itemId)
                    case .table: root.tableRoot.viewController.inlineViewer(root: root.tableRoot, with: selection.itemId)
                    case .value: root.characterRoot.viewController.inlineViewer(root: root.characterRoot, with: selection.itemId)
                    case .weather: root.weatherRoot.viewController.inlineViewer(root: root.weatherRoot, with: selection.itemId)
                    default: EmptyView()
                    }
                }
                .id(selection.id)
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
                ForEach(modules, id: \.self) { module in
                    let results = searchController.results[module, default: []]
                    if !results.isEmpty {
                        Section {
                            let isExpanded = expandedModules.contains(module)
                            let displayedResults = isExpanded ? results : Array(results.prefix(5))

                            ForEach(displayedResults) { result in
                                SearchResultRow(result: result, root: root)
                                    .tag(result)
                            }

                            if results.count > 5 {
                                Button {
                                    withAnimation {
                                        if isExpanded {
                                            expandedModules.remove(module)
                                        } else {
                                            expandedModules.insert(module)
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(isExpanded ? "Show Less" : "Show All (\(results.count) results)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            HStack {
                                Text("\(Image(systemName: module.icon)) \(module.title)")
                                Text("(\(results.count))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .foregroundStyle(module.tint)
                        }
                        .sectionIndexLabel(module.title.prefix(2))
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SearchRootView(root: GameRoot.preview, searchText: "T")
}
