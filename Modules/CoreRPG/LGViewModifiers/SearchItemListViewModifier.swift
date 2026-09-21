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
                            searchModel.selectedTokens.append(suggestion)
                            searchModel.searchFieldText = ""
                            listControllable.resetFilter()
                        }
                    } label: {
                        Label(suggestion.tag, systemImage: "tag")
                    }
                }
            }
#endif
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .onChange(of: searchModel.searchFieldText) {
                guard searchModel.searchFieldText.starts(with: "@") == false || searchModel.searchFieldText.count > 1 else {
                    return
                }
                withAnimation { searchModel.searchText = searchModel.searchFieldText }
            }
            .onChange(of: searchModel.searchText) {
                updateSearch()
            }
            .onChange(of: searchModel.selectedTokens) {
                guard searchModel.selectedTokens.isEmpty else { return }
                updateSearch()
            }
    }
    
    func updateSearch() {
        withAnimation {
            listControllable.resetFilter()
            listControllable.cacheListItemModel.reset(search: listControllable.searchModel.searchText)
            listControllable.searchModel.updateTagSuggestions()
            listControllable.searchModel.searchFieldText <=> listControllable.searchModel.searchText
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
    
    var searchScopeActivation: SearchScopeActivation {
#if os(tvOS)
        .automatic
#else
        .onSearchPresentation
#endif
    }
}

