// @copyright André Trettin

import CoreRPG
import DiceRPG
import TableRPG
import SwiftUI

struct EditorLinkView: View {
    @Environment(CharacterRootModel.self) private var root
    
    @State private var selection: NetworkModules = .value

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
                    root.diceRoot.viewController.linkWindow(isInspector: true)
                case .table:
                    root.tableRoot.viewController.linkWindow(isInspector: true)
                default:
                    LinkItemRootView(root: root.rootController, type: .inspector)
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
