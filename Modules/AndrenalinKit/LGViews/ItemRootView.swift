// @copyright André Trettin

import CoreExternalRPG
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
    }
}

struct ItemRootSingleListView: View {
    let root: ItemRootController
    
    @Environment(\.navigator) private var navigator
    @Environment(\.appSizeMode) private var appSizeMode
    
    var body: some View {
        let _ = Self._printChanges()
        
        ItemRootListView(root: root)
            .onChange(of: listModel.selectedItemId) {
                guard appSizeMode == .compact, let itemId = listModel.selectedItemId else { return }
                navigator.navigate(to: root.folderListControllable.detailDestination(for: itemId))
            }
    }
    
    var listModel: FolderListModel {
        root.folderListControllable.listModel(for: nil)
    }
}

struct ItemRootListView: View {
    let root: ItemRootController
    
    var body: some View {
        let _ = Self._printChanges()
        
        ListRootView(root: root, parentModel: nil)
            .searchItemList(listControllable: root.folderListControllable, parentModel: nil)
            //.navigationDestinationAutoReceive(InternalRoute.self)
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
        
        if let itemId = listModel.selectedItemId {
            ManagedNavigationStack {
                root.folderListControllable.detailDestination(for: itemId).asAnyView()
                    .environment(root)
            }
        } else {
            SplitContentUnavailableView(module: root.module)
        }
    }
    
    var listModel: FolderListModel {
        root.folderListControllable.listModel
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
