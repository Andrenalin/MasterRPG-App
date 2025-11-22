// @copyright André Trettin

#if !os(tvOS)

import AndrenalinKit
import SwiftUI
import DiceRPG

struct TableEntryEditor: View {
    let root: TableRootModel
    let editController: EditController
    
    var body: some View {
        //let _ = Self._printChanges()
        
        EntryEditor(editControllable: editController) {
            contentView()
        } linkActionView: {
            linkActionView()
        }
    }
    
    @ViewBuilder
    func linkActionView() -> some View {
        AltOpenWindowButton(module: .dice)
        AltOpenWindowButton(module: .table)
    }
    
    @ViewBuilder
    func contextMenuView(entryId: UUID) -> some View {
        ContextMenuEntryEditor(editControllable: editController, entryId: entryId) {
            EmptyView()
        }
    }
    
    @ViewBuilder
    func contentView() -> some View {
        @Bindable var item = editController.model
        @Bindable var editorModel = editController.editorModel
        Table(item.entries, selection: $editorModel.selected) {
            TableColumn(Text("Name", bundle: .module)) { entry in
                TableNameColumn(root: root, editController: editController, entryId: entry.id) {
                    contextMenuView(entryId: entry.id)
                }
            }
            .width(220)
            
            TableColumn(Text("Content", bundle: .module)) { entry in
                DropItemArea {
                    TableContentColumn(root: root, editController: editController, entryId: entry.id) {
                        contextMenuView(entryId: entry.id)
                    }
                } dropAction: { linkData in
                    drop(links: linkData, entryId: entry.id)
                }
            }
            .width(min: 32)
        }
    }
    
    func drop(links: [LinkData], entryId: UUID) -> Bool {
        var content = editController.model[entryId].content
        var unsupportedLinks = 0
        links.forEach { link in
            switch link.module {
            case .dice:
                content = root.diceRoot.linkController.generateLinks(itemId: link.itemId, into: content)
            case .table:
                content = root.linkController.generateLinks(itemId: link.itemId, entryId: link.entryId, into: content)
            default:
                unsupportedLinks += 1
            }
        }
        withAnimation {
            editController.updateContent(content, for: entryId)
        }
        return unsupportedLinks == 0
    }
}

#endif
