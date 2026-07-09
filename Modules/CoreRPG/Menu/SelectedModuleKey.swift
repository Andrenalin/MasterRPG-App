// @copyright André Trettin

import SwiftUI

/// The currently-selected SheetEntryView row, published by SheetRootView so the
/// macOS/iPadOS menu bar (ModuleCommands) can surface Edit/Duplicate/Move/Delete
/// for it with live keyboard shortcuts.
public struct SelectedSheetEntry {
    public let rootModel: SheetRootModel
    public let parentModel: SheetModel
    public let entryModel: SheetModel
    public let isEditor: Bool
}

public extension FocusedValues {
    @Entry var selectedModule: Binding<NetworkModules>?
    @Entry var listDisplayModel: ListDisplayModel?
    @Entry var selectedSheetEntry: SelectedSheetEntry?
}
