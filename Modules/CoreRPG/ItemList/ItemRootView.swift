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
                        detail
                            .environment(cacheItemListModel)
                            .environment(deviceRotationModel)
                            .environment(root)
                            .environment(root.listDisplayModel)
                            .environment(root.searchModel)
                    }
                    .onAppear {
                        print("*** reset list state")
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
            ItemSplitDetailRootView(root: root) {
                detail
            }
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

struct ItemSplitDetailRootView<Detail: View>: View {
    let root: ItemRootController
    @ViewBuilder let detail: Detail
    
    var body: some View {
        let _ = Self._printChanges()
        
        if listModel.selectedItemId != nil {
            ManagedNavigationStack {
                detail
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
