// @copyright André Trettin

import SwiftUI

public struct ItemRootView: View {
    public init(root: ItemRootController) {
        self.root = root
    }
    
    let root: ItemRootController
    
    @Environment(\.colorScheme) private var colorScheme
    
    public var body: some View {
        ItemRootListView(root: root)
            .environment(root.folderListControllable.cacheListItemModel)
            .environment(root.listDisplayModel)
            .environment(root.searchModel)
            .environment(root)
            .tint(root.configurable.module.tint)
            .accentColor(root.configurable.module.tint)
    }
}

struct ItemRootListView: View {
    let root: ItemRootController
    
    var body: some View {
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
        if let itemId {
            root.folderListControllable.detailDestination(for: itemId).asAnyView()
        } else {
            SplitContentUnavailableView(module: root.configurable.module)
        }
    }
}
