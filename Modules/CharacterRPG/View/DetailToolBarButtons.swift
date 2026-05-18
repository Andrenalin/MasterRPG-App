// @copyright André Trettin

import CoreRPG
import SwiftUI

struct QuickEditorButton: View {
    let root: CharacterRootModel
    let model: ValueModel
    
    @Environment(\.navigator) private var navigator
    
    var body: some View {
        Button {
            navigator.navigate(to: EditorRoute.quickEditor(model.id))
        } label: {
            Label {
                Text("Quick Editor", bundle: .module)
            } icon: {
                Image(systemName: "table.badge.more")
            }
        }
    }
}

struct AddEntryButton: View {
    let root: CharacterRootModel
    let model: ValueModel

    var body: some View {
        Button {
            withAnimation {
                root.editController.setCurrentItem(to: ItemRowTreeModel(itemId: model.id, typeId: root.config.module))
                let entryId = root.editController.addNewEntry(itemId: model.id)
                root.editController.sheetEditorModel.entryId = entryId
                Task {
                    try? await Task.sleep(for: .seconds(0.25))
                    root.editController.sheetEditorModel.scrollEntryId = entryId
                }
            }
        } label: {
            Label {
                Text("Add new Entry", bundle: .module)
            } icon: {
                Image(systemName: "note.text.badge.plus")
            }
        }
    }
}

struct AddGroupButton: View {
    let root: CharacterRootModel
    let model: ValueModel

    var body: some View {
        Button {
            root.editController.setCurrentItem(to: ItemRowTreeModel(itemId: model.id, typeId: root.config.module))
            let itemId = model.id
            Task {
                let entryId = await root.editController.addNewGroup(itemId: itemId)
                withAnimation {
                    root.editController.sheetEditorModel.entryId = entryId
                }
                try? await Task.sleep(for: .seconds(0.25))
                root.editController.sheetEditorModel.scrollEntryId = entryId
            }
        } label: {
            Label {
                Text("Add new Group", bundle: .module)
            } icon: {
                Image(systemName: "plus.square.fill.on.square.fill")
            }
        }
    }
}

struct AddLinkButton: View {
    let root: CharacterRootModel
    let model: ValueModel
    let module: NetworkModules
    
    @Environment(\.navigator) private var navigator
    

    var body: some View {
        Button {
            withAnimation {
                navigator.navigate(to: EditorRoute.addLink(ItemRowModel(itemId: model.id, typeId: module)))
            }
        } label: {
            Label {
                Text("Link", bundle: .module)
            } icon: {
                Image(systemName: module.icon)
            }
        }
    }
}
