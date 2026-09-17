// @copyright André Trettin

#if !os(tvOS)
import PDFKit
import SwiftUI

struct ThumbnailPdfView: CustomViewRepresentable {
#if os(iOS) || os(visionOS)
    private static let contentInset = UIEdgeInsets(top: 10, left: 5, bottom: 10, right: 5)
#endif

    let pdfView: PDFView?
    let horizontal: Bool
    let thumbnailSize: CGSize
    
#if os(macOS)
    func makeNSView(context _: Context) -> PDFThumbnailView {
        makeView()
    }
#else
    func makeUIView(context _: Context) -> PDFThumbnailView {
        makeView()
    }
#endif

    @MainActor
    func makeView() -> PDFThumbnailView {
        let view = PDFThumbnailView()
        view.thumbnailSize = thumbnailSize
#if os(iOS) || os(visionOS)
        view.layoutMode = horizontal ? .horizontal : .vertical
        view.backgroundColor = .systemGray
        view.contentInset = Self.contentInset
#else
        view.backgroundColor = NSColor.underPageBackgroundColor
#endif
        view.pdfView = pdfView
        return view
    }
    
#if os(macOS)
    func updateNSView(_ pdfView: PDFThumbnailView, context: Context) {
        updateView(pdfView, context: context)
    }
#else
    func updateUIView(_ pdfView: PDFThumbnailView, context: Context) {
        updateView(pdfView, context: context)
    }
#endif
    
    func updateView(_ pdfView: PDFThumbnailView, context: Context) {
    }
}

#endif
