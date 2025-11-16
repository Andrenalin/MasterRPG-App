// @copyright André Trettin

import RPGDie
import RPGValues
import RPGTables
import RPGPhotos

import AndrenalinKit
import SwiftData
import SwiftUI

struct LinkRootView: View {
    let type: LinkRootType

    @Environment(GeneratorRootModel.self) private var root
    
    @State private var selection: NetworkModules = .value
    
    var body: some View {
        allModuleLinks
    }
    
    var allModuleLinks: some View {
        VStack {
            Picker(selection: $selection) {
                buttonPicker(module: .value)

                buttonPicker(module: .table)
            } label: {
                Text("Module selection")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            ZStack {
                switch selection {
                case .value:
                    root.photoRoot.viewController.linkWindow(root: root.photoRoot, isInspector: type == .inspector)
//                    root.characterRoot.viewController.linkWindow(root: root.characterRoot, isInspector: type == .inspector)
                default:
//                    root.tableRoot.viewController.linkWindow(root: root.tableRoot, isInspector: type == .inspector)
                    root.diceRoot.viewController.linkWindow(root: root.diceRoot, isInspector: type == .inspector)

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
