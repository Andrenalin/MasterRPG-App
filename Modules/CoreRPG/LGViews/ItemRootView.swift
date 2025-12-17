// @copyright André Trettin

import SwiftUI

public struct ItemRootView: View {
    public init(root: ItemRootController) {
        self.root = root
    }
    
    let root: ItemRootController
    
    @Environment(\.colorScheme) private var colorScheme
    
    public var body: some View {
        let _ = Self._printChanges()
        
        ItemRootSingleListView(root: root)
            .environment(root.folderListControllable.cacheListItemModel)
            .environment(root.listDisplayModel)
            .environment(root.searchModel)
            .environment(root)
            .tabBarPlacementModifier(listControllable: root.folderListControllable)
            .tint(root.module.tint)
            .accentColor(root.module.tint)
    }
}

struct ItemRootSingleListView: View {
    let root: ItemRootController
    
    @Environment(\.navigator) private var navigator
    @Environment(\.appSizeMode) private var appSizeMode
    
    var body: some View {
        let _ = Self._printChanges()
        
        ItemRootListView(root: root)
            .onChange(of: listModel.selected) {
                if let itemId = listModel.selectedItemId {
                    root.editControllable.setCurrentItem(to: ItemRowTreeModel(itemId: itemId, typeId: root.module))
                }
            }
            .onChange(of: listModel.itemRoute) {
                guard appSizeMode == .compact, let itemId = listModel.itemRoute else { return }
                navigator.navigate(to: root.folderListControllable.detailDestination(for: itemId))
                listModel.itemRoute = nil
            }
    }
    
    var listModel: FolderListModel {
        root.folderListControllable.listModel
    }
}

struct ItemRootListView: View {
    let root: ItemRootController
    
    var body: some View {
        let _ = Self._printChanges()
        
        ListRootView(root: root, listController: root.folderListControllable, parentModel: nil)
            .searchItemList(listControllable: root.folderListControllable)
            .navigationAutoReceive(InternalRoute.self)
    }
}

public struct ItemSplitDetailRootView: View {
    public init(root: ItemRootController) {
        self.root = root
    }
    
    let root: ItemRootController
    
    public var body: some View {
        let _ = Self._printChanges()
        let _ = print("*** ->", root.module)
        
        ManagedNavigationStack(name: "Split-\(root.module.token)") {
            SplitContentDetailRootView(root: root, itemId: listModel.selectedItemId)
        }
        .environment(root)
        .tint(root.module.tint)
        .accentColor(root.module.tint)
    }
    
    var listModel: FolderListModel {
        root.folderListControllable.listModel
    }
}

struct SplitContentDetailRootView: View {
    let root: ItemRootController
    let itemId: UUID?
    
    var body: some View {
        let _ = Self._printChanges()
        
        if let itemId {
            root.folderListControllable.detailDestination(for: itemId).asAnyView()
        } else {
            SplitContentUnavailableView(module: root.module)
        }
    }
}

//#Preview("Small", traits: .mockData) {
//    @Previewable @Environment(FakeItemRootController.self) var root
//
//    ManagedNavigationStack {
//        ItemRootView(root: root.rootController)
//    }
//}
//
//#Preview("Split", traits: .mockData) {
//    @Previewable @Environment(FakeItemRootController.self) var root
//
//    ItemRootView(root: root.rootController)
//}
