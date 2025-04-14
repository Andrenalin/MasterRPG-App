// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct TableEntrySectionEditor: View {
    let editController: EditController
    
    @Environment(TableRoot.self) private var root
    @Environment(SelectionSheetLinkModel.self) private var selectionSheetLinkModel

    var body: some View {
        @Bindable var model = editController.model

        EntrySectionEditor(editControllable: editController) { entryId, showLink in
            editContent(entryId: entryId, showLink: showLink)
        } contentView: { entryId, showLink in
            EntryRow(model: editController.model, item: ItemRowTreeModel(itemId: editController.model.id, entryId: entryId, typeId: root.itemController.itemDataModel.networkModule), isEditing: true, cacheItemListModel: editController.editorModel.cacheItemListModel)
        } showLinkView: { linkValue in
            showLink(linkValue: linkValue)
        } swipeActionView: { entryId, showLink in
            swipeButtons(for: entryId, keypath: \.[entryId].content, showLink: showLink)
        } menuView: { entryId, selection, showLink in
            contextMenu(for: entryId, selection: selection, showLink: showLink, keyPath: nil)
        } linkActionView: { entryId, showLink in
            actionBarView(selection: entryId, showLink: showLink)
        }
    }

    @ViewBuilder
    private func editContent(entryId: UUID, showLink: Binding<ShowLinkEntryAction<TableModel>?>) -> some View {
        @Bindable var model = editController.model
        Group {
            TextFieldEditor(editController: editController, model: $model[entryId].name, title: "Name", prompt: "Enter a name for the entry", bundle: .module)

            TextFieldControllerEditor(editController: editController, linkReplaceController: editController.contentEditLink(for: entryId), title: "Content", prompt: "Enter some content for the entry", bundle: .module)
                .contextMenu {
                    contextMenu(for: entryId, selection: [], showLink: showLink, keyPath: \.[entryId].content)
                }
#if !os(tvOS)
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    swipeButtons(for: entryId, keypath: \.[entryId].content, showLink: showLink)
                }
#endif
        }
    }

    @ViewBuilder
    private func showLink(linkValue: ShowLinkEntryAction<TableModel>) -> some View {
        switch linkValue.type {
            case .dice:
                editController.selectDice(for: linkValue.entryId, linkKeyPath: linkValue.keyPath ?? \.[linkValue.entryId].content) {
                    selectionSheetLinkModel.selection = false
                }
            default:
                editController.selectTable(for: linkValue.entryId, linkKeyPath: linkValue.keyPath ?? \.[linkValue.entryId].content) {
                    selectionSheetLinkModel.selection = false
                }
        }
    }

    @ViewBuilder
    private func swipeButtons(for entryId: UUID, keypath: WritableKeyPath<TableModel, String>, showLink: Binding<ShowLinkEntryAction<TableModel>?>) -> some View {
        LinkSelectionButton(entryId: entryId, type: .dice, keyPath: keypath, title: "Dice", bundle: .module, showLink: showLink)

        LinkSelectionButton(entryId: entryId, type: .table, keyPath: keypath, title: "Table", bundle: .module, showLink: showLink)
    }

    @ViewBuilder
    private func contextMenu(for entryId: UUID?, selection: [UUID], showLink: Binding<ShowLinkEntryAction<TableModel>?>, keyPath: WritableKeyPath<TableModel, String>?) -> some View {

        if let entryId, let keyPath {
            LinkSelectionButton(entryId: entryId, type: .dice, keyPath: keyPath, title: "Add Dice", bundle: .module, showLink: showLink)

            LinkSelectionButton(entryId: entryId, type: .table, keyPath: keyPath, title: "Add Table", bundle: .module, showLink: showLink)
        }
    }
    
    @ViewBuilder
    private func actionBarView(selection: UUID?, showLink: Binding<ShowLinkEntryAction<TableModel>?>) -> some View {
        AltOpenWindowButton(module: .dice)
        AltOpenWindowButton(module: .table)
    }
}

#Preview {
    TableEntrySectionEditor(editController: .preview)
        .environment(TableRoot.preview)
}
