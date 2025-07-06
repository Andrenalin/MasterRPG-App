// @copyright André Trettin

import AndrenalinKit
import CoreRPG
import SwiftUI


public struct PhotoRootView: View {
    public init() {}
    
    @Environment(ListModel.self) private var listModel
    @Environment(TabTitleModel.self) private var tabTitleModel
#if os(iOS)
@Environment(\.horizontalSizeClass) private var horizontalSizeClass
@Environment(\.tabBarPlacement) private var tabBarPlacement
#endif

    @State private var selectionModel = ListSelectionModel<PhotoDataModel>()
    
    @State private var column: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    
    public var body: some View {
        @Bindable var listModel = listModel
        NavigationSplitView(columnVisibility: $column, preferredCompactColumn: $preferredCompactColumn) {
            PhotoListView()
                .environment(selectionModel)
                .searchable(text: $listModel.searchText, placement: .automatic, prompt: "Search")
                .searchScopes($listModel.searchToken, activation: searchScopeActivition) {
                    ForEach(listModel.categoryTags) { category in
                        Label(category.title, systemImage: category.icon)
                            .tag(category)
                    }
                }
                .searchPresentationToolbarBehavior(.avoidHidingContent)
        } detail: {
            if let selected = selectionModel.selectedItem {
                DetailView(item: selected)
                    .environment(selectionModel)
            } else {
                ContentUnavailableView("Photo", image: "photos")
            }
        }
        .ignoresSafeArea(edges: .top)
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
