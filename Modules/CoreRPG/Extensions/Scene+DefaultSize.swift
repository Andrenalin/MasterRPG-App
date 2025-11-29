// @copyright André Trettin

import SwiftUI

public extension Scene {
    func defaultSizeAll(_ size: CGSize) -> some Scene {
#if os(tvOS)
        self
#else
        self.defaultSize(size)
#endif
    }
}

