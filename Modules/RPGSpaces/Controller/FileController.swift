// @copyright André Trettin

import AndrenalinKit
import Foundation
internal import UniformTypeIdentifiers

struct FileController: Sendable {
    static var fileTypes: [UTType] { [.usdz] }
    static var filenameExtension: String { "usdz" }

    weak var root: SpaceRoot!
    private var _fileUrlDataController: FileUrlDataController?
    
    var fileUrlDataController: FileUrlDataController {
        _fileUrlDataController.unsafelyUnwrapped
    }
    
    @MainActor
    init(root: SpaceRoot) {
        self.root = root
        _fileUrlDataController = FileUrlDataController(moduleFolder: NetworkModules.space.token, fileTypes: FileController.fileTypes, filenameExtension: FileController.filenameExtension, fileUrlAccess: self)
    }

    func moveFiles() async throws {
        let itemIds = await root.itemController.itemDataModel.items
        for itemId in itemIds {
            let item = await root.itemController.itemOrEmpty(for: itemId)
            guard let fileUrl = item.fileUrl, fileUrl.location != .newCloud else { continue }
            if let newFileUrl = try? await root.fileUrlDataController.move(fileUrl: fileUrl, name: item.name, category: item.category.title) {
                let editController = await root.editController(type: .main)
                await editController.reset(fileUrl: newFileUrl, for: itemId)
            }
        }
    }
}

extension FileController: FileUrlAccessible, FileControllable {
    func fileUrl(item: any Observable) async -> FileUrl? {
        guard let item = item as? SpaceModel else { return nil }
        guard let fileUrl = await root.itemController.item(for: item.id)?.fileUrl else {
            return item.fileUrl
        }
        return fileUrl
    }
    
    func setFileUrl(_ fileUrl: FileUrl?, item: any Observable) async {
        guard let item = item as? SpaceModel else { return }
        if let oldFileUlr = item.fileUrl {
            await root.cacheController.remove(itemId: oldFileUlr.fileId)
        }
        item.fileUrl = fileUrl
    }

    func saveFileUrl(fileUrl: FileUrl) async {
        guard let item = await root.itemController.item(for: fileUrl.fileId)?.copy() else { return }
        if let fileId = item.fileUrl?.fileId {
            await root.cacheController.remove(itemId: fileId)
        }
        item.fileUrl = fileUrl
        await root.itemController.replace(model: item, isInsert: false, shouldRepairLinks: true)
    }
}
