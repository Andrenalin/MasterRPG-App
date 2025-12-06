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
    @State private var audioSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false)
    @State private var diceSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false)
    @State private var characterSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false)
    @State private var mapSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: true, allowCollections: true, allowEntrySelection: true)
    @State private var photoSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: true, allowCollections: true, allowEntrySelection: false)
    @State private var tableSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false)

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
                    root.audioRoot.viewController.linkListView(type: .inspector, itemSelectionModel: diceSelectionModel)
                case .dice:
                    root.diceRoot.viewController.linkListView(type: .inspector, itemSelectionModel: diceSelectionModel)
                case .photo:
                    root.photoRoot.viewController.linkListView(type: .inspector, itemSelectionModel: photoSelectionModel)
                case .table:
                    root.tableRoot.viewController.linkListView(type: .inspector, itemSelectionModel: tableSelectionModel)
                case .value:
                    root.characterRoot.viewController.linkListView(type: .inspector, itemSelectionModel: characterSelectionModel)
                default:
                    root.viewController.linkListView(type: .inspector, itemSelectionModel: mapSelectionModel)
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
