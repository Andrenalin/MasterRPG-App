// @copyright André Trettin

import SwiftUI

public extension EnvironmentValues {
    /// Space occupied by game chrome beside the interactive map viewport.
    ///
    /// `MapEditor` applies this value only to its canvas. Its navigation and
    /// toolbar chrome intentionally keep the full container width.
    @Entry var mapViewportTrailingInset: CGFloat = 0
}
