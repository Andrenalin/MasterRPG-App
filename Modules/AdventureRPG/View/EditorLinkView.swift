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

    @State private var selection: NetworkModules? = .map
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
        VStack {
            Picker(selection: $selection) {
                buttonPicker(module: .adventure)
                buttonPicker(module: .audio)
                buttonPicker(module: .value)
                buttonPicker(module: .dice)
                buttonPicker(module: .map)
                buttonPicker(module: .pdf)
                buttonPicker(module: .photo)
                buttonPicker(module: .space)
                buttonPicker(module: .table)
                buttonPicker(module: .weather)
            } label: {
                Text("Module selection", bundle: .module)
            }
            .pickerStyle(.automatic)
            .padding(.horizontal)

            ZStack {
                switch selection {
                case .audio:
                    root.audioRoot.viewController.linkListView(type: .inspector, itemSelectionModel: audioSelectionModel)
                case .value:
                    root.characterRoot.viewController.linkListView(type: .inspector, itemSelectionModel: characterSelectionModel)
                case .dice:
                    root.diceRoot.viewController.linkListView(type: .inspector, itemSelectionModel: diceSelectionModel)
                case .map:
                    root.mapRoot.viewController.linkListView(type: .inspector, itemSelectionModel: mapSelectionModel)
                case .pdf:
                    root.pdfRoot.viewController.linkListView(type: .inspector, itemSelectionModel: pdfSelectionModel)
                case .photo:
                    root.photoRoot.viewController.linkListView(type: .inspector, itemSelectionModel: photoSelectionModel)
                case .space:
                    root.spaceRoot.viewController.linkListView(type: .inspector, itemSelectionModel: spaceSelectionModel)
                case .table:
                    root.tableRoot.viewController.linkListView(type: .inspector, itemSelectionModel: tableSelectionModel)
                case .weather:
                    root.weatherRoot.viewController.linkListView(type: .inspector, itemSelectionModel: weatherSelectionModel)
                default:
                    root.viewController.linkListView(type: .inspector, itemSelectionModel: adventureSelectionModel)
                }
            }
            
//            TabView(selection: $selection) {
//                Tab(value: .adventure) {
//                    LinkItemRootView(root: root.rootController, type: .inspector)
//                } label: {
//                    Image(systemName: NetworkModules.adventure.icon)
//                }
//
//                Tab(value: .audio) {
//                    root.audioRoot.viewController.linkWindow(isInspector: true)
//                } label: {
//                    Image(systemName: NetworkModules.audio.icon)
//                }
//                Tab(value: .value) {
//                    root.characterRoot.viewController.linkWindow(isInspector: true)
//                } label: {
//                    Image(systemName: NetworkModules.value.icon)
//                }
//                Tab(value: .dice) {
//                    root.diceRoot.viewController.linkWindow(isInspector: true)
//                } label: {
//                    Image(systemName: NetworkModules.dice.icon)
//                }
//                Tab(value: .map) {
//                    root.mapRoot.viewController.linkWindow(isInspector: true)
//                } label: {
//                    Image(systemName: NetworkModules.map.icon)
//                }
//                Tab(value: .pdf) {
//                    root.pdfRoot.viewController.linkWindow(isInspector: true)
//                } label: {
//                    Image(systemName: NetworkModules.pdf.icon)
//                }
//                Tab(value: .photo) {
//                    root.photoRoot.viewController.linkWindow(isInspector: true)
//                } label: {
//                    Image(systemName: NetworkModules.photo.icon)
//                }
//                Tab(value: .space) {
//                    root.spaceRoot.viewController.linkWindow(isInspector: true)
//                } label: {
//                    Image(systemName: NetworkModules.space.icon)
//                }
//                Tab(value: .table) {
//                    root.tableRoot.viewController.linkWindow(isInspector: true)
//                } label: {
//                    Image(systemName: NetworkModules.table.icon)
//                }
//                Tab(value: .weather) {
//                    root.weatherRoot.viewController.linkWindow(isInspector: true)
//                } label: {
//                    Image(systemName: NetworkModules.weather.icon)
//                }
//            }
//            .tabViewStyle(.automatic)
//            .ignoresSafeArea(.container, edges: .bottom)
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
