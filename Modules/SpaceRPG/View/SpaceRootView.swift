// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

public struct SpaceRootView: View {
    public init(modelContext: ModelContext, withoutNavigation: Bool) {
        self.withoutNavigation = withoutNavigation
        self._rootModel = State(wrappedValue: SpaceRootModel(modelContext: modelContext))
    }
    let withoutNavigation: Bool

    @Environment(CacheItemListModel.self) private var cacheItemListModel
    @Environment(SearchModel.self) private var searchModel
    @Environment(TabTitleModel.self) private var tabTitleModel
    
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.tabBarPlacement) private var tabBarPlacement
#endif
    @State private var rootModel: SpaceRootModel

    @State private var selectionModel = ListSelectionModel<SpaceDataModel>()

    @State private var column: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    public var body: some View {
        Group {
            if withoutNavigation {
                listView
            } else {
                splitRoot
            }
        }
        .environment(rootModel)
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
                listView
            }
        } detail: {
            if let selected = selectionModel.selectedItem {
                DetailView(model: selected)
                    .environment(selectionModel)
            } else {
                SplitContentUnavailableView(module: .photo)
            }
        }
    }

    @ViewBuilder
    private var listView: some View {
        @Bindable var searchModel = searchModel
        ListView()
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

#Preview("Embed", traits: .mockData) {
    @Previewable @Query var models: [SpaceDataModel]
    @Previewable @Environment(\.modelContext) var modelContext
    
    ManagedNavigationStack {
        SpaceRootView(modelContext: modelContext, withoutNavigation: true)
            .environment(CacheItemListModel())
            .environment(SearchModel.preview)
            .environment(TabTitleModel())
            .environment(DeviceRotationModel())
    }
    .environment(SpaceRootModel(modelContext: modelContext))
}

#Preview("Split", traits: .mockData) {
    @Previewable @Query var models: [SpaceDataModel]
    @Previewable @Environment(\.modelContext) var modelContext

    SpaceRootView(modelContext: modelContext, withoutNavigation: false)
        .environment(CacheItemListModel())
        .environment(SearchModel.preview)
        .environment(TabTitleModel())
        .environment(DeviceRotationModel())
}

