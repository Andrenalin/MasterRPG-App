// @copyright André Trettin

import CoreRPG
import SwiftUI

struct GeneratorRoot: View {
    let generatorController: GeneratorController
    @Binding var item: ItemRowModel?

    @State private var showInputField = false
    @State private var updateDiceResult = false

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

//            ItemList(listController: generatorController.listController) { item, isSelected in
//                TableRowModel(item: item, model: model(item: item), isSelected: isSelected, cacheItemListModel: CacheItemListModel())
//                    .environment(\.showGame, false)
//                    .environment(\.itemListToggleAction, .empty)
//            }
//            .itemSplitViewSizeMode(.small)
//            .itemListChildrenConfiguration(canNavigate: false)
//            .environment(generatorController.listController.model)
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
        .onChange(of: updateDiceResult, initial: true) {
            generatorController.updateDiceResult() {
                updateDiceResult.toggle()
            }
        }

    }
    
    func model(item: ItemRowTreeModel) -> TableModel {
        generatorController.genDataModel.itemData[item.model.itemId] as? TableModel ?? .empty
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
            withAnimation { showInputField.toggle() }
        } label: {
            Label { Text("Save", bundle: .module) } icon: { Image(systemName: "gear") }
        }
        .disabled(generatorController.genDataModel.selectedEntries.isEmpty)
    }
}

#Preview {
    GeneratorRoot(generatorController: .previewWithData, item: .constant(nil))
        .environment(TableRootModel.previewWithData)
}

