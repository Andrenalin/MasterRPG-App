// @copyright André Trettin

import CoreRPG
#if !os(tvOS)
import GeneratorRPG
#endif

import SwiftUI

#if !os(tvOS)
struct TableExtractToolBarButton: View {
    let model: TableModel

    @Environment(\.navigator) private var navigator

    var body: some View {
        Button {
            navigator.navigate(to: TableDetailRoute.tableExtraction(model.id), method: .managedSheet)
        } label: {
            Label {
                Text("Extract Information", bundle: .module)
            } icon: {
                Image(systemName: NetworkModules.generator.icon)
            }
        }
        .disabled(model.entries.isEmpty)
    }
}
#endif

struct QuickEditorButton: View {
    let root: TableRootModel
    let model: TableModel

    @Environment(\.navigator) private var navigator
    
    var body: some View {
        Button {
            navigator.navigate(to: TableEditorRoute.quickEditor(model.id))
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
    let root: TableRootModel
    let model: TableModel

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

struct AddLinkButton: View {
    let root: TableRootModel
    let model: TableModel
    let module: NetworkModules
    
    @Environment(\.navigator) private var navigator
    

    var body: some View {
        Button {
            withAnimation {
                navigator.navigate(to: TableEditorRoute.addLink(ItemRowModel(itemId: model.id, typeId: module)))
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
