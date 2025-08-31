// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData

import AudioRPG
import DiceRPG
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
            DiceDataModel.self,
            DieDataModel.self,
            PdfDataModel.self,
            TableDataModel.self,
            TableEntryDataModel.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, allowsSave: true, groupContainer: .none, cloudKitDatabase: .private("icloud.de.andretrettin.MasterRPG"))
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
}
