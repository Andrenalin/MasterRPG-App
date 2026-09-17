// @copyright André Trettin

import CoreRPG
import Foundation
import UniformTypeIdentifiers
import os.log

#if canImport(PDFKit)
import PDFKit
#endif

struct ItemController: Sendable {
    @MainActor init(config: ModuleConfiguration) {
        self.config = config

        self.itemDataModel = ItemDataModel(categoryTags: config.categoryTags)
        self.collectionCategory = config.collectionCategory

        let fileUrlDataController = FileUrlDataController(moduleFolder: config.module.token, fileTypes: config.fileTypes, filenameExtension: config.filenameExtension)
        self.cacheController = CacheController(fileUrlDataController: fileUrlDataController)
        self.fileUrlDataController = fileUrlDataController
    }
    
    var cacheController: CacheController?
    let config: ModuleConfigurable
    let collectionCategory: ItemListCategory
    var fileUrlDataController: FileUrlDataController?
    let itemDataModel: ItemDataModel
}

extension ItemController: ItemControllable {
    typealias Model = PdfModel

    var cacheControllable: ImageCacheControllable? { cacheController }
    @MainActor var dataControllable: (any DataPersistenceControllable)? { itemDataModel.dataController }
}

extension ItemController {
#if !os(tvOS)
    func pdfDocument(for itemId: UUID) async -> PDFDocument? {
        guard let fileUrl = await self.item(for: itemId)?.fileUrl else { return nil }
        do {
            try await fileUrlDataController?.download(fileUrl: fileUrl)
        } catch is CancellationError {
            return nil
        } catch {
            Logger.itemController.error("Failed to download PDF for \(fileUrl.fileId, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        guard !Task.isCancelled else { return nil }
        // Decode off the MainActor: `fileUrlDataController` is @MainActor-isolated, so its
        // sync-closure `url(for:action:)` overload would otherwise run PDFDocument(url:)
        // inline on the MainActor — a real hitch for a large, multi-hundred-page PDF.
        // See CODE_AUDIT_Pdf §7.1.
        return await fileUrlDataController?.url(for: fileUrl) { url async -> PDFDocument? in
            guard let url else { return nil }
            return await Task.detached { PDFDocument(url: url) }.value
        }
    }
#endif
}
