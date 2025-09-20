// @copyright André Trettin

import CoreExternalRPG
import SwiftUI

public struct ItemListContextMenu: View {
    public init(controller: any ItemListContextMenuControllable, currentSelected: UUID? = nil) {
        self.controller = controller
        self.currentSelected = currentSelected
    }
    
    let controller: ItemListContextMenuControllable
    let currentSelected: UUID?

    @Environment(ItemRootController.self) private var root
    @Environment(\.navigator) private var navigator
    @Environment(ListDisplayModel.self) private var listDisplayModel
    
    public var body: some View {
        duplicateItemView
        moveItemView
            .disabled(listDisplayModel.isListMode)
        addItemView
            .disabled(listDisplayModel.isListMode)
        Divider()
        exportItemView
        generateLinkView
        Divider()
        deleteItemView
    }
}

private extension ItemListContextMenu {
    var title: String {
        controller.itemName(currentSelected: currentSelected)
    }

    var duplicateItemView: some View {
        Button {
            withAnimation { controller.duplicateItem(currentSelected: currentSelected) }
        } label: {
            Label {
                Text("Duplicate \(title)", bundle: .module)
            } icon: {
                Image(systemName: "doc.on.doc")
            }
        }
    }

    var deleteItemView: some View {
        Button(role: .destructive) {
            withAnimation {
                let removingItems = controller.deleteItem(currentSelected: currentSelected)
                guard !removingItems.isEmpty else { return }
                root.removeEntryListModel.removeItems = removingItems
                removingItems.forEach {
                    root.editControllable.markForDeletion(itemId: $0.itemId)
                }
            }
            navigator.navigate(to: InternalRoute.removeAlert, method: .managedSheet)
        } label: {
            Label {
                Text("Delete \(title)", bundle: .module)
            } icon: {
                Image(systemName: "trash")
            }
        }
    }

    var exportItemView: some View {
        Button {
            let route = controller.exportItem(currentSelected: currentSelected)
            navigator.navigate(to: route, method: .sheet)
        } label: {
            Label {
                Text("Export \(title)", bundle: .module)
            } icon: {
                Image(systemName: "square.and.arrow.up")
            }
        }
    }
    
    var generateLinkView: some View {
        Button {
            withAnimation { controller.generateLink(currentSelected: currentSelected) }
        } label: {
            Label {
                Text("Link for \(title)", bundle: .module)
            } icon: {
                Image(systemName: "link")
            }
        }
    }
    
    var moveItemView: some View {
        Menu {
            ForEach(controller.folderItems(currentSelected: currentSelected)) { folder in
                Button {
                    controller.moveItem(currentSelected: currentSelected, to: folder)
                } label: {
                    Label {
                        Text(folder.name)
                    } icon: {
                        Image(systemName: "folder")
                    }
                }
            }
        } label: {
            Label {
                Text("Move \(title) into", bundle: .module)
            } icon: {
                Image(systemName: "folder")
            }
        }
    }

    var addItemView: some View {
        Menu {
            ForEach(controller.collectionItems(currentSelected: currentSelected)) { folder in
                Button {
                    controller.addItem(currentSelected: currentSelected, to: folder)
                } label: {
                    Label {
                        Text(folder.name)
                    } icon: {
                        Image(systemName: controller.collectionIcon)
                    }
                }
            }
        } label: {
            Label {
                Text("Add \(title) into", bundle: .module)
            } icon: {
                Image(systemName: controller.collectionIcon)
            }
        }
    }
}
