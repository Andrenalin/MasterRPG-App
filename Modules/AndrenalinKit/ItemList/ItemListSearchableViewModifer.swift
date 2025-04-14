// @copyright André Trettin

import SwiftUI

struct ItemListSearchableViewModifer: ViewModifier {
    let listController: any ListControllable

    @State private var selectedItems: Set<ItemRowTreeModel> = []

    func body(content: Content) -> some View {
        @Bindable var itemListModel = listController.model

        content
            .overlay {
                if itemListModel.filteredItems.isEmpty && !itemListModel.searchText.isEmpty {
                    ContentUnavailableView.search
                }
            }
#if !os(tvOS)
            .searchable(text: $itemListModel.searchText, tokens: $itemListModel.selectedTokens, isPresented: $itemListModel.isSearching, placement: searchPlacement, prompt: Text("Search or use @ for tags", bundle: .module), token: { token in
                Label(token.tag.prefix(3), systemImage: "tag")
            })
#endif
            .searchScopes($itemListModel.searchToken, activation: searchScopeActivition) {
                ForEach(itemListModel.categoryTags) { category in
                    Text(category.title).tag(category)
                }
            }
            .searchSuggestions {
                ForEach(listController.filteredTagSuggestions) { suggestion in
                    Button {
                        withAnimation {
                            itemListModel.selectedTokens.append(suggestion)
                            itemListModel.searchText = ""
                        }
                    } label: {
                        Label(suggestion.tag, systemImage: "tag")
                    }
                }
            }
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .onChange(of: itemListModel.searchText, initial: false) {
                withAnimation { listController.filter(text: itemListModel.searchText, selectedTokens: itemListModel.selectedTokens, searchToken: itemListModel.searchToken) }
            }
            .onChange(of: itemListModel.searchToken, initial: false) {
                withAnimation { listController.filter(text: itemListModel.searchText, selectedTokens: itemListModel.selectedTokens, searchToken: itemListModel.searchToken) }
            }
            .onChange(of: itemListModel.selectedTokens, initial: false) { old, new in
                withAnimation { listController.filter(text: itemListModel.searchText, selectedTokens: itemListModel.selectedTokens, searchToken: itemListModel.searchToken) }
            }
            .onAppear {
                guard listController.model.selectionMode != nil || (!itemListModel.isSearching && itemListModel.searchToken != .all) else { return }
                Task { @MainActor in
                    try await Task.sleep(for: .seconds(0.25))
                    withAnimation { itemListModel.isSearching = true }
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

