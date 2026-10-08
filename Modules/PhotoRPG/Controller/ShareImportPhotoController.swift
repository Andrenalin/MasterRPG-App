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

    /// Throws when the image could not be written, instead of saving a photo whose file exists
    /// only in memory and is gone after relaunch. See CODE_AUDIT_Folder §5.11.
    public func addNewPhoto(context: NSManagedObjectContext, data: Data, name: String, text: String) async throws -> (UUID, String) {
        let added = try await addNewPhotoFile(context: context, data: data, name: name, text: text)
        return (added.photoId, added.link)
    }

    /// `addNewPhoto` that also returns the file it wrote, so a caller whose save fails
    /// afterwards can remove it with `removeFile(_:)`. See CODE_AUDIT_21 §5.27.
    public func addNewPhotoFile(context: NSManagedObjectContext, data: Data, name: String, text: String) async throws -> (photoId: UUID, link: String, fileUrl: FileUrl) {
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
        let fileUrl = URL(filePath: "/").appending(component: Self.fileName(for: name, photoId: model.id, extension: filenameExtension))
        var dataFileUrl = FileUrl(fileId: model.id, url: fileUrl, location: .newCloud, module: NetworkModules.photo.token, relativeUrl: nil)
        dataFileUrl.resetData(data)

        let fileUrlDataController = FileUrlDataController(moduleFolder: NetworkModules.photo.token, fileTypes: [.image], filenameExtension: filenameExtension)

        guard let storedFileUrl = try await fileUrlDataController.createNewFileUrl(fileId: model.id, unconvertedFileUrl: dataFileUrl, pathExtension: filenameExtension, requireDurableStorage: true) else {
            throw CocoaError(.fileWriteUnknown)
        }
        model.fileUrl = storedFileUrl

        // Snapshot on the MainActor; only the Sendable value crosses into the context.
        let snapshot = dataController.makeSnapshot(from: model)
        await context.perform {
            let dbmodel = RPGPhoto(context: context)
            dataController.applySnapshot(snapshot, into: dbmodel)
        }
        return (model.id, model.url(linkNumber: 0), storedFileUrl)
    }

    /// Removes a photo file `addNewPhotoFile` wrote and no saved item references.
    public func removeFile(_ fileUrl: FileUrl) async {
        let fileUrlDataController = FileUrlDataController(
            moduleFolder: NetworkModules.photo.token,
            fileTypes: [.image],
            filenameExtension: ModuleConfiguration().filenameExtension
        )
        await fileUrlDataController.removeStoredFile(fileUrl)
        fileUrlDataController.removeBookmarks(fileId: fileUrl.fileId)
    }

    /// A file name of its own for every shared image: all images of one share used
    /// `<name>.<ext>`, so they overwrote each other and any library photo of that name. Path
    /// separators are replaced, and an empty name gets a default. See CODE_AUDIT_Folder §5.11.
    static func fileName(for name: String, photoId: UUID, extension filenameExtension: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacing(/[\/\\:]/, with: "-")
        let base = trimmed.isEmpty ? "Photo" : trimmed
        return "\(base)-\(photoId.uuidString.prefix(8)).\(filenameExtension)"
    }
}
