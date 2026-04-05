// @copyright André Trettin

import SwiftUI

@MainActor @Observable public final class AppNavigationModel {
    public init() {}
    
    public var initialRouteType: AppInitialRouteType = .initializing
    private(set) public var modeRouteType: AppModeRouteType = AppNavigationModel.defaultMode
    
    public var navigationType: AppNavigationRouteType = .split
    
    public func resetAppMode(isGame: Bool) {
        modeRouteType = isGame ? .game : AppNavigationModel.defaultMode
    }
    
    public var isGameRunning: Bool {
        modeRouteType == .game
    }
    
#if os(macOS) || os(tvOS)
    static private let defaultMode = AppModeRouteType.gameSetup
#else
    static private let defaultMode = AppModeRouteType.editor
#endif

}
