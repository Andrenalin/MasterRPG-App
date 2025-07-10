// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct PhotoRootView: View {
    public init() {}

    @Environment(CacheItemListModel.self) private var cacheItemListModel
    @Environment(SearchModel.self) private var searchModel
    @Environment(TabTitleModel.self) private var tabTitleModel
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.tabBarPlacement) private var tabBarPlacement
#endif
    @State private var rootModel = PhotoRootModel()

    @State private var selectionModel = ListSelectionModel<PhotoDataModel>()

    @State private var column: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    public var body: some View {
        @Bindable var searchModel = searchModel
        NavigationSplitView(columnVisibility: $column, preferredCompactColumn: $preferredCompactColumn) {
            PhotoListView()
                .environment(selectionModel)
                .searchable(text: $searchModel.searchText, placement: .automatic, prompt: "Search")
                .searchScopes($searchModel.searchToken, activation: searchScopeActivition) {
                    ForEach(searchModel.categoryTags) { category in
                        Label(category.title, systemImage: category.icon)
                            .tag(category)
                    }
                }
                .searchPresentationToolbarBehavior(.avoidHidingContent)
                .onChange(of: searchModel.searchText, initial: true) {
                    cacheItemListModel.reset(search: searchModel.searchText)
                }
        } detail: {
            if let selected = selectionModel.selectedItem {
                DetailView(item: selected)
                    .environment(selectionModel)
            } else {
                ContentUnavailableView("Photo", image: "photos")
            }
        }
        .ignoresSafeArea(edges: .top)
        .environment(rootModel)
#if os(iOS)
        .onChange(of: tabBarPlacement, initial: true) {
            tabTitleModel.toggleTitles(horizontalSizeClass: horizontalSizeClass, tabBarPlacement: tabBarPlacement)
        }
#endif

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
