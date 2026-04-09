// @copyright André Trettin

import CoreData
import CoreRPG
import Foundation

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

        context.performAndWait {
            let dbmodel = RPGAdventure(context: context)
            dataController.mapModel(model, into: dbmodel)
        }
    }
}
