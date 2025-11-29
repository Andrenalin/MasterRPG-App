// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI

struct EditorLinkView: View {
    @Environment(TableRootModel.self) private var root
    
    @State private var selection: NetworkModules = .table

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
                    root.diceRoot.viewController.linkWindow(isInspector: true)
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
