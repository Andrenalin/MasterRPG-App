// @copyright André Trettin

import SwiftUI

@MainActor @Observable public final class AppNavigationModel {
    public var initialRouteType: AppInitialRouteType = .initializing
    var modeRouteType: AppModeRouteType = AppNavigationModel.defaultMode
    
    

#if os(macOS) || os(tvOS)
    static private let defaultMode = AppModeRouteType.gameSetup
#else
    static private let defaultMode = AppModeRouteType.editor
#endif

}
