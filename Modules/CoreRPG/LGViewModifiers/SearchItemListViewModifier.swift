// @copyright André Trettin

import SwiftUI

extension View {
    public func searchItemList(listControllable: any FolderListControllable) -> some View {
        modifier(SearchItemListViewModifier(listControllable: listControllable))
    }
}

struct SearchItemListViewModifier: ViewModifier {
    let listControllable: any FolderListControllable

    func body(content: Content) -> some View {
        @Bindable var searchModel = listControllable.searchModel
        content
#if os(tvOS)
            .searchable(text: $searchModel.searchFieldText, placement: .automatic, prompt: Text("Search for items", bundle: .module))
#else
            .searchable(text: $searchModel.searchFieldText, tokens: $searchModel.selectedTokens, placement: searchPlacement, prompt: Text("Search or use @ for tags", bundle: .module), token: { token in
                Label(token.tag.prefix(3), systemImage: "tag")
            })
            .searchSuggestions {
                ForEach(searchModel.searchTags) { suggestion in
                    Button {
                        withAnimation {
                            searchModel.select(token: suggestion)
                            listControllable.resetFilter()
                        }
                    } label: {
                        Label(suggestion.tag, systemImage: "tag")
                    }
                }
            }
#endif
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .onAppear {
                // The model can already hold a search typed elsewhere (e.g. the inspector filter
                // field binds `searchText` directly); `searchFieldText` only syncs on change.
                searchModel.searchFieldText <=> searchModel.searchText
            }
            .onChange(of: searchModel.searchFieldText) {
                // "@dra" looks up tags to pick; only other entries are searched as text.
                searchModel.updateTagSuggestions()
                let text = SearchModel.searchText(forField: searchModel.searchFieldText)
                withAnimation { searchModel.searchText = text }
            }
            .onChange(of: searchModel.searchText) {
                updateSearch()
            }
            .onChange(of: searchModel.selectedTokens) {
                // Every added or removed token changes the filter.
                updateSearch()
            }
    }
    
    func updateSearch() {
        withAnimation {
            listControllable.resetFilter()
            listControllable.cacheListItemModel.reset(search: listControllable.searchModel.searchText)
            listControllable.searchModel.updateTagSuggestions()
            // A "@…" entry is being typed as a tag lookup; the text search it stands for is empty.
            if !listControllable.searchModel.searchFieldText.starts(with: "@") {
                listControllable.searchModel.searchFieldText <=> listControllable.searchModel.searchText
            }
        }
        // The single search pipeline owns the debounce + cancellation now.
        listControllable.scheduleSearch()
    }
    
    var searchPlacement: SearchFieldPlacement {
#if os(iOS) || os(visionOS)
        .navigationBarDrawer(displayMode: .always)
#else
        .automatic
#endif
    }
    
}

