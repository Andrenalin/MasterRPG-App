// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import AppIntents
import Foundation
import os.log
import SwiftUI


struct OpenPdfIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open PDF"

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

extension PdfRootModel {
    @MainActor
    func addSiriContext(to activity: NSUserActivity, itemId: UUID) {
        guard #available(iOS 27, macOS 27, visionOS 27, *) else { return }
        activity.appEntityIdentifier = EntityIdentifier(for: PdfEntity.self, identifier: itemId)
    }

    @MainActor
    func donateSiriViewingIntent(for itemId: UUID) async {
        guard #available(iOS 27, macOS 27, visionOS 27, *),
              let model = itemController.itemSync(for: itemId)
        else { return }

        let intent = OpenPdfIntent()
        intent.target = PdfEntity(root: self, model: model)
        do {
            try await IntentDonationManager.shared.donate(intent: intent)
        } catch {
            Logger.appIntents.debug("Failed to donate OpenPdfIntent for Siri/Shortcuts: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
        }
    }
}

#endif
