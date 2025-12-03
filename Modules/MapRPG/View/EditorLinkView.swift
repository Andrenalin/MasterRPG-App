// @copyright André Trettin

import AudioRPG
import CoreRPG
import CharacterRPG
import DiceRPG
import PhotoRPG
import TableRPG
import SwiftUI

struct EditorLinkView: View {
    @Environment(MapRootModel.self) private var root
    
    @State private var selection: NetworkModules = .map
    @State private var itemSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: true, allowCollections: true, allowEntrySelection: true)

    var body: some View {
        VStack {
            Picker(selection: $selection) {
                buttonPicker(module: .map)
                buttonPicker(module: .value)
                buttonPicker(module: .table)
                buttonPicker(module: .audio)
                buttonPicker(module: .photo)
                buttonPicker(module: .dice)
            } label: {
                Text("Module selection", bundle: .module)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            ZStack {
                switch selection {
                case .audio:
                    root.audioRoot.viewController.linkWindow(isInspector: true)
                case .dice:
                    root.diceRoot.viewController.linkWindow(isInspector: true)
                case .photo:
                    root.photoRoot.viewController.linkWindow(isInspector: true)
                case .table:
                    root.tableRoot.viewController.linkWindow(isInspector: true)
                case .value:
                    root.characterRoot.viewController.linkWindow(isInspector: true)
                default:
                    LinkItemRootView(root: root.rootController, type: .inspector)
                        .environment(itemSelectionModel)
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
