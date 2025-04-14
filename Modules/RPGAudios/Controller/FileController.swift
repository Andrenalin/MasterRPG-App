// @copyright André Trettin

import AndrenalinKit
import Foundation

struct FileController: Sendable {
    weak var root: AudioRoot!
    private var _fileUrlDataController: FileUrlDataController?
    
    var fileUrlDataController: FileUrlDataController {
        _fileUrlDataController.unsafelyUnwrapped
    }
    
    @MainActor
    init(root: AudioRoot) {
        self.root = root
        _fileUrlDataController = FileUrlDataController(moduleFolder: NetworkModules.audio.token, fileTypes: [.audio], filenameExtension: "m4a", fileUrlAccess: self)
    }
}

extension FileController: FileUrlAccessible, FileControllable {
    func fileUrl(item: any Observable) async -> FileUrl? {
        guard let item = item as? AudioModel else { return nil }
        guard let fileUrl = await root.itemController.item(for: item.id)?.fileUrl else {
            return item.fileUrl
        }
        return fileUrl
    }
    
    func setFileUrl(_ fileUrl: FileUrl?, item: any Observable) async {
        guard let item = item as? AudioModel else { return }
        item.fileUrl = fileUrl
    }

    func fetchFileUrl() async -> [FileUrl] {
        var fileUrls: [FileUrl] = []
        for itemId in await root.itemController.itemDataModel.items {
            if let fileUrl = await root.itemController.item(for: itemId)?.fileUrl {
                fileUrls.append(fileUrl)
            }
        }
        return fileUrls
    }

    func saveFileUrl(fileUrl: FileUrl) async {
        guard let item = await root.itemController.item(for: fileUrl.fileId)?.copy() else { return }
        item.fileUrl = fileUrl
        await root.itemController.replace(model: item, isInsert: false, shouldRepairLinks: true)
    }
}
