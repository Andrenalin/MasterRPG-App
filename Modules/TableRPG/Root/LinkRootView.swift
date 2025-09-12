// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI
import DiceRPG

struct LinkRootView: View {
    let type: LinkRootType

    @Environment(TableRootModel.self) private var root
    
    @State private var selection: NetworkModules = .table
    
    var body: some View {
        if type == .selection {
            CoreRPG.LinkRootView(root: root, type: type)
        } else {
            allModuleLinks
        }
    }
    
    var allModuleLinks: some View {
        VStack {
            Picker(selection: $selection) {
                buttonPicker(module: .table)
                
                buttonPicker(module: .dice)
            } label: {
                Text("Module selection")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            ZStack {
                switch selection {
                case .dice:
                    root.diceRoot.viewController.linkWindow(root: root.diceRoot, isInspector: type == .inspector)
                default:
                    CoreRPG.LinkRootView(root: root, type: type)
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
