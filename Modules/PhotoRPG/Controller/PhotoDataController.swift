// @copyright André Trettin

import CoreData
import CoreRPG
import Foundation
import UniformTypeIdentifiers

@MainActor public struct PhotoDataController: Sendable {
    public init() {}
        
    public func addNewPhoto(context: NSManagedObjectContext, data: Data, name: String, text: String) async -> (UUID, String) {
        let dataController = DataController(context: context, token: NetworkModules.photo.token)
        let model = PhotoModel.empty.copy()
        model.category = .entry
        
        model.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        model.description = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // `name` is user-editable and can contain characters invalid in a URL string
        // (`#`, unencoded `%`/`?`, ...); `.appending(component:)` percent-encodes it,
        // unlike `URL(string:)` which would return nil (and previously force-unwrapped).
        let fileUrl = URL(string: "/")!.appending(component: "\(name).jpg")
        var dataFileUrl = FileUrl(fileId: model.id, url: fileUrl, location: .newCloud, module: NetworkModules.photo.token, relativeUrl: nil)
        dataFileUrl.resetData(data)
        
        let fileUrlDataController = FileUrlDataController(moduleFolder: NetworkModules.photo.token, fileTypes: [.image], filenameExtension: "jpg")

        model.fileUrl = try? await fileUrlDataController.createNewFileUrl(fileId: model.id, unconvertedFileUrl: dataFileUrl, pathExtension: "jpg")
        
        // Snapshot on the MainActor; only the Sendable value crosses into the context.
        let snapshot = dataController.makeSnapshot(from: model)
        context.performAndWait {
            let dbmodel = RPGPhoto(context: context)
            dataController.applySnapshot(snapshot, into: dbmodel)
        }
        return (model.id, model.url(linkNumber: 0))
    }
}
