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
        let model = PhotoModel.empty.copy()
        model.category = .entry
        
        model.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        model.description = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let filePath = "\(name).jpg"
        var dataFileUrl = FileUrl(fileId: model.id, url: URL(string: filePath)!, location: .newCloud, module: NetworkModules.photo.token, relativeUrl: nil)
        dataFileUrl.resetData(data)
        
        let fileUrlDataController = FileUrlDataController(moduleFolder: NetworkModules.photo.token, fileTypes: [.image], filenameExtension: "jpg", fileUrlAccess: self)

        model.fileUrl = try? await fileUrlDataController.createNewFileUrl(fileId: model.id, unconvertedFileUrl: dataFileUrl, pathExtension: "jpg")
        
//        context.performAndWait {
//            context.insert(model)
//            context.save()
//        }
        return (model.id, model.url(linkNumber: 0))
    }
}
