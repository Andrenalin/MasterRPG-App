import AndrenalinKit
import SwiftUI
import SwiftData
import RPGPhotos

enum RootRoute: Equatable, CaseIterable {
    case photo
    case adventure
    case character
    case pdf
    case settings
    
    var title: String {
        switch self {
        case .adventure:
            return "Adventure"
        case .character:
            return "Character"
        case .photo:
            return "Photo"
        case .pdf:
            return "PDF"
        case .settings:
            return "Settings"
        }
    }
    
    var icon: String {
        switch self {
        case .adventure: "wand.and.stars"
        case .character: "person.fill"
        case .photo: "photo"
        case .pdf: "doc.fill"
        case .settings: "gear"
        }
    }
}

extension RootRoute: @MainActor NavigationDestination {
    var body: some View {
        if self == .photo {
            PhotoRootView()
        } else {
            RootListView(rootRoute: self)
        }
    }
}

struct AppRootView: View {
    
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    
    @Environment(ListModel.self) private var listModel
    @Environment(AppRootModel.self) private var appRootModel
    
    @State private var selectedTab: RootRoute = .photo
    @State private var column: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    @State private var searchText: String = ""
    
    @State private var category: ItemListCategory = .adventure
    
    var body: some View {
        @Bindable var listModel = listModel
        TabView(selection: $selectedTab) {
            ForEach(RootRoute.allCases) { tab in
                if tab == .settings {
                    Tab(title(for: tab), systemImage: tab.icon, value: tab, role: .search) {
                      tab
                    }
                } else {
                    Tab(title(for: tab), systemImage: tab.icon, value: tab) {
                        tab
                    }
                }
            }
        }
        #if !os(macOS)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            if selectedTab == .photo {
                Picker(selection: $category) {
                    ForEach(appRootModel.listModel.categoryTags) { category in
                        Text(category.localizedTitle)
                            .tag(category)
                    }
                } label: {
                 Text("Selected Cataegory")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                //.glassEffect(.regular.interactive())
            }
        }
        #endif
        #if os(macOS)
        .tabViewStyle(.tabBarOnly)
        #else
        .tabViewStyle(.sidebarAdaptable)
        #endif
    }
    
    func title(for tab: RootRoute) -> String {
        #if os(iOS)
        horizontalSizeClass == .compact ? tab.title : ""
        #else
        tab.title
        #endif
    }
}

@Observable
final class ListSelectionModel {
    var selectedItem: PhotoDataModel?
}

struct RootListView: View {
    let rootRoute: RootRoute
    
    @State private var selectionModel = ListSelectionModel()
    
    @State private var column: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    
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
    }
}

struct ListView: View {
    let rootRoute: RootRoute
    
    @Environment(\.modelContext) private var modelContext
    @Environment(ListSelectionModel.self) private var model
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
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
#endif
                ToolbarItem {
                    Button(action: addItem) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
    }
        private func addItem() {
            withAnimation {
                let newItem = PhotoDataModel(name: "Hello", information: "Mega view Text here")
                modelContext.insert(newItem)
            }
        }

        private func deleteItems(offsets: IndexSet) {
            withAnimation {
                for index in offsets {
                    modelContext.delete(items[index])
                }
            }
        }

}

struct RowView: View {
    let item: PhotoDataModel
    var body: some View {
        VStack(alignment: .leading) {
            Text(item.name)
            Text(item.information).foregroundStyle(.secondary)
            Text(item.category.localizedTitle)
            
            Text(item.nameLLW)
                .foregroundStyle(.secondary)
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
                    //.flexibleHeaderContent()

                RowView(item: item)
                
                TextField(text: $name) {
                    Text("Name:")
                }
                .onSubmit {
                    if item.name != name {
                        withAnimation { item.reset(name: name) }
                    }
                }
                .onAppear {
                    name = item.name
                }
            }
        }
        //.flexibleHeaderScrollView()
        .ignoresSafeArea(.keyboard)
        .ignoresSafeArea(edges: .top)
        .toolbar(removing: .title)
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
        .environment(AppRootModel())
        .environment(AppRootModel().listModel)
        .environment(AppRootModel().deviceRotationModel)
}


@Observable final class AppRootModel {
    var windowSize: CGSize = CGSize(width: 300, height: 800)
    var deviceRotationModel = DeviceRotationModel()
    var listModel = ListModel(searchToken: .all, categoryTags: [.adventure, .character, .photo, .weather], listStoreName: "Photo", hasChildren: false)
    var cacheModel = CacheItemListModel()
}

@Observable private class FlexibleHeaderGeometry {
    var offset: CGFloat = 0
}

/// A view modifer that stretches content when the containing geometry offset changes.
private struct FlexibleHeaderContentModifier: ViewModifier {
    @Environment(AppRootModel.self) private var modelData
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

extension View {
    func stretchy() -> some View {
        visualEffect { effect, geometry in
            let currentHeight = geometry.size.height
            let scrollOffset = geometry.frame(in: .scrollView).minY
            let positiveOffset = max(0, scrollOffset)
            
            let newHeight = currentHeight + positiveOffset
            let scaleFactor = newHeight / currentHeight
            
            return effect.scaleEffect(
                x: scaleFactor, y: scaleFactor,
                anchor: .bottom
            )
        }
    }
}
