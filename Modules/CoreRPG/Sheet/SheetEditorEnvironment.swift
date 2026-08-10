// @copyright André Trettin

import SwiftUI

public extension EnvironmentValues {
    /// Mirrors `SheetRootView`'s `isEditor` flag for content nested through the
    /// `ViewControllable.rowViewer(source:destination:)` indirection (e.g. a
    /// module's `InlineRowViewer`), which has no other way to learn whether it
    /// is being rendered inside the sheet editor versus a read-only viewer.
    /// Set once by `SheetRootView`; everything below reads it via `@Environment`.
    @Entry var isSheetEditor: Bool = false
}
