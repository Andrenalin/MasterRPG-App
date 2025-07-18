// @copyright André Trettin

import CoreExternalRPG
import SwiftUI

public struct RootView<DataModel, List: View, Detail: View>: View {
    public init(module: NetworkModules, selectionModel: ListSelectionModel<DataModel>, withoutNavigation: Bool, @ViewBuilder list: () -> List, @ViewBuilder detail: () -> Detail) {
        self.module = module
        self.selectionModel = selectionModel
        self.withoutNavigation = withoutNavigation
        self.list = list()
        self.detail = detail()
    }
    
    let module: NetworkModules
    let selectionModel: ListSelectionModel<DataModel>
    let withoutNavigation: Bool
    let list: List
    let detail: Detail

    @Environment(CacheItemListModel.self) private var cacheItemListModel
    @Environment(SearchModel.self) private var searchModel
    @Environment(TabTitleModel.self) private var tabTitleModel
    
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.tabBarPlacement) private var tabBarPlacement
#endif
    
    @State private var column: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    public var body: some View {
        Group {
            if withoutNavigation {
                listRoot
            } else {
                splitRoot
            }
        }
#if os(iOS)
        .onChange(of: tabBarPlacement, initial: true) {
            tabTitleModel.toggleTitles(horizontalSizeClass: horizontalSizeClass, tabBarPlacement: tabBarPlacement)
        }
#endif
    }
    
    @ViewBuilder
    private var splitRoot: some View {
        NavigationSplitView(columnVisibility: $column, preferredCompactColumn: $preferredCompactColumn) {
            ManagedPresentationView {
                listRoot
            }
        } detail: {
            if selectionModel.selectedItem == nil {
                SplitContentUnavailableView(module: module)
            } else {
                detail
                    .environment(selectionModel)
            }
        }
    }

    @ViewBuilder
    private var listRoot: some View {
        @Bindable var searchModel = searchModel
        list
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

