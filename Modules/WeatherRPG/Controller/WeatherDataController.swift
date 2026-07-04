// @copyright André Trettin

import CoreData
import CoreRPG
import Foundation

@MainActor public struct WeatherDataController {
    public init() {}

    public func addNewWeather(context: NSManagedObjectContext, name: String, text: String, photoId: UUID?) async {
        let dataController = DataController(context: context, token: NetworkModules.weather.token)
        let model = WeatherModel.empty.copy()
        model.category = .entry

        model.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        model.description = text.trimmingCharacters(in: .whitespacesAndNewlines)
        model.photoId = photoId

        // Snapshot on the MainActor; only the Sendable value crosses into the context.
        let snapshot = dataController.makeSnapshot(from: model)
        context.performAndWait {
            let dbmodel = RPGWeather(context: context)
            dataController.applySnapshot(snapshot, into: dbmodel)
        }
    }
}
