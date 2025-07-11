// @copyright André Trettin

import SwiftUI

public extension View {
    
    /// A helper function that returns a platform-specific
    func valueFor<V>(iOS: V, macOS: V, tvOS: V, visionOS: V) -> V {
#if os(visionOS)
        visionOS
#elseif os(tvOS)
        tvOS
#elseif os(macOS)
        macOS
#else
        iOS
#endif
    }
    
    /// A Boolean value that indicates whether the current platform is visionOS.
    ///
    /// If the value is `true`, `isMobile` is also true.
    var isVision: Bool {
#if os(visionOS)
        true
#else
        false
#endif
    }
    
    /// A Boolean value that indicates whether the current platform is iOS or iPadOS.
    var isMobile: Bool {
#if os(iOS)
        true
#else
        false
#endif
    }
    
    /// A Boolean value that indicates whether the current platform is tvOS.
    var isTV: Bool {
#if os(tvOS)
        true
#else
        false
#endif
    }
    
    /// A Boolean value that indicates whether the current platform is macOS.
    var isMac: Bool {
#if os(macOS)
        true
#else
        false
#endif
    }
}
