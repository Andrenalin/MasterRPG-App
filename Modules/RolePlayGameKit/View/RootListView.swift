import CoreRPG
import PhotoRPG
import SwiftData
import SwiftUI

struct RootListView: View {
    let rootRoute: RootRoute
    
    @Environment(AppModel.self) private var appModel
    @Environment(TabTitleModel.self) private var tabTitleModel
#if os(iOS)
@Environment(\.horizontalSizeClass) private var horizontalSizeClass
@Environment(\.tabBarPlacement) private var tabBarPlacement
#endif

    @State private var selectionModel = ListSelectionModel<PhotoDataModel>()
    
    @State private var column: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    
    var body: some View {
        NavigationSplitView(columnVisibility: $column, preferredCompactColumn: $preferredCompactColumn) {
            ListView(rootRoute: rootRoute)
                .environment(selectionModel)
        } detail: {
            Group {
                if let selected = selectionModel.selectedItem {
                    DetailView(item: selected)
                } else {
                    ContentUnavailableView(rootRoute.title, image: rootRoute.icon)
                }
            }
            .frame(maxWidth: .infinity)
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
        .frame(minWidth: 250, idealWidth: 350, maxWidth: 450)
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
        .backgroundExtensionEffect()
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
