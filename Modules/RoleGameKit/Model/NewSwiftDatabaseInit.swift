// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData

import AdventureRPG
import AudioRPG
import CharacterRPG
import DiceRPG
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import WeatherRPG

@MainActor
struct NewSwiftDatabaseInit {
    static func initModelContainer() -> ModelContainer {
        let schema = Schema([
            ItemDataModel.self,
            EntryDataModel.self,
            LinkDataModel.self,
            TagDataModel.self,
            AdventureDataModel.self,
            CharacterDataModel.self,
            DiceDataModel.self,
            MapDataModel.self,
            PdfDataModel.self,
            TableDataModel.self,
            WeatherDataModel.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, allowsSave: true, groupContainer: .none, cloudKitDatabase: .private("icloud.de.andretrettin.MasterRPG"))
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
}
