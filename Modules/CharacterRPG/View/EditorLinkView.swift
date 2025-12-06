// @copyright André Trettin

import CoreRPG
import DiceRPG
import TableRPG
import SwiftUI

struct EditorLinkView: View {
    @Environment(CharacterRootModel.self) private var root
    
    @State private var selection: NetworkModules = .value
    @State private var characterSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true)
    @State private var diceSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false)
    @State private var tableSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true)

    var body: some View {
        VStack {
            Picker(selection: $selection) {
                buttonPicker(module: .value)
                buttonPicker(module: .dice)
                buttonPicker(module: .table)
            } label: {
                Text("Module selection", bundle: .module)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            ZStack {
                switch selection {
                case .dice:
                    root.diceRoot.viewController.linkListView(type: .inspector, itemSelectionModel: diceSelectionModel)
                case .table:
                    root.tableRoot.viewController.linkListView(type: .inspector, itemSelectionModel: tableSelectionModel)
                default:
                    root.viewController.linkListView(type: .inspector, itemSelectionModel: characterSelectionModel)
                }
            }
        }
    }
    
    func buttonPicker(module: NetworkModules) -> some View {
        Image(systemName: module.icon)
            .tag(module)
    }
}

#Preview(traits: .mockData) {
    EditorLinkView()
}
