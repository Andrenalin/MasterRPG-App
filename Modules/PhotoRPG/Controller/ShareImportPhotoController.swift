// @copyright André Trettin

import CoreData
import CoreRPG
import Foundation
import UniformTypeIdentifiers

/// Synthesizes a new Photo item from raw `Data` handed in by the Share Extension —
/// unrelated to `DataController`'s job of mapping a `PhotoModel` to/from its Core
/// Data snapshot. See CODE_AUDIT §9.7 (previously misleadingly named `PhotoDataController`).
@MainActor public struct ShareImportPhotoController: Sendable {
    public init() {}

    public func addNewPhoto(context: NSManagedObjectContext, data: Data, name: String, text: String) async -> (UUID, String) {
        let dataController = DataController(context: context, token: NetworkModules.photo.token)
        let model = PhotoModel.empty.copy()
        model.category = .entry

        model.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        model.description = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let filenameExtension = ModuleConfiguration().filenameExtension
        // `name` is user-editable and can contain characters invalid in a URL string
        // (`#`, unencoded `%`/`?`, ...); `.appending(component:)` percent-encodes it,
        // unlike `URL(string:)` which would return nil. `URL(filePath:)` is non-failable,
        // unlike the `URL(string: "/")!` this replaced.
        let fileUrl = URL(filePath: "/").appending(component: "\(name).\(filenameExtension)")
        var dataFileUrl = FileUrl(fileId: model.id, url: fileUrl, location: .newCloud, module: NetworkModules.photo.token, relativeUrl: nil)
        dataFileUrl.resetData(data)

        let fileUrlDataController = FileUrlDataController(moduleFolder: NetworkModules.photo.token, fileTypes: [.image], filenameExtension: filenameExtension)

        model.fileUrl = try? await fileUrlDataController.createNewFileUrl(fileId: model.id, unconvertedFileUrl: dataFileUrl, pathExtension: filenameExtension)

        // Snapshot on the MainActor; only the Sendable value crosses into the context.
        let snapshot = dataController.makeSnapshot(from: model)
        await context.perform {
            let dbmodel = RPGPhoto(context: context)
            dataController.applySnapshot(snapshot, into: dbmodel)
        }
        return (model.id, model.url(linkNumber: 0))
    }
}
