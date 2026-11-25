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

/// Select All / Select None of the focused module list, for the menu bar and the keyboard. Only a
/// list in selection mode takes them.
@MainActor
public struct FocusedListSelectionActions {
    public init(
        isSelectionMode: Bool,
        selectAllFolderName: @escaping @MainActor () -> String? = { nil },
        selectAll: @escaping @MainActor () -> Void,
        selectNone: @escaping @MainActor () -> Void
    ) {
        self.isSelectionMode = isSelectionMode
        self.selectAllFolderName = selectAllFolderName
        self.selectAll = selectAll
        self.selectNone = selectNone
    }

    public let isSelectionMode: Bool
    /// The name of the folder or collection Select All selects the content of; nil when it selects
    /// every row. A closure, read when the menu is shown: the row the keyboard is on changes
    /// without the list rebuilding its focused value.
    public let selectAllFolderName: @MainActor () -> String?
    public let selectAll: @MainActor () -> Void
    public let selectNone: @MainActor () -> Void
}

/// Zoom commands of the focused canvas (the map editor), for the View menu on macOS and the
/// keyboard. The canvas has no scroll-wheel zoom API in SwiftUI, so the commands are the
/// pointer-free way to zoom. See CODE_AUDIT_26 §8.22.
public struct FocusedViewportZoom {
    public init(zoomIn: @escaping @MainActor () -> Void, zoomOut: @escaping @MainActor () -> Void, reset: @escaping @MainActor () -> Void) {
        self.zoomIn = zoomIn
        self.zoomOut = zoomOut
        self.reset = reset
    }

    public let zoomIn: @MainActor () -> Void
    public let zoomOut: @MainActor () -> Void
    public let reset: @MainActor () -> Void
}

public extension FocusedValues {
    @Entry var selectedModule: Binding<NetworkModules>?
    @Entry var listDisplayModel: ListDisplayModel?
    @Entry var moduleListIsFocused: Bool?
    @Entry var selectedSheetEntry: SelectedSheetEntry?
    @Entry var editorUndoActions: FocusedUndoActions?
    @Entry var listSelectionActions: FocusedListSelectionActions?
    @Entry var viewportZoom: FocusedViewportZoom?
}
