// @copyright André Trettin

import SwiftUI

@MainActor @Observable public final class AppNavigationModel {
    public init(appGameStateModel: AppGameStateModel) {
        self.appGameStateModel = appGameStateModel
    }
    
    let appGameStateModel: AppGameStateModel
    
    public var initialRouteType: AppInitialRouteType = .initializing
    public var modeRouteType: AppModeRouteType { appGameStateModel.isGameRunning ? .game : AppNavigationModel.defaultMode
    }
    
    public var navigationType: AppNavigationRouteType = .split
        
#if os(macOS) || os(tvOS)
    static private let defaultMode = AppModeRouteType.gameSetup
#else
    static private let defaultMode = AppModeRouteType.editor
#endif

}
