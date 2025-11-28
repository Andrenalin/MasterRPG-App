// @copyright André Trettin

import AndrenalinKit
import CharacterRPG
import DiceRPG
import TableRPG
import SwiftUI

struct LinkRootView: View {
    let type: LinkRootType

    @Environment(MapRootModel.self) private var root
    
    @State private var selection: NetworkModules = .map

    var body: some View {
        if type == .selection {
            LinkItemRootView(root: root.rootController, type: type)
        } else {
            allModuleLinks
        }
    }
    
    var allModuleLinks: some View {
        VStack {
            Picker(selection: $selection) {
                buttonPicker(module: .map)
                buttonPicker(module: .value)
                buttonPicker(module: .table)
                buttonPicker(module: .dice)
            } label: {
                Text("Module selection", bundle: .module)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            ZStack {
                switch selection {
                case .dice:
                    root.diceRoot.viewController.linkWindow(root: root.diceRoot, isInspector: type == .inspector)
                case .table:
                    root.tableRoot.viewController.linkWindow(root: root.tableRoot, isInspector: type == .inspector)
                case .value:
                    root.valueRoot.viewController.linkWindow(isInspector: type == .inspector)
                default:
                    LinkItemRootView(root: root.rootController, type: type)
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
    LinkRootView(type: .window)
}
