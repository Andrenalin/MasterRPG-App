// @copyright André Trettin

import SwiftUI

extension Color {
    // MARK: - Background Colors
    public static var adaptiveBackground: Color {
#if os(iOS)
        Color(UIColor.systemBackground)
#elseif os(macOS)
        Color(NSColor.windowBackgroundColor)
#else
        Color(.systemBackground)
#endif
    }
}
