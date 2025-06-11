// @copyright André Trettin

import AppIntents
import Foundation
import RPGAdventures
import RoleGameKit
import SwiftUI
import AndrenalinKit
internal import _AppIntents_SwiftUI

struct OpenAdventure: AppIntent, OpenIntent {
    static let title: LocalizedStringResource = "Open Adventure"
    static let description = IntentDescription("Displays adventure details in the app.")
    
    @Parameter(title: "Adventure")
    var target: AdventureEntity
    
    func perform() async throws -> some IntentResult {
        let router = await AppStore.shared.routeActions
        await router.routePage(.adventure, target.id, nil)
        return .result()
    }
    
    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$target)")
    }
}


struct GetActiveAdventure: AppIntent {
    static let title: LocalizedStringResource = "Get Active Adventure"
    static let description = IntentDescription("Displays and read the active adventure details.")
        
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let appStore = await AppStore.shared
        //let gameRoot = await appStore.gameRoot
        let adventureRoot = await appStore.adventureRoot
        let viewController = adventureRoot.viewController
        //let itemId = await gameRoot.gameModel.selectedAdventure ?? UUID()
        let summary = "The adventure is not yet implemented."
        return .result(
            dialog: """
                Adventure summary: \(summary)
                """,
            view: viewController.viewMinimum(with: UUID())
        )
    }
}
