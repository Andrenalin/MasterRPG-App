//// @copyright André Trettin
//
//#if !os(tvOS)
//
//import RolePlayGameKit
//import AdventureRPG
//import AudioRPG
//import CharacterRPG
//import DiceRPG
//import MapRPG
//import PdfRPG
//import PhotoRPG
//import SpaceRPG
//import TableRPG
//import WeatherRPG
//import SwiftUI
//
//struct MenuCommandList: Commands {
//    let appModel: AppModel
//
//    var body: some Commands {
//        Group {
//            Group {
//                AdventureCommands(root: appModel.adventureRoot, navigator: appModel.navigator)
//                CharacterCommands(root: appModel.characterRoot, navigator: appModel.navigator)
//                PdfCommands(root: appModel.pdfRoot, navigator: appModel.navigator)
//                TableCommands(root: appModel.tableRoot, navigator: appModel.navigator)
//                MapCommands(root: appModel.mapRoot, navigator: appModel.navigator)
//            }
//            Group {
//                AudioCommands(root: appModel.audioRoot, navigator: appModel.navigator)
//                DiceCommands(root: appModel.diceRoot, navigator: appModel.navigator)
//                PhotoCommands(root: appModel.photoRoot, navigator: appModel.navigator)
//                SpaceCommands(root: appModel.spaceRoot, navigator: appModel.navigator)
//                WeatherCommands(root: appModel.weatherRoot, navigator: appModel.navigator)
//            }
//        }
//    }
//}
//
//#endif
