// @copyright André Trettin

import CoreRPG
import AppIntents


public struct NavigateIntent: AppIntent {
    public static let title: LocalizedStringResource = "Navigate to Section"
    
    public static let supportedModes: IntentModes = .foreground
    
    public static var parameterSummary: some ParameterSummary {
        Summary("Navigate to \(\.$navigationOption)")
    }
    
    @Parameter(
        title: "Section",
        requestValueDialog: "Which section?"
    )
    var navigationOption: NavigationOption
    
    @Dependency var appModel: AppModel

    public init() {}
    
    public func perform() async throws -> some IntentResult {
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
