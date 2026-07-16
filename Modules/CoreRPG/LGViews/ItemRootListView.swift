// @copyright André Trettin

import SwiftUI

struct ItemRootListView: View {
    let root: ItemRootController

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        ListRootView(root: root, listController: root.folderListControllable, parentModel: nil, isSubFolder: false)
            .searchItemList(listControllable: root.folderListControllable)
            .navigationAutoReceive(InternalRoute.self)
    }
}

#Preview("Item Root List") {
    ItemRootListView(root: ItemRootController.fake)
}
