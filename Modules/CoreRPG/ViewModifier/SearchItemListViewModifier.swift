// @copyright André Trettin

import SwiftUI

extension View {
    func searchItemList(listControllable: any ListControllable) -> some View {
        modifier(SearchItemListViewModifier(listControllable: listControllable))
    }
}

struct SearchItemListViewModifier: ViewModifier {
    let listControllable: any ListControllable
    
    @Environment(CacheItemListModel.self) private var cacheItemListModel
    
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
                ForEach(searchModel.filteredTagSuggestions) { suggestion in
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
                guard searchModel.searchFieldText.starts(with: "@") == false else { return }
                withAnimation { searchModel.searchText = searchModel.searchFieldText }
            }
            .onChange(of: searchModel.searchText, initial: true) {
                withAnimation {
                    listControllable.resetFilter()
                    cacheItemListModel.reset(search: searchModel.searchText)
                }
            }
    }
    
    var searchPlacement: SearchFieldPlacement {
        .automatic
    }
    
    var searchScopeActivition: SearchScopeActivation {
#if os(tvOS)
        .automatic
#else
        .onSearchPresentation
#endif
    }
}

