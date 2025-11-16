// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import RPGTables

struct GeneratorRoot: View {
    let generatorController: GeneratorController
    @Binding var item: ItemRowModel?

    @Environment(CharacterRootModel.self) private var root
    
    @State private var showInputField = false
    
    var body: some View {
        VStack {
            ViewThatFits {
                HStack {
                    cancelButtonView
                    Spacer()
                    resetButtonView
                    rollButtonView
                    saveButtonView
                }

                VStack(spacing: 20) {
                    HStack {
                        cancelButtonView
                        Spacer()
                        saveButtonView
                    }
                    HStack {
                        resetButtonView
                        Spacer()
                        rollButtonView
                    }
                }

            }
            .padding()

            ItemList(listController: generatorController.listController) { item, isSelected in
                if item.model.typeId == .table {
                    root.tableRoot.viewController.generatorRow(controllable: generatorController.tableGeneratorControllable(for: ItemRowModel(itemId: item.model.itemId, typeId: item.model.typeId)), item: item)
                } else {
                    ValueRowModel(item: item, model: model(item: item), isSelected: isSelected, hasQuickEditor: false, cacheItemListModel: CacheItemListModel())
                        .environment(\.showGame, false)
                        .environment(\.itemListToggleAction, .empty)
                }
            }
            .itemSplitViewSizeMode(.small)
            .itemListChildrenConfiguration(canNavigate: false)
            .environment(generatorController.listController.model)
        }
        .overlay(alignment: .top) {
            if showInputField {
                GeneratorEditor(generatorController: generatorController) {
                    showInputField = false

                    if $0 {
                        withAnimation { item = nil }
                    }
                }
                .transition(.move(edge: .top))
            }
        }
        .animation(.spring(), value: showInputField)
    }
    
    func model(item: ItemRowTreeModel) -> ValueModel {
        generatorController.genDataModel.itemData[item.model.itemId] as? ValueModel ?? .empty
    }

    var cancelButtonView: some View {
        Button {
            withAnimation { item = nil }
        } label: {
            Label { Text("Cancel", bundle: .module) } icon: { Image(systemName: "xmark.circle") }
        }
    }

    var resetButtonView: some View {
        Button {
            withAnimation { generatorController.reset() }
        } label: {
            Label { Text("Delete", bundle: .module) } icon: { Image(systemName: "trash.circle") }
        }
    }

    var rollButtonView: some View {
        Button {
            withAnimation { let _ = generatorController.roleResults() }
        } label: {
            Label { Text("Roll", bundle: .module) } icon: { Image(systemName: NetworkModules.dice.icon) }
        }
    }

    var saveButtonView: some View {
        Button {
            if generatorController.genDataModel.saveId == nil {
                withAnimation { showInputField.toggle() }
            } else {
                Task {
                    await generatorController.createValue(name: "")
                    item = nil
                }
            }
        } label: {
            Label { Text("Save", bundle: .module) } icon: { Image(systemName: "gear") }
        }
        .disabled(generatorController.genDataModel.selectedEntries.isEmpty)
    }
}
