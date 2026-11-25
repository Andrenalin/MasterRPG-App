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
                // Same look as the inspector row chevron (InspectorRowViewFolderChevronView):
                // a 44pt glass circle, so the target is easy to hit with a mouse on macOS.
                Image(systemName: item.isOpen ? "chevron.down" : "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(.tint)
                    .contentShape(.circle)
                    .frame(minWidth: 44, minHeight: 44)
#if !os(visionOS)
                    .glassEffect(.clear.interactive())
#endif
            }
            .borderLessTVButtonStyle()
            .padding(.trailing, 4)
            .accessibilityLabel(Text("Toggle Folder", bundle: .module))
            // VoiceOver reads whether the folder is open. See CODE_AUDIT_Folder §8.5.
            .accessibilityValue(item.isOpen ? Text("Expanded", bundle: .module) : Text("Collapsed", bundle: .module))
        }
    }
}

#Preview {
    let item = {
        let item = FolderListItemModel(
            id: .fixture1,
            source: ItemRowModel(itemId: .fixture2, typeId: .none),
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
