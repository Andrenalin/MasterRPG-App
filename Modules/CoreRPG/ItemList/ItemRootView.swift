// @copyright André Trettin

import CoreExternalRPG
import SwiftData
import SwiftUI

public struct ItemRootView: View {
    public init(root: ItemRootController, withoutNavigation: Bool) {
        self.root = root
        self.withoutNavigation = withoutNavigation
    }
    
    let root: ItemRootController
    let withoutNavigation: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var cacheItemListModel = CacheItemListModel()
    
    public var body: some View {
        let _ = Self._printChanges()
        
        ItemRootSplitListView(root: root, withoutNavigation: withoutNavigation)
        .environment(cacheItemListModel)
        .environment(root.listDisplayModel)
        .environment(root.searchModel)
        .environment(root)
        .tabBarPlacementModifier(listControllable: root.listControllable)
        .tint(root.module.tint)
    }
}

struct ItemRootSplitListView: View {
    let root: ItemRootController
    let withoutNavigation: Bool
    
    @Environment(CacheItemListModel.self) private var cacheItemListModel
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    
    var body: some View {
        let _ = Self._printChanges()
        
#if os(iOS)
        Group {
            if withoutNavigation {
                ItemRootSingleListView(root: root, cacheItemListModel: cacheItemListModel)
            } else {
                if horizontalSizeClass == .compact {
                    ManagedNavigationStack(name: root.module.token) {
                        ItemRootSingleListView(root: root, cacheItemListModel: cacheItemListModel)
                    }
                } else {
                    ItemRootSplitView(root: root)
                }
            }
        }
#else
        ItemRootSplitView(root: root)
#endif
    }
}

struct ItemRootSingleListView: View {
    let root: ItemRootController
    let cacheItemListModel: CacheItemListModel
    
    @Environment(\.navigator) private var navigator
        
    var body: some View {
        let _ = Self._printChanges()
        
        ItemRootListView(root: root)
            .onChange(of: listModel.selectedItemId) {
                guard let itemId = listModel.selectedItemId else { return }
                navigator.navigate(to: root.listControllable.detailDestination(for: itemId))
            }
    }
    
    var listModel: ListModel {
        root.listControllable.listModel(for: nil)
    }
}

struct ItemRootSplitView: View {
    let root: ItemRootController
    
    @State private var column: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    
    var body: some View {
        let _ = Self._printChanges()
        
        NavigationSplitView(columnVisibility: $column, preferredCompactColumn: $preferredCompactColumn) {
            ManagedPresentationView {
                ItemRootListView(root: root)
            }
            .environment(root)
            .environment(root.listDisplayModel)
            .environment(root.searchModel)
        } detail: {
            ItemSplitDetailRootView(root: root)
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

struct ItemSplitDetailRootView: View {
    let root: ItemRootController
    
    var body: some View {
        let _ = Self._printChanges()
        let _ = print("*** ->", root.module)
        
        if let itemId = listModel.selectedItemId {
            ManagedPresentationView {
                root.listControllable.detailDestination(for: itemId).asAnyView()
                    .environment(root)
            }
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
//        ItemRootView(root: root.rootController, withoutNavigation: true)
//    }
//}
//
//#Preview("Split", traits: .mockData) {
//    @Previewable @Environment(FakeItemRootController.self) var root
//
//    ItemRootView(root: root.rootController, withoutNavigation: false)
//}
