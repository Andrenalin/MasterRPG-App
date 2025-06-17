// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct ValueEntrySectionEditor: View {
    let editController: EditController
    let changeChildModel: ChangeChildModel
    let changeGeneratorModel: ChangeGeneratorModel

    @Environment(ValueRoot.self) private var root
    @Environment(SelectionSheetLinkModel.self) private var selectionSheetLinkModel
    @Environment(\.dismiss) private var dismiss

    @State private var entrySectionEditorModel = EntrySectionEditorModel<ValueModel>()

    var body: some View {
        let _ = Self._printChanges()
        @Bindable var model = editController.model

        EntrySectionEditor(editControllable: editController, entrySectionEditorModel: entrySectionEditorModel) { entryId in
            editContent(entryId: entryId)
        } contentView: { entryId in
            EntryRow(linkController: root.linkController, model: editController.model, item: ItemRowTreeModel(id: UUID(), model: ItemRowModel(itemId: editController.model.id, entryId: entryId, typeId: root.itemController.itemDataModel.networkModule)), isEditing: true, hasQuickEditor: false, cacheItemListModel: editController.cacheItemListModel)
        } showLinkView: {
            showLink()
        } swipeActionView: { entryId in
            swipeButtons(for: entryId, keypath: \.[entryId].value)
        } menuView: { entryId, selection in
            contextMenu(for: entryId, selection: selection, keyPath: nil)
        } linkActionView: { entryId in
            actionBarView(selection: entryId)
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
    private func editContent(entryId: UUID) -> some View {
        @Bindable var model = editController.model
        Group {
            TextFieldControllerEditor(editController: editController, linkReplaceController: editController.nameEditLink(for: entryId), title: "Name", prompt: "Enter a name for the entry", bundle: .module)
                .id(entryId)
                .contextMenu {
                    contextMenu(for: entryId, selection: [], keyPath: \.[entryId].name)
                }
#if !os(tvOS)
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    swipeButtons(for: entryId, keypath: \.[entryId].name)
                }
#endif

            ValueTypeEditor(editController: editController, model: model, entryId: entryId)
                .id(entryId)

            Group {
                if model[entryId].type == .selection {
                    ToggleEditor(editController: editController, model: $model[entryId].isSelectedToggle, canToggle: model[entryId].canSelection, title: "Selection", bundle: .module, icon: "checkmark")
                        .id(entryId)
                } else {
                    TextFieldControllerEditor(editController: editController, linkReplaceController: editController.contentEditLink(for: entryId), title: "Value", prompt: "Enter a value for the entry", bundle: .module)
                        .id(entryId)
                        .contextMenu {
                            contextMenu(for: entryId, selection: [], keyPath: \.[entryId].value)
                        }
#if !os(tvOS)
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            swipeButtons(for: entryId, keypath: \.[entryId].value)
                        }
#endif
                }
            }
            .transition(.move(edge: .leading))
            .animation(.bouncy, value: model[entryId].type)

//            ToggleEditor(editController: editController, model: $model[entryId].isGeneratorToggle, canToggle: model[entryId].canGenerator, title: "Generator", bundle: .module, icon: "gear")

            diceRowEditor(for: model, entryId: entryId)
                .id(entryId)

            valueRowEditor(for: model, entryId: entryId)
                .id(entryId)
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
    private func swipeButtons(for entryId: UUID, keypath: WritableKeyPath<ValueModel, String>) -> some View {
        @Bindable var entryModel = entrySectionEditorModel
        LinkSelectionButton(entryId: entryId, type: .dice, keyPath: keypath, title: "Dice", bundle: .module, showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .pdf, keyPath: keypath, title: "Pdf", bundle: .module,showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .table, keyPath: keypath, title: "Table", bundle: .module,showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .value, keyPath: keypath, title: "Value", bundle: .module,showLink: $entryModel.showLink)
    }

    @ViewBuilder
    private func contextMenu(for entryId: UUID?, selection: [UUID], keyPath: WritableKeyPath<ValueModel, String>?) -> some View {
        @Bindable var entryModel = entrySectionEditorModel
        if let entryId {
            LinkSelectionButton(entryId: entryId, type: .dice, keyPath: keyPath, title: "Add Dice", bundle: .module, showLink: $entryModel.showLink)

            LinkSelectionButton(entryId: entryId, type: .pdf, keyPath: keyPath, title: "Add Pdf", bundle: .module, showLink: $entryModel.showLink)

            LinkSelectionButton(entryId: entryId, type: .table, keyPath: keyPath, title: "Add Table", bundle: .module, showLink: $entryModel.showLink)

            LinkSelectionButton(entryId: entryId, type: .value, keyPath: keyPath, title: "Add Value", bundle: .module, showLink: $entryModel.showLink)
        } else if !selection.isEmpty {
            Button {
                let rootModel = selection.first.map { ItemRowModel(itemId: editController.model.id, entryId: $0, typeId: .value) }
                guard let rootModel else { return }
                Task {
                    await editController.toggleGroup(for: rootModel, models: selection.dropFirst().map { ItemRowModel(itemId: editController.model.id, entryId: $0, typeId: .value) })
                }
            } label: {
                Label(editController.groupTitle(for: selection.dropFirst().map { ItemRowModel(itemId: editController.model.id, entryId: $0, typeId: .value)}, rootModel: selection.first.map { ItemRowModel(itemId: editController.model.id, entryId: $0, typeId: .value)}), systemImage: "square.on.square.squareshape.controlhandles")
            }
        }
    }

    @ViewBuilder
    private func actionBarView(selection: UUID?) -> some View {
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

    private func diceRowEditor(for model: ValueModel, entryId: UUID) -> some View {
        HStack {
            Label { Text("Dice", bundle: .module) } icon: { Image(systemName: NetworkModules.dice.icon) }

            if model[entryId].diceId != nil {
                EntryListDiceRow(itemId: model.id, entryId: entryId)
                    .removeItemImage(isLeading: true) {
                        editController.removeDice(from: entryId)
                    }
            }

            Spacer()

            Button {
                entrySectionEditorModel.showLink = ShowLinkEntryAction(id: UUID(), entryId: entryId, type: .dice, keyPath: nil)
            } label: {
                Text(model[entryId].diceId == nil ? "Add" : "Change", bundle: .module)
            }
        }
    }

    private func valueGroupTitle(entryId: UUID) -> String {
        guard let valueId =  editController.model[entryId].valueId else { return "" }
        return root.itemController.itemOrEmpty(for: valueId).name
    }

    private func valueRowEditor(for model: ValueModel, entryId: UUID) -> some View {
        HStack {
            Label { Text("Group", bundle: .module) } icon: { Image(systemName: NetworkModules.value.icon) }

            if let childId = model[entryId].valueId {
                Text(valueGroupTitle(entryId: entryId))
                    .removeItemImage(isLeading: true) {
                        editController.removeChild(childId: childId)
                    }
            }

            Spacer()

            Button {
                entrySectionEditorModel.showLink = ShowLinkEntryAction(id: UUID(), entryId: entryId, type: .value, keyPath: nil)
            } label: {
                Text(model[entryId].valueId == nil ? "Add" : "Change", bundle: .module)
            }
        }
    }
}

#Preview {
    ValueEntrySectionEditor(editController: .preview, changeChildModel: ChangeChildModel(), changeGeneratorModel: ChangeGeneratorModel())
        .environment(ValueRoot.preview)
        .environment(ListModel.preview)
        .environment(SelectionSheetLinkModel())
        .environment(\.locale, .init(identifier: "de"))
}
