// @copyright André Trettin

import CoreRPG
import AppIntents


struct NavigateIntent: AppIntent {
    static let title: LocalizedStringResource = "Navigate to Section"
    
    static let supportedModes: IntentModes = .foreground
    
    static var parameterSummary: some ParameterSummary {
        Summary("Navigate to \(\.$navigationOption)")
    }
    
    @Parameter(
        title: "Section",
        requestValueDialog: "Which section?"
    )
    var navigationOption: NavigationOption
    
    @Dependency var appModel: AppModel
    
    func perform() async throws -> some IntentResult {
        await appModel.routeToModule(navigationOption.module)
        return .result()
    }
}

extension NavigateIntent {
    init(navigationOption: NavigationOption) {
        self.navigationOption = navigationOption
    }
}

#if os(iOS)
extension NavigateIntent: TargetContentProvidingIntent {}
#endif
