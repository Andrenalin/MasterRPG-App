// @copyright André Trettin

#if !os(tvOS)

import CoreGraphics
import CoreText
import Foundation
import PDFKit

/// Draws plain text pages into a PDF with CoreGraphics and CoreText, so the evaluation needs no
/// committed (and possibly copyrighted) PDF files and no UIKit/AppKit. The text stays selectable,
/// so `PDFPage.string`, which the analyzer reads, returns it.
enum PdfTagFixtureRenderer {
    enum RenderError: Error {
        case contextUnavailable
    }

    static func makeDocument(pages: [String]) throws -> PDFDocument {
        let data = try render(pages: pages)
        guard let document = PDFDocument(data: data) else {
            throw RenderError.contextUnavailable
        }
        return document
    }

    static func render(pages: [String]) throws -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw RenderError.contextUnavailable
        }

        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let textRect = mediaBox.insetBy(dx: 54, dy: 54)

        for text in pages {
            let attributed = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font
            ])
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: 0, length: 0),
                CGPath(rect: textRect, transform: nil),
                nil
            )
            context.beginPDFPage(nil)
            CTFrameDraw(frame, context)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }
}

#endif
