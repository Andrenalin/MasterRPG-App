// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData
import UniformTypeIdentifiers

#if os(macOS)
internal import AppKit
#else
internal import UIKit
#endif

public struct EditController {
    @MainActor
    init(itemController: ItemController, fileUrlDataController: FileUrlDataController) {
        self.itemController = itemController
        self.fileUrlDataController = fileUrlDataController
    }
    
    let itemController: ItemController
    public let fileUrlDataController: FileUrlDataController?
}

// MARK: - EditControllable

extension EditController: EditControllable {
    public var itemControllable: any ItemControllable {
        itemController
    }
}

// MARK: - File Editor

extension EditController {
    func resetFile(image: AKImage?, id: UUID, actor: DataModelActor) async {
        guard let image else { return }
        let data = image.jpegData(compressionQuality: 0.9)
        await actor.setup(id: id)
        await resetFile(data: data, id: id, actor: actor)
        await actor.save()
    }

    func resetFile(data: Data, model: ItemDataModel) {
        guard let actor = model.modelActor() else { return }
        let id = model.id
        Task.detached {
            await actor.setup(id: id)
            await resetFile(data: data, id: id, actor: actor)
            await actor.save()
        }
    }
    
    private func resetFile(data: Data?, id: UUID, actor: DataModelActor) async {
        guard let fileUrlDataController else { return }
        await fileUrlDataController.delete(await actor.fileUrl)
        await actor.update(url: nil)
        guard let data else { return }
        
        let module = NetworkModules.photo.token
        let filePath = await actor.name.isEmpty ? "\(await actor.category.title)/Image-\(id.uuidString).\(FileController.filenameExtension)" : "\(await actor.category.title)/\(await actor.name).\(FileController.filenameExtension)"
        var dataFileUrl = FileUrl(fileId: id, url: URL(string: filePath)!, location: .cloud, module: module)
        dataFileUrl.resetData(data)
        
        let updatedFileUrl = try? await fileUrlDataController.createNewFileUrl(fileId: id, unconvertedFileUrl: dataFileUrl, pathExtension: FileController.filenameExtension)
        await actor.update(url: updatedFileUrl?.rawUrl)
    }
}

extension EditController {
#if os(macOS)
    static let importImageTypes = AKImage.imageTypes.compactMap { UTType($0) }

    nonisolated
    static func importImageFromProviders(_ itemProviders: [NSItemProvider], completion: @Sendable @escaping (Data?) -> Void) -> Bool {
        guard let provider = itemProviders.first else { return false }
        for type in importImageTypes {
            let typeIdentifier = type.identifier
            if provider.hasItemConformingToTypeIdentifier(typeIdentifier) {
                provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                    DispatchQueue.main.async {
                        completion(data)
                    }
                }
                return true
            }
        }
        return false
    }
#endif
}
