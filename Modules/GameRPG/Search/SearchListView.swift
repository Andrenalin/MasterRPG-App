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
    @State private var modules: [NetworkModules] = []

    public var body: some View {
        @Bindable var model = searchController.model

        Group {
            if model.isSearching {
                ProgressView("Searching...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.searchText.isEmpty {
                unavailableSearch
            } else if model.results.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            } else {
                listView(model: $model)
            }
        }
        .navigationTitle("Search Results")
        .searchable(text: $model.searchText, prompt: "Search items and entries")
        .task(id: model.searchText) {
            await searchController.performSearch()
        }
        .task(id: locale.identifier) {
            updateModulesOrder()
        }
    }

    private func updateModulesOrder() {
        modules = locale.identifier.hasPrefix("de")
            ? [.space, .adventure, .value, .photo, .map, .audio, .pdf, .table, .weather, .dice]
            : [.adventure, .audio, .value, .dice, .map, .pdf, .photo, .space, .table, .weather]
    }
}

private extension SearchListView {
    var unavailableSearch: some View {
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
    func listView(model: Bindable<SearchModel>) -> some View {
        List(selection: model.selection) {
            ForEach(modules, id: \.self) { module in
                let results = model.wrappedValue.results[module, default: []]
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
