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

struct SearchListView: View {
    let root: GameRoot
    let searchController: SearchController

    @Environment(\.locale) private var locale: Locale

    @State private var expandedModules: Set<NetworkModules> = []

    var modules: [NetworkModules] {
        if locale.identifier.hasPrefix("de") {
            [.space, .adventure, .value, .photo, .map, .audio, .pdf, .table, .weather, .dice]
        } else {
            [.adventure, .audio, .value, .dice, .map, .pdf, .photo, .space, .table, .weather]
        }
    }

    public var body: some View {
        @Bindable var model = searchController.model
        
        Group {
            if searchController.model.isSearching {
                ProgressView("Searching...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchController.model.searchText.isEmpty {
                unavailbleSearch
            } else if searchController.model.results.isEmpty {
                ContentUnavailableView.search(text: searchController.model.searchText)
            } else {
                listView
            }
        }
        .navigationTitle("Search Results")
        .searchable(text: $model.searchText, prompt: "Search items and entries")
        .task(id: searchController.model.searchText) {
            await searchController.performSearch()
        }
    }
}

private extension SearchListView {
    var unavailbleSearch: some View {
        ContentUnavailableView {
            Label {
                Text("Search", bundle: .module)
            } icon: {
                Image(systemName: "magnifyingglass")
            }
        } description: {
            Text("Enter text to search across all items and entries", bundle: .module)
        }
    }

    @ViewBuilder
    var listView: some View {
        @Bindable var model = searchController.model
        
        List(selection: $model.selection) {
            ForEach(modules, id: \.self) { module in
                let results = searchController.model.results[module, default: []]
                if !results.isEmpty {
                    Section {
                        let isExpanded = expandedModules.contains(module)
                        let displayedResults = isExpanded ? results : Array(results.prefix(5))
                        
                        ForEach(displayedResults) { result in
                            NavigationLink(value: result) {
                                SearchResultRow(result: result, root: root)
                            }
                            .tag(result)
                        }
                        
                        expandView(module: module, results: results)
                    } header: {
                        sectionHeader(module: module, results: results)
                    }
                    .sectionIndexLabel(module.title.prefix(2))
                }
            }
        }
#if !os(visionOS)
        .scrollDismissesKeyboard(.immediately)
#endif
    }
    
    func sectionHeader(module: NetworkModules, results: [SearchResult]) -> some View {
        HStack {
            Text("\(Image(systemName: module.icon)) \(module.title)")
            Text("(\(results.count))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(module.tint)
    }
    
    @ViewBuilder
    func expandView(module: NetworkModules, results: [SearchResult]) -> some View {
        let isExpanded = expandedModules.contains(module)
        
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
                    Text(isExpanded ? "Show Less" : "Show All (\(results.count) results)", bundle: .module)
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

    }
}

// MARK: - Preview

#Preview {
    SearchListView(root: GameRoot.preview, searchController: SearchController(root: GameRoot.preview, searchText: "T"))
}
