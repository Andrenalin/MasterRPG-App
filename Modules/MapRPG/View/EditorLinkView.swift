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
            pickerRow(modules: firstRow)
            
            ZStack {
                root.audioRoot.viewController.linkListView(type: .inspector, itemSelectionModel: audioSelectionModel)
                    .opacity(selection == .audio ? 1 : 0)
                
                root.characterRoot.viewController.linkListView(type: .inspector, itemSelectionModel: characterSelectionModel)
                    .opacity(selection == .value ? 1 : 0)
                
                root.diceRoot.viewController.linkListView(type: .inspector, itemSelectionModel: diceSelectionModel)
                    .opacity(selection == .dice ? 1 : 0)
                
                root.viewController.linkListView(type: .inspector, itemSelectionModel: mapSelectionModel)
                    .opacity(selection == .map ? 1 : 0)
                                
                root.photoRoot.viewController.linkListView(type: .inspector, itemSelectionModel: photoSelectionModel)
                    .opacity(selection == .photo ? 1 : 0)
                
                root.tableRoot.viewController.linkListView(type: .inspector, itemSelectionModel: tableSelectionModel)
                    .opacity(selection == .table ? 1 : 0)
            }
        }
    }
    
    var firstRow: [NetworkModules] {
        [.map, .value, .table, .photo, .audio, .dice]
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
