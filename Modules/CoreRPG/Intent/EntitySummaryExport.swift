// @copyright André Trettin

import SwiftUI

/// The Shortcuts/share export of an item entity as a one-page PDF summary or plain text.
/// Shared by the Adventure, Character, Map, Table and Weather entities, which had five copies
/// with different error handling (one silently returned a URL to a file that was never
/// written). See CODE_AUDIT_18 §9.14.
public enum EntitySummaryExport {
    public struct RenderError: Error {}

    /// Renders `name` and `description` into a PDF in the caches directory. The file name is
    /// derived from `id`, not the user-editable name, so equal names or concurrent exports
    /// can't collide (CODE_AUDIT_Character §6.1). Throws when the PDF context can't be created.
    @MainActor
    public static func pdf(id: UUID, name: String, description: String) throws -> URL {
        let url = URL.cachesDirectory.appending(component: "\(id.uuidString).pdf")
        let renderer = ImageRenderer(content: VStack {
            Text(verbatim: name)
            Text(verbatim: description)
        }.frame(width: 600))

        var renderError: (any Error)?
        renderer.render { size, render in
            var box = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else {
                renderError = RenderError()
                return
            }
            pdf.beginPDFPage(nil)
            render(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
        }
        if let renderError {
            throw renderError
        }
        return url
    }

    public static func plainText(name: String, description: String) -> Data {
        Data(
            """
            Name: \(name)
            Description: \(description)
            """.utf8
        )
    }
}
