// @copyright André Trettin

import CoreExternalRPG
import SwiftData
import SwiftUI

public struct ItemRootView<Detail: View>: View {
    public init(root: ItemRootController, withoutNavigation: Bool, @ViewBuilder detail: () -> Detail) {
        self.root = root
        self.withoutNavigation = withoutNavigation
        self.detail = detail()
    }

    let root: ItemRootController
    let withoutNavigation: Bool
    let detail: Detail

    @State private var cacheItemListModel = CacheItemListModel()

    public var body: some View {
        let _ = Self._printChanges()
        
        ItemRootSplitListView(root: root, withoutNavigation: withoutNavigation) {
            detail
        }
            .environment(cacheItemListModel)
            .environment(root.listDisplayModel)
            .environment(root.searchModel)
            .environment(root)
            .tabBarPlacementModifier(listControllable: root.listControllable)
    }
}

struct ItemRootSplitListView<Detail: View>: View {
    let root: ItemRootController
    let withoutNavigation: Bool
    @ViewBuilder let detail: Detail
    
    @Environment(CacheItemListModel.self) private var cacheItemListModel
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
        
    var body: some View {
        let _ = Self._printChanges()
        
#if os(iOS)
        Group {
            if withoutNavigation {
                ItemRootSingleListView(root: root, cacheItemListModel: cacheItemListModel) {
                    detail
                }
            } else {
                if horizontalSizeClass == .compact {
                    ManagedNavigationStack {
                        ItemRootSingleListView(root: root, cacheItemListModel: cacheItemListModel) {
                            detail
                        }
                    }
                } else {
                    ItemRootSplitView(root: root) {
                        detail
                    }
                }
            }
        }
#else
        ItemRootSplitView(root: root) {
            detail
        }
#endif
    }
}

struct ItemRootSingleListView<Detail: View>: View {
    let root: ItemRootController
    let cacheItemListModel: CacheItemListModel
    @ViewBuilder let detail: Detail
    
    var body: some View {
        let _ = Self._printChanges()
        
        ItemRootListView(root: root)
            .navigationDestination(for: ItemRootRoute.self) { route in
                ItemDetailRooteNavigationView(root: root, route: route) {
                    detail
                }
                .environment(cacheItemListModel)
            }
            .onAppear {
                listModel.resetListSelection()
                listModel.update(selection: Set())
            }
    }
    
    var listModel: ListModel {
        root.listControllable.listModel(for: nil)
    }
}

struct ItemDetailRooteNavigationView<Detail: View>: View {
    let root: ItemRootController
    let route: ItemRootRoute
    @ViewBuilder let detail: Detail
    
    @Environment(DeviceRotationModel.self) private var deviceRotationModel

    var body: some View {
        let _ = Self._printChanges()

        detail
            .environment(deviceRotationModel)
            .environment(root)
            .environment(root.listDisplayModel)
            .environment(root.searchModel)
    }
}

struct ItemRootSplitView<Detail: View>: View {
    let root: ItemRootController
    @ViewBuilder let detail: Detail
    
    @State private var column: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    
    var body: some View {
        let _ = Self._printChanges()
        
        NavigationSplitView(columnVisibility: $column, preferredCompactColumn: $preferredCompactColumn) {
            ManagedPresentationView {
                ItemRootListView(root: root)
            }
        } detail: {
            ItemSplitDetailRootView(root: root) {
                detail
            }
        }
    }
}

struct ItemRootListView: View {
    let root: ItemRootController
    
    var body: some View {
        let _ = Self._printChanges()
        
        ListRootView(root: root, parentModel: nil)
            .searchItemList(listControllable: root.listControllable, parentModel: nil)
    }
}

struct ItemSplitDetailRootView<Detail: View>: View {
    let root: ItemRootController
    @ViewBuilder let detail: Detail
    
    var body: some View {
        let _ = Self._printChanges()
        
        if listModel.selectedItemId != nil {
            //ManagedNavigationStack {
                detail
                    .environment(root)
            //}
        } else {
            SplitContentUnavailableView(module: root.module)
        }
    }
    
    var listModel: ListModel {
        root.listControllable.listModel
    }
}

//#Preview("Small", traits: .mockData) {
//    @Previewable @Environment(FakeItemRootController.self) var root
//    
//    ManagedNavigationStack {
//        ItemRootView(root: root, withoutNavigation: true, displayMode: .constant(.regular), listMode: .constant(.list), route: .constant(.detail(UUID())))
//    }
//}
//
//#Preview("Split", traits: .mockData) {
//    @Previewable @Environment(FakeItemRootController.self) var root
//    
//    ItemRootView(root: root, withoutNavigation: false, displayMode: .constant(.regular), listMode: .constant(.list), route: .constant(.detail(UUID())))
//}
