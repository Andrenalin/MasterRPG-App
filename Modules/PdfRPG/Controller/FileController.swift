// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData
import UniformTypeIdentifiers

#if canImport(PDFKit)
import PDFKit
#endif

#if canImport(QuickLookThumbnailing)
import QuickLookThumbnailing
#endif

struct FileController: Sendable {
    static var fileTypes: [UTType] { [.pdf] }
    static var filenameExtension: String { "pdf" }
    
    private var _fileUrlDataController: FileUrlDataController?
    
    var fileUrlDataController: FileUrlDataController {
        _fileUrlDataController.unsafelyUnwrapped
    }
    
    @MainActor
    init() {
        _fileUrlDataController = FileUrlDataController(moduleFolder: PdfDataModel.typeId.token, fileTypes: FileController.fileTypes, filenameExtension: FileController.filenameExtension)
    }

#if !os(tvOS)
    func pdfDocument(itemId: UUID, actor: DataModelActor) async -> PDFDocument? {
        await actor.setup(id: itemId)
        guard let fileUrl = await actor.fileUrl else { return nil }
        try? await fileUrlDataController.download(fileUrl: fileUrl)
        return await fileUrlDataController.url(for: fileUrl) { url -> PDFDocument? in
            guard let url else { return nil }
            return PDFDocument(url: url)
        }
    }
#endif
}

extension FileController: FileControllable {
    func fileUrl(item: any Observable) async -> FileUrl? {
        guard let item = item as? PdfDataModel else { return nil }
        return item.fileUrl
//        guard let fileUrl = await root.itemController.item(for: item.id)?.fileUrl else {
//            return item.fileUrl
//        }
//        return fileUrl
    }
    
    func setFileUrl(_ fileUrl: FileUrl?, item: any Observable) async {
        guard let item = item as? PdfDataModel else { return }
//        if let oldFileUlr = item.fileUrl {
//            await root.cacheController.remove(itemId: oldFileUlr.fileId)
//        }
        item.url = fileUrl?.rawUrl
    }
    
    func fetchFileUrl() async -> [FileUrl] {
        var fileUrls: [FileUrl] = []
//        for itemId in await root.itemController.itemDataModel.items {
//            if let fileUrl = await root.itemController.item(for: itemId)?.fileUrl {
//                fileUrls.append(fileUrl)
//            }
//        }
        return fileUrls
    }

    func saveFileUrl(fileUrl: FileUrl) async {
//        guard let item = await root.itemController.item(for: fileUrl.fileId)?.copy() else { return }
//        if let fileId = item.fileUrl?.fileId {
//            await root.cacheController.remove(itemId: fileId)
//        }
//        item.fileUrl = fileUrl
//        await root.itemController.replace(model: item, isInsert: false, shouldRepairLinks: true)
    }
}
