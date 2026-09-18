// @copyright André Trettin

import CoreData
import CoreRPG
import Foundation

/// The Share Extension's (`RPGShare`) write path for adding a shared adventure directly to
/// the database — not part of the main `AdventureRootModel` controller hierarchy (unlike
/// `ItemController`/`EditController`/`DataController`/etc., it's never constructed by
/// `AdventureRootModel` and builds its own throwaway `DataController` internally). See
/// CODE_AUDIT §9.13.
@MainActor public struct AdventureDataController {
    public init() {}

    public func addNewAdventure(context: NSManagedObjectContext, name: String, text: String, photoIds: [UUID], photoLinks: [String]) async {
        let dataController = DataController(context: context, token: NetworkModules.adventure.token)
        let model = AdventureModel.empty.copy()
        model.category = .entry

        model.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        model.description = text.trimmingCharacters(in: .whitespacesAndNewlines)
        model.photoId = photoIds.first

        let entry = AdventureEntryModel(id: UUID(), name: String(localized: "Photos", bundle: .module).localizedString, content: photoLinks.joined(separator: ", "))
        model.entries.append(entry)

        // Snapshot on the MainActor; only the Sendable value crosses into the context.
        let snapshot = dataController.makeSnapshot(from: model)
        await context.perform {
            let dbmodel = RPGAdventure(context: context)
            dataController.applySnapshot(snapshot, into: dbmodel)
        }
    }
}
