// @copyright André Trettin

import AppIntents
import Foundation
import SwiftUI
import CoreRPG
import CoreExternalRPG

@available(iOS 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, *)
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
@available(iOS 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension OpenPhotoIntent: TargetContentProvidingIntent {}
#endif


//struct GetActiveAdventure: AppIntent {
//    static let title: LocalizedStringResource = "Get Active Adventure"
//    static let description = IntentDescription("Displays and read the active adventure details.")
//        
//    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
//        let appStore = await AppStore.shared
//        //let gameRoot = await appStore.gameRoot
//        let adventureRoot = await appStore.adventureRoot
//        let viewController = adventureRoot.viewController
//        //let itemId = await gameRoot.gameModel.selectedAdventure ?? UUID()
//        let summary = "The adventure is not yet implemented."
//        return .result(
//            dialog: """
//                Adventure summary: \(summary)
//                """,
//            view: viewController.viewMinimum(with: UUID())
//        )
//    }
//}
