// @copyright André Trettin

import CoreText
import Foundation

/// The Shortcuts/share export of an item entity as plain text or a PDF, used when Siri hands the
/// item to another app ("summarize this", Writing Tools, Mail). Both carry the item's whole text —
/// name, description and entries — which each module registers once (`register(module:document:)`),
/// because an entity only holds its summary fields. Shared by every entity with a text export.
/// See CODE_AUDIT_18 §9.14, CODE_AUDIT_AppIntents3 §4.1.
public enum EntitySummaryExport {
    public struct RenderError: Error {}

    @MainActor private static var documents: [NetworkModules: @MainActor (UUID) -> String?] = [:]

    /// Registers how `module` turns an item id into its text (usually
    /// `IntentEntityText.document(of:)` of the live model), or `nil` when the item is gone.
    @MainActor
    public static func register(module: NetworkModules, document: @escaping @MainActor (UUID) -> String?) {
        documents[module] = document
    }

    /// The item's registered text; for an item that no longer exists (or a module without a
    /// registration) the name and description the entity still carries.
    @MainActor
    public static func text(id: UUID, module: NetworkModules, name: String, description: String) -> String {
        if let document = documents[module]?(id), !document.isEmpty {
            return document
        }
        return [name, description].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    @MainActor
    public static func plainText(id: UUID, module: NetworkModules, name: String, description: String) -> Data {
        Data(text(id: id, module: module, name: name, description: description).utf8)
    }

    /// Lays the item's text out on US Letter pages in the temporary directory, which the system
    /// empties: the text is private campaign content and must not outlive the export. The file name
    /// is derived from `id`, not the user-editable name, so equal names or concurrent exports can't
    /// collide (CODE_AUDIT_Character §6.1). Throws when the PDF context can't be created.
    /// The text is read on the main actor; laying out and writing the pages, up to 50,000
    /// characters, runs off it. See CODE_AUDIT_AppIntents2 §6.2, CODE_AUDIT_Since_3.0.1 §3.2.
    @MainActor
    public static func pdf(id: UUID, module: NetworkModules, name: String, description: String) async throws -> URL {
        let url = URL.temporaryDirectory.appending(component: "\(id.uuidString).pdf")
        let body = text(id: id, module: module, name: name, description: description)
        try await runOffCallerExecutor { try renderPdf(body, to: url) }
        return url
    }

    private static let pageSize = CGSize(width: 612, height: 792)
    private static let pageMargin: CGFloat = 54
    private static let fontSize: CGFloat = 12

    private static func renderPdf(_ body: String, to url: URL) throws {
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw RenderError()
        }
        var attributes: [NSAttributedString.Key: Any] = [:]
        if let font = CTFontCreateUIFontForLanguage(.system, fontSize, nil) {
            attributes[NSAttributedString.Key(kCTFontAttributeName as String)] = font
        }
        let attributed = NSAttributedString(string: body, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: mediaBox.insetBy(dx: pageMargin, dy: pageMargin), transform: nil)

        var location = 0
        repeat {
            context.beginPDFPage(nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            CTFrameDraw(frame, context)
            context.endPDFPage()
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { break }
            location += visible.length
        } while location < attributed.length
        context.closePDF()
    }
}
