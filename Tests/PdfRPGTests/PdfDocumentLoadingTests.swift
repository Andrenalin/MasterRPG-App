// @copyright André Trettin

#if !os(tvOS)
@testable import CoreRPG
import Foundation
import PDFKit
import Testing
import UniformTypeIdentifiers

@testable import PdfRPG

/// CODE_AUDIT_26 §10.19: `pdfDocument(for:)` with an injected downloader, so cancellation and a
/// finished download can be told apart without the network or iCloud.
@MainActor
@Suite("Pdf document loading")
struct PdfDocumentLoadingTests {
    private func makeController(downloader: @escaping @Sendable (URL) async throws -> URL) -> (ItemController, UUID) {
        var controller = ItemController(config: ModuleConfiguration())
        let module = "PdfLoading-\(UUID().uuidString)"
        controller.fileUrlDataController = FileUrlDataController(
            moduleFolder: module,
            fileTypes: [.pdf],
            filenameExtension: "pdf",
            remoteFileDownloader: downloader
        )
        let itemId = UUID()
        let fileUrl = FileUrl(
            fileId: itemId,
            url: URL(string: "https://example.com/files/\(UUID().uuidString).pdf") ?? URL.temporaryDirectory,
            location: .url,
            module: module,
            relativeUrl: nil
        )
        controller.replace(model: PdfModel(id: itemId, name: "Remote", fileUrl: fileUrl), isInsert: true)
        return (controller, itemId)
    }

    private func writePdf() throws -> URL {
        let document = PDFDocument()
        document.insert(PDFPage(), at: 0)
        let url = URL.temporaryDirectory.appending(path: UUID().uuidString).appendingPathExtension("pdf")
        guard document.write(to: url) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }

    @Test("A cancelled load returns nil instead of an error document", .timeLimit(.minutes(1)))
    func cancelledLoadReturnsNil() async {
        let (controller, itemId) = makeController { _ in
            try await Task.sleep(for: .seconds(300))
            throw URLError(.timedOut)
        }

        let load = Task { @MainActor in await controller.pdfDocument(for: itemId)?.pageCount }
        try? await Task.sleep(for: .milliseconds(100))
        load.cancel()

        #expect(await load.value == nil)
    }

    @Test("A finished download opens the document", .timeLimit(.minutes(1)))
    func finishedDownloadOpensTheDocument() async throws {
        let source = try writePdf()
        let (controller, itemId) = makeController { _ in source }

        let document = await controller.pdfDocument(for: itemId)

        #expect(document?.pageCount == 1)
    }

    @Test("A failed download does not crash and leaves no document", .timeLimit(.minutes(1)))
    func failedDownloadReturnsNil() async {
        let (controller, itemId) = makeController { _ in throw URLError(.notConnectedToInternet) }

        #expect(await controller.pdfDocument(for: itemId) == nil)
    }

    @Test("An unknown item has no document", .timeLimit(.minutes(1)))
    func unknownItemHasNoDocument() async {
        let (controller, _) = makeController { _ in throw URLError(.badURL) }

        #expect(await controller.pdfDocument(for: UUID()) == nil)
    }
}
#endif
