// @copyright André Trettin

import CoreExternalRPG
import SwiftUI

public protocol ItemListContextMenuControllable {
    var itemName: String { get }

    func duplicateItem()
    func deleteItem()
    func exportItem() -> any NavigationDestination
    func generateLink()
}

public struct ItemListContextMenu: View {
    public init(controller: any ItemListContextMenuControllable) {
        self.controller = controller
    }
    
    let controller: ItemListContextMenuControllable
    
    @Environment(\.navigator) private var navigator
    
    public var body: some View {
        duplicateItemView
        exportItemView
        generateLinkView
        deleteItemView
    }
}

private extension ItemListContextMenu {
    var duplicateItemView: some View {
        Button {
            withAnimation { controller.duplicateItem() }
        } label: {
            Label {
                Text("Duplicate \(controller.itemName)", bundle: .module)
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
            let route = controller.exportItem()
            navigator.navigate(to: route, method: .sheet)
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
