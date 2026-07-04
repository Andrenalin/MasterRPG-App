// @copyright André Trettin

import CoreData
import CoreRPG
import Foundation
import UniformTypeIdentifiers

@MainActor public struct PhotoDataController: FileUrlAccessible {
    public init() {}
    
    public func saveFileUrl(fileUrl: CoreRPG.FileUrl) async {
        // not needed
    }
        
    public func addNewPhoto(context: NSManagedObjectContext, data: Data, name: String, text: String) async -> (UUID, String) {
        let dataController = DataController(context: context, token: NetworkModules.photo.token)
        let model = PhotoModel.empty.copy()
        model.category = .entry
        
        model.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        model.description = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let filePath = "\(name).jpg"
        var dataFileUrl = FileUrl(fileId: model.id, url: URL(string: filePath)!, location: .newCloud, module: NetworkModules.photo.token, relativeUrl: nil)
        dataFileUrl.resetData(data)
        
        let fileUrlDataController = FileUrlDataController(moduleFolder: NetworkModules.photo.token, fileTypes: [.image], filenameExtension: "jpg", fileUrlAccess: self)

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
