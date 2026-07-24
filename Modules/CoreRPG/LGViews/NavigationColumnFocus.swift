// @copyright André Trettin

import SwiftUI

/// Keyboard focus shared by the three columns of the editor layout.
public enum NavigationColumnFocus: Hashable, Sendable {
    case tabs
    case list
    case detail
}

public extension EnvironmentValues {
    @Entry var navigationColumnFocus: FocusState<NavigationColumnFocus?>.Binding?
}

public extension View {
    @ViewBuilder
    func navigationColumnFocused(
        _ focus: FocusState<NavigationColumnFocus?>.Binding?,
        equals value: NavigationColumnFocus
    ) -> some View {
        if let focus {
            focused(focus, equals: value)
        } else {
            self
        }
    }
}
