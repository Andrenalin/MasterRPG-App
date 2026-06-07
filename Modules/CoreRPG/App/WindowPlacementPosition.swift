// @copyright André Trettin

import SwiftUI

public enum WindowPlacementPosition {
    case utilityPanel
    case leading(_ id: String, fallback: String? = nil)
    case trailing(_ id: String, fallback: String? = nil)
    case above(_ id: String, fallback: String? = nil)
    case below(_ id: String, fallback: String? = nil)
}

/// Cross-platform restoration behavior for scenes
/// Mirrors SwiftUI's SceneRestorationBehavior but works on all platforms
public enum SceneRestorationBehaviorAll {
    /// Automatic restoration behavior (default)
    case automatic
    /// Prevents the scene from being automatically restored
    case disabled
    case disabledOnlyVisionOS
}

extension SwiftUI.Scene {
    public func defaultWindowPlacementAll(_ windowPlacementPosition: WindowPlacementPosition) -> some SwiftUI.Scene {
#if os(visionOS)
        return self.defaultWindowPlacement { content, context in
            func firstWindowProxy(withID id: String, fallback: String?) -> WindowProxy? {
                if let windowProxy = context.windows.first(where: { $0.id == id }) {
                    return windowProxy
                } else if let fallback, let windowProxy = context.windows.first(where: { $0.id == fallback }) {
                    return windowProxy
                } else {
                    assertionFailure("windowProxy is undefined")
                    return nil
                }
            }
            
            switch windowPlacementPosition {
            case .utilityPanel:
                return WindowPlacement(.utilityPanel)
            case .leading(let id, let fallback):
                if let windowProxy = firstWindowProxy(withID: id, fallback: fallback) {
                    return WindowPlacement(.leading(windowProxy))
                } else {
                    return WindowPlacement(.none)
                }
            case .trailing(let id, let fallback):
                if let windowProxy = firstWindowProxy(withID: id, fallback: fallback) {
                    return WindowPlacement(.trailing(windowProxy))
                } else {
                    return WindowPlacement(.none)
                }
            case .above(let id, let fallback):
                if let windowProxy = firstWindowProxy(withID: id, fallback: fallback) {
                    return WindowPlacement(.above(windowProxy))
                } else {
                    return WindowPlacement(.none)
                }
            case .below(let id, let fallback):
                if let windowProxy = firstWindowProxy(withID: id, fallback: fallback) {
                    return WindowPlacement(.below(windowProxy))
                } else {
                    return WindowPlacement(.none)
                }
            }
        }
#else
        return self
#endif
    }
    
    /// Applies restoration behavior with platform-specific checks
    /// On platforms that don't support `.restorationBehavior`, this is a no-op
    /// Mac always restore / visionOS not
    public func restorationBehaviorAll(_ behavior: SceneRestorationBehaviorAll) -> some SwiftUI.Scene {
#if os(macOS) || os(visionOS)
        switch behavior {
        case .automatic:
            self.restorationBehavior(.automatic)
        case .disabled:
            self.restorationBehavior(.disabled)
        case .disabledOnlyVisionOS:
#if os(visionOS)
            self.restorationBehavior(.disabled)
#else
            self.restorationBehavior(.automatic)
#endif
        }
#else
        return self
#endif
    }
}
