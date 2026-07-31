// @copyright André Trettin

import Observation

/// Shared keyboard focus state for the tab/list/detail columns, injected once app-wide so
/// every window and platform reads and writes the same value — `TabSidebar` moves focus into
/// the list, `ListRootView` moves it back to the tabs or forward to the detail, `SheetRootView`
/// (the detail column) moves it back to the list.
@MainActor @Observable
public final class AppFocusModel: Sendable {
    public init(navigationColumnFocus: NavigationColumnFocus = .none) {
        self.navigationColumnFocus = navigationColumnFocus
    }

    public var navigationColumnFocus: NavigationColumnFocus
}
