// @copyright André Trettin

#if !os(tvOS)

import AndrenalinKit
import SwiftUI
import DiceRPG
import PdfRPG
import TableRPG

struct ValueEntryEditor: View {
    let root: CharacterRootModel
    let editController: EditController
    let changeChildModel: ChangeChildModel
    
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let _ = Self._printChanges()
        EntryEditor(editControllable: editController) {
            contentView
        } linkActionView: {
            linkActionView
        } addActionView: {
            addEntryFromTemplateView
        }
        .modifier(ChangeChildEditorViewModifier(editController: editController, model: changeChildModel))
    }
    
    @ViewBuilder
    var linkActionView: some View {
        AltOpenWindowButton(module: .dice)
        AltOpenWindowButton(module: .pdf)
        AltOpenWindowButton(module: .table)
        AltOpenWindowButton(module: .value)
    }
    
    @ViewBuilder
    func contextMenuView(entryId: UUID) -> some View {
        ContextMenuEntryEditor(editControllable: editController, entryId: entryId) {
            Divider()

            if editController.editorModel.selected.count > 0 {
                Button {
                    withAnimation { editController.createGroup(from: editController.editorModel.selection) }
                } label: {
                    Text("Create group from \(editController.editorModel.selection.count) entry", bundle: .module)
                }
            }
            
            Button {
                Task {
                    await editController.ungroup(from: editController.editorModel.selection.isEmpty ? [entryId] : editController.editorModel.selection)
                }
            } label: {
                if editController.editorModel.selection.count > 0 {
                    Text("Ungroup \(editController.editorModel.selection.count) entry if grouped", bundle: .module)
                } else {
                    Text("Ungroup row \(String(editController.model[entryId].name.prefix(16)))", bundle: .module)
                }
            }
            .disabled(editController.editorModel.selection.count == 0 && editController.model[entryId].valueId == nil)
        }
    }

    @ViewBuilder
    var contentView: some View {
        @Bindable var model = editController.model
        @Bindable var editorModel = editController.editorModel
        Table(model.entries, selection: $editorModel.selected) {
            TableColumn(Text("Name", bundle: .module)) { entry in
                DropItemArea {
                    ValueNameColumn(root: root, editController: editController, entryId: entry.id) {
                        contextMenuView(entryId: entry.id)
                    }
                } dropAction: { linkData in
                    drop(links: linkData, entryId: entry.id, keyPath: \.[entry.id].name, isName: true)
                }
                .id(entry.id)
            }
            .width(220)
            
            TableColumn(Text("Type", bundle: .module)) { entry in
                ValueTypeEditor(editController: editController, model: model, entryId: entry.id)
                    .labelsHidden()
                    .id(entry.id)
            }
            .width(90)

//            TableColumn(Text("Gen", bundle: .module)) { entry in
//                ToggleEditor(editController: editController, model: $model[entry.id].isGeneratorToggle, canToggle: model[entry.id].canGenerator, bundle: .module)
//                    .labelsHidden()
//                    .labelsHidden()
//            }
//            .width(42)
            
            TableColumn(Text("Value", bundle: .module)) { entry in
                DropItemArea {
                    ValueValueColumn(root: root, editController: editController, entryId: entry.id) {
                        contextMenuView(entryId: entry.id)
                    }
                } dropAction: { linkData in
                    drop(links: linkData, entryId: entry.id, keyPath: \.[entry.id].value, isName: false)
                }
                .id(entry.id)
            }
            .width(min: 32)
            
            TableColumn(Text("Dice", bundle: .module)) { entry in
                root.diceRoot.viewController.viewDiceDropDownMenu(root: root.diceRoot, editController: editController, model: $model[entry.id].diceId)
                    .id(entry.id)
            }
            .width(96)
        }
        .id(model.id)
    }
    
    func drop(links: [LinkData], entryId: UUID, keyPath: WritableKeyPath<ValueModel, String>, isName: Bool) -> Bool {
        var content = editController.model[keyPath: keyPath]
        var unsupportedLinks = 0
        links.forEach { link in
            switch link.module {
            case .dice:
                content = root.diceRoot.linkController.generateLinks(itemId: link.itemId, into: content)
            case .pdf:
                content = root.pdfRoot.linkController.generateLinks(itemId: link.itemId, into: content)
            case .table:
                content = root.tableRoot.linkController.generateLinks(itemId: link.itemId, entryId: link.entryId, into: content)
            case .value:
                if let entryId = link.entryId {
                    content = root.linkController.generateLinks(itemId: link.itemId, entryId: entryId, into: content)
                } else {
                    if editController.canAddChild(childId: link.itemId) {
                        editController.addChild(childId: link.itemId, into: entryId)
                    } else {
                        changeChildModel.childId = link.itemId
                        changeChildModel.entryId = entryId
                        withAnimation { changeChildModel.showChildLinkAlert.toggle() }
                    }
                }
            default:
                unsupportedLinks += 1
            }
        }
        withAnimation {
            if isName {
                editController.updateNameContent(content, for: entryId)
            } else {
                editController.updateValueContent(content, for: entryId)
            }
        }
        return unsupportedLinks > 0
    }

    var addEntryFromTemplateView: some View {
        DropItemArea {
            Text("Drop Template for Generation", bundle: .module)
        } dropAction: { links in
            guard let link = links.first else { return false }
            switch link.module {
                case .value:
                    root.resetGeneratorController(rootItem: ItemRowModel(itemId: link.itemId, typeId: .value), saveId: editController.model.id)
                    openWindow(id: WindowIdentifier.generatorValueEditor.rawValue)
                default:
                    break
            }
            return true
        }
    }
}

#endif
