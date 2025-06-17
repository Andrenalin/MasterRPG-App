// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct TableEntrySectionEditor: View {
    let editController: EditController
    
    @Environment(TableRoot.self) private var root
    @Environment(SelectionSheetLinkModel.self) private var selectionSheetLinkModel

    @State private var entrySectionEditorModel = EntrySectionEditorModel<TableModel>()

    var body: some View {
        @Bindable var model = editController.model

        EntrySectionEditor(editControllable: editController, entrySectionEditorModel: entrySectionEditorModel) { entryId in
            editContent(entryId: entryId)
        } contentView: { entryId in
            EntryRow(model: editController.model, item: ItemRowTreeModel(itemId: editController.model.id, entryId: entryId, typeId: root.itemController.itemDataModel.networkModule), isEditing: true, cacheItemListModel: editController.editorModel.cacheItemListModel)
        } showLinkView: {
            showLink()
        } swipeActionView: { entryId in
            swipeButtons(for: entryId, keypath: \.[entryId].content)
        } menuView: { entryId, selection in
            contextMenu(for: entryId, selection: selection, keyPath: nil)
        } linkActionView: { entryId in
            actionBarView(selection: entryId)
        }
    }

    @ViewBuilder
    private func editContent(entryId: UUID) -> some View {
        @Bindable var model = editController.model
        Group {
            TextFieldEditor(editController: editController, model: $model[entryId].name, title: "Name", prompt: "Enter a name for the entry", bundle: .module)

            TextFieldControllerEditor(editController: editController, linkReplaceController: editController.contentEditLink(for: entryId), title: "Content", prompt: "Enter some content for the entry", bundle: .module)
                .contextMenu {
                    contextMenu(for: entryId, selection: [], keyPath: \.[entryId].content)
                }
#if !os(tvOS)
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    swipeButtons(for: entryId, keypath: \.[entryId].content)
                }
#endif
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
                    editController.selectTable(for: linkValue.entryId, linkKeyPath: linkValue.keyPath ?? \.[linkValue.entryId].content) {
                        selectionSheetLinkModel.selection = false
                    }
            }
        }
    }

    @ViewBuilder
    private func swipeButtons(for entryId: UUID, keypath: WritableKeyPath<TableModel, String>) -> some View {
        @Bindable var entryModel = entrySectionEditorModel
            LinkSelectionButton(entryId: entryId, type: .dice, keyPath: keypath, title: "Dice", bundle: .module, showLink: $entryModel.showLink)

            LinkSelectionButton(entryId: entryId, type: .table, keyPath: keypath, title: "Table", bundle: .module, showLink: $entryModel.showLink)
    }

    @ViewBuilder
    private func contextMenu(for entryId: UUID?, selection: [UUID], keyPath: WritableKeyPath<TableModel, String>?) -> some View {
        @Bindable var entryModel = entrySectionEditorModel
        if let entryId, let keyPath {
            LinkSelectionButton(entryId: entryId, type: .dice, keyPath: keyPath, title: "Add Dice", bundle: .module, showLink: $entryModel.showLink)

            LinkSelectionButton(entryId: entryId, type: .table, keyPath: keyPath, title: "Add Table", bundle: .module, showLink: $entryModel.showLink)
        }
    }
    
    @ViewBuilder
    private func actionBarView(selection: UUID?) -> some View {
        AltOpenWindowButton(module: .dice)
        AltOpenWindowButton(module: .table)
    }
}

#Preview {
    TableEntrySectionEditor(editController: .preview)
        .environment(TableRoot.preview)
}
