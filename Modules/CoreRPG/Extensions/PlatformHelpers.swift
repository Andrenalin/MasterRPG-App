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
    
}
