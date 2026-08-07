// @copyright André Trettin

import Observation

/// Tracks whether the table sheet's `.searchable` toolbar item should be attached.
///
/// On macOS, hiding the Game sidebar's content (see `GameSidebarToolbarMenu`) removes the
/// `TableRootSheet` from the view tree, but a `.searchable` modifier already installed on the
/// window toolbar can linger behind — the search field stays visible with nothing left to
/// search. `TableSheetView` only attaches `.searchable` while this flag is `true`, and the
/// sidebar toggle flips it to `false` before the content disappears.
@MainActor @Observable
public final class SearchBarVisibleModel: Sendable {
    public init() {}

    public var isVisible: Bool = true
}
