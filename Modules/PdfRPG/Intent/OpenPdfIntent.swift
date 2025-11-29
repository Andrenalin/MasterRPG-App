// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import AppIntents
import Foundation
import SwiftUI
import CoreExternalRPG

struct OpenPdfIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Pdf"

    @Parameter(title: "Pdf", requestValueDialog: "Which pdf?")
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

#endif
