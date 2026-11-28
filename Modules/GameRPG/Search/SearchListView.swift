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
    let searchController: SearchGlobalController
    
    @Environment(\.locale) private var locale: Locale
    
    @State private var expandedModules: Set<NetworkModules> = []
    @State private var modules: [NetworkModules] = []
    @State private var lastSearchedRequest = GlobalSearchRequest(text: "", levelTokens: [])

    public var body: some View {
        @Bindable var model = searchController.model

        Group {
            if model.isSearching {
                ProgressView {
                    Text("Searching...", bundle: .module)
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !model.hasSearch {
                SearchListUnavailableSearchView()
            } else if !model.hasResults {
                ContentUnavailableView.search(text: model.searchText)
            } else {
                listView(model: $model)
            }
        }
        .navigationTitle(Text("Search Results", bundle: .module))
#if !os(tvOS)
        .searchable(text: $model.searchText, tokens: $model.levelTokens, placement: .sidebar,
                    prompt: Text("Search items and entries", bundle: .module)) { filter in
            LevelSearchTokenText(filter: filter)
        }
#endif
        .task(id: model.request) {
            // Only perform search if the search text or the level token has actually changed
            guard model.request != lastSearchedRequest else { return }
            lastSearchedRequest = model.request
            await searchController.performSearch()
        }
        .task(id: locale.identifier) {
            updateModulesOrder()
        }
    }
    
    private func updateModulesOrder() {
        modules = locale.identifier.hasPrefix("de")
        ? [.space, .adventure, .value, .photo, .map, .audio, .pdf, .rule, .table, .weather, .dice]
        : [.adventure, .audio, .value, .dice, .map, .pdf, .photo, .rule, .space, .table, .weather]
    }
}

private extension SearchListView {
    @ViewBuilder
    func listView(model: Bindable<GlobalSearchModel>) -> some View {
        List(selection: model.selection) {
            ForEach(modules, id: \.self) { module in
                let results = model.wrappedValue.results[module, default: []]
                if !results.isEmpty {
                    Section {
                        let isExpanded = expandedModules.contains(module)
                        let displayedResults = isExpanded ? results : Array(results.prefix(5))
                        
                        ForEach(displayedResults) { result in
                            SearchResultRow(result: result, root: root)
                                .equatable()
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
        .themedListSurface()
#if !os(visionOS)
        .scrollDismissesKeyboard(.immediately)
#endif
    }
    
    func sectionHeader(module: NetworkModules, results: [SearchResult]) -> some View {
        HStack {
            Text("\(Image(systemName: module.icon)) \(module.title)", bundle: .module)
            Text("(\(results.count))", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .moduleForegroundStyle(module)
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

// MARK: - Extracted subviews (CODE_AUDIT §8.3)
//
// Gives SwiftUI its own diffing boundary, instead of the previous computed
// `some View` property on `SearchListView` itself.

private struct SearchListUnavailableSearchView: View {
    var body: some View {
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
}

/// The level token in the search field: "Level 4", "Level 4 Adventures", "Level 9 Monsters".
private struct LevelSearchTokenText: View {
    let filter: LevelSearchFilter

    var body: some View {
        switch filter.kind {
        case .adventure: Text("Level \(filter.level) Adventures", bundle: .module)
        case .monster: Text("Level \(filter.level) Monsters", bundle: .module)
        case nil: Text("Level \(filter.level)", bundle: .module)
        }
    }
}

// MARK: - Preview

#Preview {
    SearchListView(root: GameRoot.preview, searchController: SearchGlobalController(root: GameRoot.preview, searchText: "T"))
}
