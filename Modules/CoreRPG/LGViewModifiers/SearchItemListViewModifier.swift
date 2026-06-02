// @copyright André Trettin

import SwiftUI

extension View {
    public func searchItemList(listControllable: any FolderListControllable) -> some View {
        modifier(SearchItemListViewModifier(listControllable: listControllable))
    }
}

struct SearchItemListViewModifier: ViewModifier {
    let listControllable: any FolderListControllable

    /// Owns the debounce-then-search task so each new keystroke cancels the previous.
    @State private var searchTask: Task<Void, Never>?

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
            .onChange(of: searchModel.searchText, initial: true) {
                updateSearch()
            }
            .onChange(of: searchModel.selectedTokens) {
                guard searchModel.selectedTokens.isEmpty else { return }
                updateSearch()
            }
    }
    
    func updateSearch() {
        // Cancel any in-flight debounce or search from the previous keystroke
        searchTask?.cancel()

        withAnimation {
            listControllable.resetFilter()
            listControllable.cacheListItemModel.reset(search: listControllable.searchModel.searchText)
            listControllable.searchModel.updateTagSuggestions()
            listControllable.searchModel.searchFieldText <=> listControllable.searchModel.searchText
        }

        // The debounce now lives here so each keystroke cancels the previous wait.
        // performSearch() is a clean async function — structured cancellation propagates correctly.
        searchTask = Task {
            do {
                if !listControllable.searchModel.searchText.isEmpty {
                    try await Task.sleep(for: .milliseconds(300))
                }
            } catch {
                return  // Cancelled by next keystroke — stop cleanly
            }
            await listControllable.performSearch()
        }
    }
    
    var searchPlacement: SearchFieldPlacement {
#if os(iOS) || os(visionOS)
        .navigationBarDrawer(displayMode: .always)
#else
        .automatic
#endif
    }
    
    var searchScopeActivition: SearchScopeActivation {
#if os(tvOS)
        .automatic
#else
        .onSearchPresentation
#endif
    }
}

