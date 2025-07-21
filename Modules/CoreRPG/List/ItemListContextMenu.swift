// @copyright André Trettin

import CoreExternalRPG
import SwiftUI

@MainActor
public protocol ItemListContextMenuControllable {
    func itemName(currentSelected: UUID?) -> String

    func duplicateItem(currentSelected: UUID?)
    func deleteItem(currentSelected: UUID?)
    func exportItem(currentSelected: UUID?) -> any NavigationDestination
    func generateLink(currentSelected: UUID?)
}

public struct ItemListContextMenu: View {
    public init(controller: any ItemListContextMenuControllable, currentSelected: UUID? = nil) {
        self.controller = controller
        self.currentSelected = currentSelected
    }
    
    let controller: ItemListContextMenuControllable
    let currentSelected: UUID?

    @Environment(\.navigator) private var navigator
    
    public var body: some View {
        duplicateItemView
        exportItemView
        generateLinkView
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
            withAnimation { controller.deleteItem(currentSelected: currentSelected) }
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
}
