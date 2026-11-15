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
        // The portrait is the first photo, as `EditController.add(selection:)` sets it; without it
        // the character shows no thumbnail or pin photo until a repair pass. See CODE_AUDIT_26 §5.31.
        model.photoId = photoIds.first

        // Snapshot on the MainActor; only the Sendable value crosses into the context.
        let snapshot = dataController.makeSnapshot(from: model)
        await context.perform {
            let dbmodel = RPGValue(context: context)
            dataController.applySnapshot(snapshot, into: dbmodel)
        }
    }
}
