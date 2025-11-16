// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct ValueEntrySectionEditor: View {
    let editController: EditController
    let changeChildModel: ChangeChildModel
    let changeGeneratorModel: ChangeGeneratorModel

    @Environment(CharacterRootModel.self) private var root
    @Environment(SelectionSheetLinkModel.self) private var selectionSheetLinkModel
    @Environment(\.dismiss) private var dismiss

    @State private var entrySectionEditorModel = EntrySectionEditorModel<ValueModel>()

    var body: some View {
        let _ = Self._printChanges()
        @Bindable var model = editController.model

        EntrySectionEditor(editControllable: editController, entrySectionEditorModel: entrySectionEditorModel) {
            ValueEntryEditContent(editController: editController, entrySectionEditorModel: entrySectionEditorModel)
        } contentView: {
            ValueEntryEditRow(editController: editController, entrySectionEditorModel: entrySectionEditorModel)
        } showLinkView: {
            showLink()
        } swipeActionView: {
            ValueEntrySwipeAction(editController: editController, entrySectionEditorModel: entrySectionEditorModel, actionType: .value)
        } menuView: {
            ValueEntryMenuContext(editController: editController, entrySectionEditorModel: entrySectionEditorModel, menuType: .all)
        } linkActionView: {
            actionBarView()
        } addActionView: {
            addEntryFromTemplateView()
        }
        .onChange(of: selectionSheetLinkModel.childId, initial: false) {
            guard let childId = selectionSheetLinkModel.childId else { return }
            selectionSheetLinkModel.childId = nil
            changeChildModel.entryId = selectionSheetLinkModel.entryId
            changeChildModel.childId = childId
            withAnimation { changeChildModel.showChildLinkAlert.toggle() }
        }
        .onChange(of: selectionSheetLinkModel.generatorId, initial: false) {
            guard let generatorId = selectionSheetLinkModel.generatorId else { return }
            selectionSheetLinkModel.generatorId = nil
            changeGeneratorModel.generatorId = generatorId
            withAnimation { changeGeneratorModel.showGenerator.toggle() }
        }
    }

    @ViewBuilder
    private func showLink() -> some View {
        @Bindable var entryModel = entrySectionEditorModel
        if let linkValue = entryModel.showLink {
            switch linkValue.type {
                case .dice:
                    editController.selectDice(for: linkValue.entryId, linkKeyPath: linkValue.keyPath) { selectionSheetLinkModel.selection = false }
                case .pdf:
                    editController.selectPdf(for: linkValue.entryId, linkKeyPath: linkValue.keyPath) { selectionSheetLinkModel.selection = false }
                case .table:
                    editController.selectTable(for: linkValue.entryId, linkKeyPath: linkValue.keyPath) { selectionSheetLinkModel.selection = false }
                case .editor:
                    editController.selectTemplate(selectionModel: selectionSheetLinkModel) { selectionSheetLinkModel.selection = false }
                default:
                    editController.selectValue(for: linkValue.entryId, linkKeyPath: linkValue.keyPath, selectionModel: selectionSheetLinkModel) { selectionSheetLinkModel.selection = false }
            }
        }
    }

    @ViewBuilder
    private func actionBarView() -> some View {
        LinkWindowButton(type: .dice)
        LinkWindowButton(type: .pdf)
        LinkWindowButton(type: .table)
        LinkWindowButton(type: .value)
    }

    private func addEntryFromTemplateView() -> some View {
        Button {
            withAnimation {
                entrySectionEditorModel.showLink = ShowLinkEntryAction(id: UUID(), entryId: UUID(), type: .editor, keyPath: nil)
            }
        } label: {
            Image(systemName: "gear")
        }
    }
}

#Preview {
    ValueEntrySectionEditor(editController: .preview, changeChildModel: ChangeChildModel(), changeGeneratorModel: ChangeGeneratorModel())
        .environment(CharacterRootModel.preview)
        .environment(ListModel.preview)
        .environment(SelectionSheetLinkModel())
        .environment(\.locale, .init(identifier: "de"))
}

