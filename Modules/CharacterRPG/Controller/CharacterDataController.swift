// @copyright André Trettin

import CoreData
import CoreRPG
import Foundation

@MainActor public struct CharacterDataController {
    public init() {}

    public func addNewValue(context: NSManagedObjectContext, name: String, text: String, photoIds: [UUID]) async {
        let dataController = DataController(context: context, token: NetworkModules.value.token)
        let model = ValueModel.empty.copy()
        model.category = .entry

        model.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        model.description = text.trimmingCharacters(in: .whitespacesAndNewlines)
        model.photos = photoIds

        // Snapshot on the MainActor; only the Sendable value crosses into the context.
        let snapshot = dataController.makeSnapshot(from: model)
        context.performAndWait {
            let dbmodel = RPGValue(context: context)
            dataController.applySnapshot(snapshot, into: dbmodel)
        }
    }
}
