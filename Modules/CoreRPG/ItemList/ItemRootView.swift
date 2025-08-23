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

    @Environment(DeviceRotationModel.self) private var deviceRotationModel

    @State private var column: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    @State private var cacheItemListModel = CacheItemListModel()

    public var body: some View {
        let _ = Self._printChanges()
        
        rootView
            .environment(cacheItemListModel)
            .environment(root.listDisplayModel)
            .environment(root.searchModel)
            .environment(root)
            .tabBarPlacementModifier(listControllable: root.listControllable)
    }
}

private extension ItemRootView {
    @ViewBuilder var rootView: some View {
#if os(iOS)
        Group {
            if withoutNavigation {
                listRoot
                    .navigationDestination(for: ItemRootRoute.self) { route in
                        route
                            .environment(cacheItemListModel)
                            .environment(deviceRotationModel)
                            .environment(root)
                            .environment(root.listDisplayModel)
                            .environment(root.searchModel)
                    }
                    .onAppear {
                        listModel.resetListSelection()
                        listModel.update(selection: Set())
                    }
            } else {
                splitRoot
            }
        }
#else
        splitRoot
#endif
    }

    @ViewBuilder var splitRoot: some View {
        NavigationSplitView(columnVisibility: $column, preferredCompactColumn: $preferredCompactColumn) {
            ManagedPresentationView {
                listRoot
            }
        } detail: {
            ItemSplitDetailRootView(root: root)
        }
    }

    @ViewBuilder var listRoot: some View {
        ListRootView(root: root, parentModel: nil)
            .searchItemList(listControllable: root.listControllable)
    }

    var listModel: ListModel {
        root.listControllable.listModel
    }
}

struct ItemSplitDetailRootView: View {
    let root: ItemRootController
    
    var body: some View {
        let _ = Self._printChanges()
        
        if let selected = listModel.selectedItemId {
            ManagedNavigationStack {
                ItemRootRoute.detail(selected)
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
//        ItemRootView(root: root, withoutNavigation: true, displayMode: .constant(.regular), listMode: .constant(.list), route: .constant(.detail(UUID())))
//    }
//}
//
//#Preview("Split", traits: .mockData) {
//    @Previewable @Environment(FakeItemRootController.self) var root
//    
//    ItemRootView(root: root, withoutNavigation: false, displayMode: .constant(.regular), listMode: .constant(.list), route: .constant(.detail(UUID())))
//}
