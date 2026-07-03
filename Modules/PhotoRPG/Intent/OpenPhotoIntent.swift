// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import AppIntents
import Foundation
import SwiftUI


struct OpenPhotoIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Photo"

    @Parameter(title: "Photo", requestValueDialog: "Which photo?")
    var target: PhotoEntity

    @Dependency var navigator: Navigator

    func perform() async throws -> some IntentResult {
        await navigator.perform(route: KnownRoutes.photos(target.id, nil))
        return .result()
    }
}

#if os(iOS)
extension OpenPhotoIntent: TargetContentProvidingIntent {}
#endif

extension PhotoRootModel {
    @MainActor
    func addSiriContext(to activity: NSUserActivity, itemId: UUID) {
#if compiler(>=6.4)
        guard #available(iOS 27, macOS 27, visionOS 27, *) else { return }
        activity.appEntityIdentifier = EntityIdentifier(for: PhotoEntity.self, identifier: itemId)
#endif
    }

    @MainActor
    func donateSiriViewingIntent(for itemId: UUID) async {
#if compiler(>=6.4)
        guard #available(iOS 27, macOS 27, visionOS 27, *),
              let model = itemController.itemSync(for: itemId)
        else { return }

        var intent = OpenPhotoIntent()
        intent.target = PhotoEntity(root: self, model: model)
        do {
            try await IntentDonationManager.shared.donate(intent: intent)
        } catch {}
#endif
    }
}

#endif
