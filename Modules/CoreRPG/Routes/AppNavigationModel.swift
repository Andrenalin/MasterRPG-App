// @copyright André Trettin

import SwiftUI

@MainActor @Observable public final class AppNavigationModel {
#if os(macOS)
    public init(appGameStateModel: AppGameStateModel) {
        self.appGameStateModel = appGameStateModel
    }
#else
    public init(appGameStateModel: AppGameStateModel) {
        self.appGameStateModel = appGameStateModel
    }
    
    public func reset(sceneDelegate: AppWindowSceneModel) {
        self.sceneModel = sceneDelegate
    }
    
    public var sceneModel: AppWindowSceneModel?
#endif
    
    let appGameStateModel: AppGameStateModel
    
    public var initialRouteType: AppInitialRouteType = .initializing
    public var modeRouteType: AppModeRouteType { appGameStateModel.isGameRunning ? .game : AppNavigationModel.defaultMode
    }
    
#if os(iOS)
    static private let defaultMode = AppModeRouteType.editor
#elseif os(visionOS)
    static private let defaultMode = AppModeRouteType.gameVisionSetup
#else
    static private let defaultMode = AppModeRouteType.gameSetup
#endif
    
    public func canShowInspector(appSizeModel: AppWindowSizeModel) -> Bool {
#if os(macOS)
        true
#elseif os(iOS)
        appSizeModel.mode == .regular
#else
        false
#endif
    }
}

#if !os(macOS)
public protocol AppWindowSceneModel {
    var windowScene: UIWindowScene? { get }
}
#endif
