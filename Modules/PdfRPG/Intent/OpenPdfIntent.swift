// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import AppIntents
import Foundation
import os.log
import SwiftUI


struct OpenPdfIntent: AppIntent {
    static let title: LocalizedStringResource = "Open PDF"
    static let description = IntentDescription(
        "Opens a PDF in the app.",
        categoryName: "PDF",
        searchKeywords: ["show", "book", "document"]
    )
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "PDF", requestValueDialog: .localized("Which PDF?", bundle: .module))
    var target: PdfEntity

    @Dependency var navigator: Navigator

    func perform() async throws -> some IntentResult {
        await navigator.perform(route: KnownRoutes.pdfs(target.id, nil))
        return .result()
    }
}

#if os(iOS)
extension OpenPdfIntent: TargetContentProvidingIntent {}
#endif

/// The iOS 27 open intent. `.system.open` lets Siri resolve "open <name> in MasterRPG" against
/// the indexed items; the schema supplies the title and the `target` parameter. It is a sibling
/// of `OpenPdfIntent` (the macro and schema are 27-only, and only one `OpenIntent` may name
/// an entity type) and takes the same route. See CODE_AUDIT_AppIntents §4.2.
@available(iOS 27, macOS 27, visionOS 27, *)
@AppIntent(schema: .system.open)
struct OpenPdfSchemaIntent: OpenIntent {
    /// Serves Siri and Spotlight; the legacy open intent is the one Shortcuts lists, so the library
    /// does not show two "open" actions per module. See CODE_AUDIT_AppIntents2 §4.2.
    static let isDiscoverable = false

    var target: PdfEntity

    @Dependency var navigator: Navigator

    init() {}

    func perform() async throws -> some IntentResult {
        await navigator.perform(route: KnownRoutes.pdfs(target.id, nil))
        return .result()
    }
}

#if os(iOS)
@available(iOS 27, *)
extension OpenPdfSchemaIntent: TargetContentProvidingIntent {}
#endif

extension PdfRootModel: SiriItemContext {
    public func siriEntityIdentifier(for itemId: UUID) -> EntityIdentifier? {
        EntityIdentifier(for: PdfEntity.self, identifier: itemId)
    }

    public func siriOpenIntent(for itemId: UUID) -> (any AppIntent)? {
        guard let model = itemController.itemSync(for: itemId) else { return nil }
        let entity = PdfEntity(root: self, model: model)
        if #available(iOS 27, macOS 27, visionOS 27, *) {
            let intent = OpenPdfSchemaIntent()
            intent.target = entity
            return intent
        }
        let intent = OpenPdfIntent()
        intent.target = entity
        return intent
    }
}

#endif
