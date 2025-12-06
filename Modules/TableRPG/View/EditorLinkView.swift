// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI

struct EditorLinkView: View {
    @Environment(TableRootModel.self) private var root
    
    @State private var selection: NetworkModules = .table
    @State private var diceSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false)
    @State private var tableSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true)

    var body: some View {
        VStack {
            Picker(selection: $selection) {
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
                default:
                    root.viewController.linkListView(type: .inspector, itemSelectionModel: tableSelectionModel)
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
