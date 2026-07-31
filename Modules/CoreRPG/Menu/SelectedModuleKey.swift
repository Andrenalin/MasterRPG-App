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

@MainActor
public struct FocusedUndoActions {
    public init(
        canUndo: Bool,
        canRedo: Bool,
        undoTitle: String,
        redoTitle: String,
        undo: @escaping @MainActor () -> Void,
        redo: @escaping @MainActor () -> Void
    ) {
        self.canUndo = canUndo
        self.canRedo = canRedo
        self.undoTitle = undoTitle
        self.redoTitle = redoTitle
        self.undo = undo
        self.redo = redo
    }

    public let canUndo: Bool
    public let canRedo: Bool
    public let undoTitle: String
    public let redoTitle: String
    public let undo: @MainActor () -> Void
    public let redo: @MainActor () -> Void
}

public extension FocusedValues {
    @Entry var selectedModule: Binding<NetworkModules>?
    @Entry var listDisplayModel: ListDisplayModel?
    @Entry var moduleListIsFocused: Bool?
    @Entry var selectedSheetEntry: SelectedSheetEntry?
    @Entry var editorUndoActions: FocusedUndoActions?
}
