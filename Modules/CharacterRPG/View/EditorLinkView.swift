// @copyright André Trettin

import CoreRPG
import DiceRPG
import TableRPG
import SwiftUI
import PdfRPG

struct EditorLinkView: View {
    @Environment(CharacterRootModel.self) private var root
    
    @State private var selection: NetworkModules = .value
    @State private var characterSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true)
    @State private var diceSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false)
    @State private var pdfSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false)
    @State private var tableSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true)
    
    var body: some View {
        ManagedNavigationStack(name: "CharacterEditorLink") {
            VStack {
                pickerRow(modules: firstRow)
                
                ZStack {
                    root.diceRoot.viewController.linkListView(type: .inspector, itemSelectionModel: diceSelectionModel)
                        .opacity(selection == .dice ? 1 : 0)
                    
                    root.pdfRoot.viewController.linkListView(type: .inspector, itemSelectionModel: pdfSelectionModel)
                        .opacity(selection == .pdf ? 1 : 0)
                    
                    root.tableRoot.viewController.linkListView(type: .inspector, itemSelectionModel: tableSelectionModel)
                        .opacity(selection == .table ? 1 : 0)
                    
                    root.viewController.linkListView(type: .inspector, itemSelectionModel: characterSelectionModel)
                        .opacity(selection == .value ? 1 : 0)
                }
            }
        }
    }
    
    var firstRow: [NetworkModules] {
        [.value, .table, .dice, .pdf]
    }
    
    func pickerRow(modules: [NetworkModules]) -> some View {
        Picker(selection: $selection) {
            ForEach(modules, id: \.self) { module in
                buttonPicker(module: module)
            }
        } label: {
            Text("Module selection", bundle: .module)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }
    
    func buttonPicker(module: NetworkModules) -> some View {
        Image(systemName: module.icon)
            .tag(module)
    }
}

#Preview(traits: .mockData) {
    EditorLinkView()
}
