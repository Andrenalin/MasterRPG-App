// @copyright André Trettin

import SwiftUI

struct SpecialCategoryFolderIndicator: View {
    let item: FolderListItemModel
    let listController: any FolderListControllable
    
    var body: some View {
        // Show chevron when: (a) item has unexplored children (canOpen), (b) item is open,
        // or (c) user explicitly closed it (wasExplicitlyClosed) so they can reopen it.
        // Without (c), closing a folder during search hid the chevron permanently (canOpen=false
        // because children were already in result.children, isOpen=false after close).
        if item.canOpen || item.isOpen || item.wasExplicitlyClosed {
            Button {
                listController.toggleFolder(item: item)
            } label: {
                Image(systemName: item.isOpen ? "chevron.down" : "chevron.right")
                    .imageScale(.small)
                    .padding(.trailing)
                    .foregroundStyle(item.isOpen ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
            .accessibilityLabel(Text("Toggle Folder", bundle: .module))
        }
    }
}

#Preview {
    let item = {
        let item = FolderListItemModel(
            id: .fixture1,
            source: ItemRowModel(itemId: .fixture2, typeId: .none),
            destination: nil,
            level: 0,
            isShown: false
        )
        item.canOpen = true
        return item
    }()
    SpecialCategoryFolderIndicator(
        item: item,
        listController: FakeFolderListController.fake
    )
    .padding()
}
