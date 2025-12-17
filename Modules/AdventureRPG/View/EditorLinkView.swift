// @copyright André Trettin

import AudioRPG
import CoreRPG
import CharacterRPG
import DiceRPG
import PhotoRPG
import TableRPG
import SwiftUI
import MapRPG
import WeatherRPG
import PdfRPG
import SpaceRPG

struct EditorLinkView: View {
    @Environment(AdventureRootModel.self) private var root
    
    @State private var selection: NetworkModules = .map
    
    @State private var selectionFirstRow: NetworkModules? = .map
    @State private var selectionSecondRow: NetworkModules? = nil
    
    @State private var adventureSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true)
    @State private var audioSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false)
    @State private var characterSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false)
    @State private var diceSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false)
    @State private var mapSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true)
    @State private var pdfSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false)
    @State private var photoSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false)
    @State private var spaceSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false)
    @State private var tableSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true)
    @State private var weatherSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false)
    
    var body: some View {
        ManagedNavigationStack(name: "AdventureEditorLink") {
            VStack {
                pickerAll
                
                ZStack {
                    root.audioRoot.viewController.linkListView(type: .inspector, itemSelectionModel: audioSelectionModel)
                        .opacity(selection == .audio ? 1 : 0)
                    
                    root.characterRoot.viewController.linkListView(type: .inspector, itemSelectionModel: characterSelectionModel)
                        .opacity(selection == .value ? 1 : 0)
                    
                    root.diceRoot.viewController.linkListView(type: .inspector, itemSelectionModel: diceSelectionModel)
                        .opacity(selection == .dice ? 1 : 0)
                    
                    root.mapRoot.viewController.linkListView(type: .inspector, itemSelectionModel: mapSelectionModel)
                        .opacity(selection == .map ? 1 : 0)
                    
                    root.pdfRoot.viewController.linkListView(type: .inspector, itemSelectionModel: pdfSelectionModel)
                        .opacity(selection == .pdf ? 1 : 0)
                    
                    root.photoRoot.viewController.linkListView(type: .inspector, itemSelectionModel: photoSelectionModel)
                        .opacity(selection == .photo ? 1 : 0)
                    
                    root.spaceRoot.viewController.linkListView(type: .inspector, itemSelectionModel: spaceSelectionModel)
                        .opacity(selection == .space ? 1 : 0)
                    
                    root.tableRoot.viewController.linkListView(type: .inspector, itemSelectionModel: tableSelectionModel)
                        .opacity(selection == .table ? 1 : 0)
                    
                    root.weatherRoot.viewController.linkListView(type: .inspector, itemSelectionModel: weatherSelectionModel)
                        .opacity(selection == .weather ? 1 : 0)
                    
                    root.viewController.linkListView(type: .inspector, itemSelectionModel: adventureSelectionModel)
                        .opacity(selection == .adventure ? 1 : 0)
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }
    
    @ViewBuilder var pickerAll: some View {
        pickerRow(selectionRow: $selectionFirstRow, modules: firstRow)
        pickerRow(selectionRow: $selectionSecondRow, modules: secondRow)
            .onChange(of: selectionFirstRow) {
                guard let selectionFirstRow else { return }
                withAnimation {
                    selection = selectionFirstRow
                    selectionSecondRow = nil
                }
            }
            .onChange(of: selectionSecondRow) {
                guard let selectionSecondRow else { return }
                withAnimation {
                    selection = selectionSecondRow
                    selectionFirstRow = nil
                }
            }
    }
    
    func pickerRow(selectionRow: Binding<NetworkModules?>, modules: [NetworkModules]) -> some View {
        Picker(selection: selectionRow) {
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
    
    var firstRow: [NetworkModules] {
        [.adventure, .map, .value, .table, .weather]
    }

    var secondRow: [NetworkModules] {
        [.audio, .dice, .pdf, .photo, .space]
    }

    func buttonPicker(module: NetworkModules) -> some View {
        Image(systemName: module.icon)
            .tag(module)
    }
}

#Preview(traits: .mockData) {
    EditorLinkView()
}
