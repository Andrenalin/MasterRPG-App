import CoreRPG
import CoreExternalRPG
import PhotoRPG
import SpaceRPG
import SwiftUI
import SwiftData


extension RootRoute: @retroactive View {}
extension RootRoute: @retroactive Identifiable {}
extension RootRoute: @MainActor @retroactive NavigationDestination {
    public var body: some View {
        RootRouteDestionationView(route: self)
    }
}

struct RootRouteDestionationView: View {
    let route: RootRoute
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        switch route {
        case .adventures:
            RootListView(rootRoute: route)
        case .audios:
            RootListView(rootRoute: route)
        case .dice:
            RootListView(rootRoute: route)
        case .editors:
            RootListView(rootRoute: route)
        case .game:
            RootListView(rootRoute: route)
        case .maps:
            RootListView(rootRoute: route)
        case .pdfs:
            RootListView(rootRoute: route)
        case .photos:
            PhotoRootView(modelContext: modelContext, withoutNavigation: false)
        case .settings:
            RootListView(rootRoute: route)
        case .space:
            SpaceRootView(modelContext: modelContext, withoutNavigation: false)
        case .tables:
            RootListView(rootRoute: route)
        case .values:
            RootListView(rootRoute: route)
        case .weathers:
            RootListView(rootRoute: route)
        @unknown default:
            fatalError()
        }
    }
}

struct AppRootView: View {
    @Environment(AppRootUiModel.self) private var appRootModel
    
    @State private var selectedTab: RootRoute = .photos
    @State private var tabTitleModel = TabTitleModel()

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(RootRoute.allTabs) { tab in
                if tab == .settings {
                    Tab(tabTitleModel.titles[tab, default: tab.title], systemImage: tab.icon, value: tab, role: .search) {
                        tab
                    }
                } else {
                    Tab(tabTitleModel.titles[tab, default: tab.title], systemImage: tab.icon, value: tab) {
                        tab
                    }
                }
            }
        }
        .environment(tabTitleModel)
        #if os(iOS)
        .tabBarMinimizeBehavior(.onScrollDown)
        #endif
        #if os(macOS)
        .tabViewStyle(.tabBarOnly)
        #else
        .tabViewStyle(.sidebarAdaptable)
        #endif
    }
}

struct RootListView: View {
    let rootRoute: RootRoute
    
    @State private var selectionModel = ListSelectionModel<PhotoDataModel>()
    
    @State private var column: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    
    @Environment(TabTitleModel.self) private var tabTitleModel
#if os(iOS)
@Environment(\.horizontalSizeClass) private var horizontalSizeClass
@Environment(\.tabBarPlacement) private var tabBarPlacement
#endif

    var body: some View {
        NavigationSplitView(columnVisibility: $column, preferredCompactColumn: $preferredCompactColumn) {
            ListView(rootRoute: rootRoute)
                .environment(selectionModel)
        } detail: {
            if let selected = selectionModel.selectedItem {
                DetailView(item: selected)
            } else {
                ContentUnavailableView(rootRoute.title, image: rootRoute.icon)
            }
        }
        .ignoresSafeArea(edges: .top)
#if os(iOS)
                .onChange(of: tabBarPlacement, initial: true) {
                    tabTitleModel.toggleTitles(horizontalSizeClass: horizontalSizeClass, tabBarPlacement: tabBarPlacement)
                }               
#endif
    }
}

struct ListView: View {
    let rootRoute: RootRoute
    
    @Environment(\.modelContext) private var modelContext
    @Environment(ListSelectionModel<PhotoDataModel>.self) private var model
    @Query private var items: [PhotoDataModel]

    @State private var selected: UUID?
    var body: some View {
        List(selection: $selected) {
            ForEach(items) { item in
                RowView(item: item)
            }
        }
        .onChange(of: selected) {
            model.selectedItem = items.first { $0.id == selected }
        }
        .navigationTitle(rootRoute.title)
#if os(macOS)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
#endif
    }
}

struct RowView: View {
    let item: PhotoDataModel
    var body: some View {
        VStack(alignment: .leading) {
            Text("Bla")
        }
    }
}


struct DetailView: View {
    @Environment(\.isSearching) private var isSearching
    
    let item: PhotoDataModel
    
    @State private var name = ""
    
    var body: some View {
        @Bindable var item = item
        
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 8) {

                ImageHeaderView()
                    .ignoresSafeArea(edges: .top)
                    .stretchy()

                RowView(item: item)
            }
        }
        .ignoresSafeArea(.keyboard)
        .ignoresSafeArea(edges: .top)
        #if !os(tvOS)
        .toolbar(removing: .title)
        #endif
    }
}

struct ImageHeaderView: View {
    var body: some View {
        Image(decorative: "1022")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .clipped()
            .backgroundExtensionEffect()
            .overlay(alignment: .bottom) {
                VStack {
                    Text("Featured Landmark", comment: "Big headline in the main image of featured landmarks.")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .opacity(0.8)
                    Text("Kirchenberg")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Button("Learn More") {
                        
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom, 6)
                }
                .padding([.bottom], 40)
            }
    }
}

#Preview {
    AppRootView()
        .modelContainer(for: [PhotoDataModel.self, PhotoEntryDataModel.self], inMemory: true)
        .environment(AppRootUiModel())
        .environment(SearchModel.preview)
        .environment(DeviceRotationModel())
        .environment(CacheItemListModel())
}

@Observable private class FlexibleHeaderGeometry {
    var offset: CGFloat = 0
}

/// A view modifer that stretches content when the containing geometry offset changes.
private struct FlexibleHeaderContentModifier: ViewModifier {
    @Environment(AppRootUiModel.self) private var modelData
    @Environment(FlexibleHeaderGeometry.self) private var geometry

    func body(content: Content) -> some View {
        let height = (modelData.windowSize.height / 2) - geometry.offset
        content
            .frame(height: height)
            .padding(.bottom, geometry.offset)
            .offset(y: geometry.offset)
    }
}

/// A view modifier that tracks scroll view geometry to stretch a view with ``FlexibleHeaderContentModifier``.
private struct FlexibleHeaderScrollViewModifier: ViewModifier {
    @State private var geometry = FlexibleHeaderGeometry()

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                min(geometry.contentOffset.y + geometry.contentInsets.top, 0)
            } action: { _, offset in
                geometry.offset = offset
            }
            .environment(geometry)
    }
}

// MARK: - View Extensions

extension ScrollView {
    /// A function that returns a view after it applies `FlexibleHeaderScrollViewModifier` to it.
    @MainActor func flexibleHeaderScrollView() -> some View {
        modifier(FlexibleHeaderScrollViewModifier())
    }
}

extension View {
    /// A function that returns a view after it applies `FlexibleHeaderContentModifier` to it.
    func flexibleHeaderContent() -> some View {
        modifier(FlexibleHeaderContentModifier())
    }
}
