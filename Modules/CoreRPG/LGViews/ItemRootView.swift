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
            .tint(root.configurable.module.tint)
            .accentColor(root.configurable.module.tint)
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
                    root.editControllable.setCurrentItem(to: ItemRowTreeModel(itemId: itemId, typeId: root.configurable.module))
                }
            }
            .onChange(of: listModel.itemRoute) {
                guard let itemId = listModel.itemRoute else { return }
                listModel.itemRoute = nil
                guard appSizeMode == .compact else { return }
                navigator.navigate(to: root.folderListControllable.detailDestination(for: itemId))
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
        let _ = print("*** ->", root.configurable.module)
        
        ManagedNavigationStack(name: "Split-\(root.configurable.module.token)") {
            SplitContentDetailRootView(root: root, itemId: listModel.selectedItemId)
        }
        .environment(root)
        .tint(root.configurable.module.tint)
        .accentColor(root.configurable.module.tint)
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
            SplitContentUnavailableView(module: root.configurable.module)
        }
    }
}
