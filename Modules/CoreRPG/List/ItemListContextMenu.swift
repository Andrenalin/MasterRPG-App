// @copyright André Trettin

import SwiftUI

public protocol ItemListContextMenuControllable {
    var itemName: String { get }

    func copyItem()
    func deleteItem()
    func exportItem()
    func generateLink()
}

public struct ItemListContextMenu: View {
    public init(controller: any ItemListContextMenuControllable) {
        self.controller = controller
    }
    
    let controller: ItemListContextMenuControllable
    
    public var body: some View {
        copyItemView
        exportItemView
        generateLinkView
        deleteItemView
    }
}

private extension ItemListContextMenu {
    var copyItemView: some View {
        Button {
            withAnimation { controller.copyItem() }
        } label: {
            Label {
                Text("Copy \(controller.itemName)", bundle: .module)
            } icon: {
                Image(systemName: "doc.on.doc")
            }
        }
    }

    var deleteItemView: some View {
        Button(role: .destructive) {
            withAnimation { controller.deleteItem() }
        } label: {
            Label {
                Text("Delete \(controller.itemName)", bundle: .module)
            } icon: {
                Image(systemName: "trash")
            }
        }
    }

    var exportItemView: some View {
        Button {
            withAnimation { controller.exportItem() }
        } label: {
            Label {
                Text("Export \(controller.itemName)", bundle: .module)
            } icon: {
                Image(systemName: "square.and.arrow.up")
            }
        }
    }
    
    var generateLinkView: some View {
        Button {
            withAnimation { controller.generateLink() }
        } label: {
            Label {
                Text("Link for \(controller.itemName)", bundle: .module)
            } icon: {
                Image(systemName: "link")
            }
        }
    }


}
