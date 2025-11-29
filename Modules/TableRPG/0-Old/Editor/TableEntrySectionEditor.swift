// @copyright André Trettin

import CoreRPG
import SwiftUI

struct TableEntrySectionEditor: View {
    let editController: EditController
    
    @Environment(TableRootModel.self) private var root
    @Environment(SelectionSheetLinkModel.self) private var selectionSheetLinkModel

    @State private var entrySectionEditorModel = EntrySectionEditorModel<TableModel>()

    var body: some View {
        @Bindable var model = editController.model

        EntrySectionEditor(editControllable: editController, entrySectionEditorModel: entrySectionEditorModel) {
            TableEntryEditContent(editController: editController, entrySectionEditorModel: entrySectionEditorModel)
        } contentView: {
            TableEntryEditRow(editController: editController, entrySectionEditorModel: entrySectionEditorModel)
        } showLinkView: {
            showLink()
        } swipeActionView: {
            TableEntrySwipeAction(editController: editController, entrySectionEditorModel: entrySectionEditorModel, actionType: .content)
        } menuView: {
            TableEntryMenuContext(editController: editController, entrySectionEditorModel: entrySectionEditorModel, menuType: .all)
        } linkActionView: {
            actionBarView()
        }
    }

    @ViewBuilder
    private func showLink() -> some View {
        @Bindable var entryModel = entrySectionEditorModel
        if let linkValue = entryModel.showLink {
            switch linkValue.type {
                case .dice:
                    editController.selectDice(for: linkValue.entryId, linkKeyPath: linkValue.keyPath ?? \.[linkValue.entryId].content) {
                        selectionSheetLinkModel.selection = false
                    }
                default:
                EmptyView()
//                    editController.selectTable(for: linkValue.entryId, linkKeyPath: linkValue.keyPath ?? \.[linkValue.entryId].content) {
//                        selectionSheetLinkModel.selection = false
//                    }
            }
        }
    }

    @ViewBuilder
    private func actionBarView() -> some View {
        AltOpenWindowButton(module: .dice)
        AltOpenWindowButton(module: .table)
    }
}

#Preview {
    TableEntrySectionEditor(editController: .preview)
        .environment(TableRootModel.preview)
}
