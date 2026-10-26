// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import AppIntents
import Foundation
import os.log
import SwiftUI


struct OpenPdfIntent: AppIntent {
    static let title: LocalizedStringResource = "Open PDF"
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "PDF", requestValueDialog: "Which PDF?")
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

extension PdfRootModel {
    @MainActor
    /// `appEntityIdentifier` is available since iOS 18.2 / macOS 15.2 / visionOS 2.2, so it needs no
    /// iOS 27 gate. See CODE_AUDIT_AppIntents §5.1.
    func addSiriContext(to activity: NSUserActivity, itemId: UUID) {
        activity.appEntityIdentifier = EntityIdentifier(for: PdfEntity.self, identifier: itemId)
    }

    @MainActor
    /// Donates the open intent that matches the running OS, once the item stays selected.
    /// See CODE_AUDIT_AppIntents §4.4.
    func donateSiriViewingIntent(for itemId: UUID) async {
        await IntentDonations.donateOpen(of: itemId) { [self] () -> (any AppIntent)? in
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
}

#endif
