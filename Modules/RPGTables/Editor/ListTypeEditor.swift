// @copyright André Trettin

import AndrenalinKit
import RPGDie
import SwiftUI

struct ListTypeEditor: View {
    let editController: EditController
    
    @Environment(TableRoot.self) private var root
    @Environment(SelectionSheetLinkModel.self) private var selectionSheetLinkModel

    var body: some View {
        @Bindable var model = editController.model

        Group {
            Section {
                pickerView
            } header: {
#if os(macOS)
                Divider()
                    .padding(.top)
#endif
                Text("Table type", bundle: .module)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
            } footer: {
                Text("A table can be a List, Dice or All. A list table is a simple name / content table. The dice table uses the dice value as name and the content is the result of the dice roll. All tables are used for a generator to use all entries.", bundle: .module)
            }

            if editController.model.tableType == .dice {
                ItemSelectionEditor(editController: editController, model: $model.diceId, title: "Dice", bundle: .module, value: .dice, inline: false) { diceId in
                    root.viewController.rowDiceView(for: model.diceId, cacheItemListModel: editController.cacheItemListModel)
                } selectorView: {
                    root.diceRoot.viewController.viewSelect(root: root.diceRoot, filter: .table, selection: {
                        guard let diceId = model.diceId else { return [] }
                        return [ItemRowModel(itemId: diceId, typeId: .dice)]
                    }, toggleSelection: { selection, _ in
                        if model.diceId == selection.itemId {
                            model.diceId = nil
                        } else {
                            model.diceId = selection.itemId
                        }
                    }) {
                        selectionSheetLinkModel.selection = false
                    }
                } valueFactory: { id in
                    id
                }
            }
        }
        .animation(.bouncy, value: editController.model.tableType)
    }
}

// MARK: Table Type Picker

private extension ListTypeEditor {
    var tableTypeBinding: Binding<TableModel.TableType> {
        Binding {
            editController.model.tableType
        } set: { newValue in
            if newValue != editController.model.tableType {
                withAnimation { editController.model.tableType = newValue }
                editController.save(with: String(localized: "Change table type").localizedString)
            }
        }
    }

    var pickerView: some View {
        LabeledContent {
            Picker(selection: tableTypeBinding) {
                DiceListRow(name: "List", icon: iconName(for: TableModel.TableType.list))
                    .tag(TableModel.TableType.list)

                DiceListRow(name: "Dice", icon: iconName(for: TableModel.TableType.dice))
                    .tag(TableModel.TableType.dice)

                DiceListRow(name: "All", icon: iconName(for: TableModel.TableType.all))
                    .tag(TableModel.TableType.all)
            } label: {
                Text("Table Type", bundle: .module)
            }
            .labelsHidden()
            .pickerStyle(.automatic)
        } label: {
            Label { Text("Table Type", bundle: .module) } icon: { Image(systemName: iconName(for: editController.model.tableType)) }
        }
    }

    func iconName(for tableType: TableModel.TableType) -> String {
        switch tableType {
        case .list: "checklist"
        case .dice: "list.number"
        case .all: "checklist.checked"
        }
    }
}

#Preview {
    ListTypeEditor(editController: .preview)
        .environment(TableRoot.previewWithData)
}
