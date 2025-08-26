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
        _fileUrlDataController = FileUrlDataController(moduleFolder: NetworkModules.pdf.token, fileTypes: FileController.fileTypes, filenameExtension: FileController.filenameExtension)
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
