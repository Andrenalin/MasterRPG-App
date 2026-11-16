// @copyright André Trettin

import SwiftUI

struct ItemRowsView: View {
    let root: any ItemRootControllable
    let listController: any FolderListControllable
    let parentModel: (any ItemDataAccessible)?
    let listModel: FolderListModel
    let menuController: ContextMenuMultiController
    var focusedRowId: FocusState<UUID?>.Binding

    var body: some View {
        if listModel.list.isEmpty && parentModel != nil {
            DropHereView(root: root, addLink: addLink)
        }

        ForEach(listModel.list) { item in
            VStack(spacing: 0) {
                ListRowItemView(
                    root: root,
                    item: item,
                    listController: listController,
                    parentModel: parentModel,
                    listModel: listModel,
                    menuController: menuController,
                    leadingPadding: leadingPadding,
                    focusedRowId: focusedRowId
                )
                .equatable()

                if item.isOpen {
                    Divider().padding(.leading, 8)
                }
            }
            .id(item.id)
        }
    }

    private func addLink(name: String, itemId: UUID, entryId: UUID?) {
        guard let parentModel else { return }
        addDroppedMember(itemId: itemId, to: parentModel.id, root: root, listController: listController)
    }
    
    private var leadingPadding: CGFloat {
        let value = listController.listDisplayModel.isSelectionMode ? 12 : 8
        return CGFloat(valueFor(iOS: value, macOS: 4, tvOS: value, visionOS: value))
    }
}

private struct DropHereView: View {
    @Environment(\.appTheme) private var theme

    let root: any ItemRootControllable
    let addLink: (String, UUID, UUID?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("Drop here", bundle: .module)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
                .background(
                    theme.background(for: root.configurable.module).gradient,
                    in: .capsule
                )
                .padding()
                .dropDestination(for: root.configurable.module, isEnabled: true, handler: addLink)

            Text("Drag items from the list or the inspector on this drop field to add the item to the folder or collection. After the first item is added you can add more items by dropping it on the exisiting items in this detail list.", bundle: .module)
                .padding()
                .lineLimit(5)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("Item Rows") {
    @Previewable @FocusState var focusedRowId: UUID?
    let fixture = FakeItemRootControllerFixture()
    ItemRowsView(
        root: fixture.root,
        listController: fixture.folderListController,
        parentModel: nil,
        listModel: fixture.folderListController.listModel,
        menuController: ContextMenuMultiController(
            editController: fixture.editController,
            itemController: fixture.itemController,
            listModel: fixture.folderListController.listModel
        ),
        focusedRowId: $focusedRowId
    )
}
