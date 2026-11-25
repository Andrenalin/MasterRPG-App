// @copyright André Trettin

import SwiftUI

#if !os(tvOS)
public struct ModuleCommands: Commands {
    public init(root: any ItemRootControllable, scenesManager: ScenesManager, routeActions: RouteActions, key: AKKeyEquivalent) {
        self.root = root
        self.scenesManager = scenesManager
        self.routeActions = routeActions
        self.key = key
    }

    let root: any ItemRootControllable
    let scenesManager: ScenesManager
    let routeActions: RouteActions
    let key: AKKeyEquivalent

    @FocusedBinding(\.selectedModule) private var selectedModule: NetworkModules?
    @FocusedValue(\.listDisplayModel) private var listDisplayModel: ListDisplayModel?
    @FocusedValue(\.moduleListIsFocused) private var moduleListIsFocused: Bool?
    @FocusedValue(\.selectedSheetEntry) private var selectedSheetEntry: SelectedSheetEntry?
    @FocusedValue(\.editorUndoActions) private var editorUndoActions: FocusedUndoActions?
    @FocusedValue(\.viewportZoom) private var viewportZoom: FocusedViewportZoom?
    @FocusedValue(\.listSelectionActions) private var listSelectionActions: FocusedListSelectionActions?

    public var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            LinkWindowCommandView(networkModule: root.configurable.module, scenesManager: scenesManager, key: key)
        }
        CommandGroup(after: .toolbar) {
            NavigateButton(root: root, routeActions: routeActions, key: key)
        }
        CommandGroup(after: .newItem) {
            if selectedModule == root.configurable.module {
                AddItemButton(root: root, routeActions: routeActions)
                AddFolderButton(root: root, routeActions: routeActions)
                AddCollectionButton(root: root, routeActions: routeActions)
            }
        }
        CommandGroup(before: .textEditing) {
            if selectedModule == root.configurable.module {
                SpaceActionButton(
                    root: root,
                    scenesManager: scenesManager,
                    isListFocused: moduleListIsFocused == true
                )
                EditItemButton(root: root)
                DuplicateItemButton(root: root)
                ExportItemButton(root: root)
                GroupEditorButton(root: root)
                if root.viewControllable.supportsBatchExtraction {
                    BatchExtractionButton(root: root)
                }
                Divider()
                AddItemIntoButton(root: root)
                MoveItemIntoButton(root: root)
                Divider()
                DeleteItemButton(root: root, isListFocused: moduleListIsFocused == true)
                Divider()
            }
        }
        // The Edit menu, next to the system's Select All, which a text field answers.
        CommandGroup(after: .pasteboard) {
            if selectedModule == root.configurable.module {
                ModuleSelectAllButton(root: root, focused: listSelectionActions)
                ModuleSelectNoneButton(root: root, focused: listSelectionActions)
            }
        }
        CommandGroup(after: .textEditing) {
            if selectedModule == root.configurable.module,
               let selectedSheetEntry, selectedSheetEntry.entryModel.source.typeId == root.configurable.module {
                SheetEntryEditButton(rootModel: selectedSheetEntry.rootModel, entryModel: selectedSheetEntry.entryModel, parentModel: selectedSheetEntry.parentModel, isEditor: selectedSheetEntry.isEditor, onlyIcon: false)
                SheetContextMenuView(rootModel: selectedSheetEntry.rootModel, parentModel: selectedSheetEntry.parentModel, entryModel: selectedSheetEntry.entryModel, isEditor: selectedSheetEntry.isEditor)
                SheetEntryDeleteButton(rootModel: selectedSheetEntry.rootModel, parentModel: selectedSheetEntry.parentModel, entryModel: selectedSheetEntry.entryModel, onlyIcon: false)
            }
        }
        CommandGroup(replacing: .undoRedo) {
            if selectedModule == root.configurable.module {
                if let editorUndoActions {
                    FocusedEditorUndoButton(actions: editorUndoActions)
                    FocusedEditorRedoButton(actions: editorUndoActions)
                } else {
                    UndoButton(root: root)
                    RedoButton(root: root)
                }
            }
        }
        CommandGroup(after: .toolbar) {
            if selectedModule == root.configurable.module, let viewportZoom {
                Button {
                    viewportZoom.zoomIn()
                } label: {
                    Text("Zoom In", bundle: .module)
                }
                .keyboardShortcut("+", modifiers: .command)
                Button {
                    viewportZoom.zoomOut()
                } label: {
                    Text("Zoom Out", bundle: .module)
                }
                .keyboardShortcut("-", modifiers: .command)
                Button {
                    viewportZoom.reset()
                } label: {
                    Text("Fit to Window", bundle: .module)
                }
                .keyboardShortcut(ModuleMenuPolicy.fitToWindowKey, modifiers: ModuleMenuPolicy.fitToWindowModifiers)
            }
        }
        CommandGroup(before: .sidebar) {
            if selectedModule == root.configurable.module, let listDisplayModel {
                MenuDisplayModeToggle(listDisplayModel: listDisplayModel, showSelectionButton: true)
                Divider()
                OpenFolderButton(
                    root: root,
                    isListFocused: moduleListIsFocused == true
                )
                CloseFolderButton(root: root)
                Divider()
            }
        }
    }
}

private struct FocusedEditorUndoButton: View {
    let actions: FocusedUndoActions

    var body: some View {
        Button {
            withAnimation {
                actions.undo()
            }
        } label: {
            Label {
                Text("Undo \(actions.undoTitle)", bundle: .module)
            } icon: {
                Image(systemName: "arrow.uturn.backward")
            }
        }
        .keyboardShortcut("z", modifiers: [.command])
        .disabled(!actions.canUndo)
    }
}

private struct FocusedEditorRedoButton: View {
    let actions: FocusedUndoActions

    var body: some View {
        Button {
            withAnimation {
                actions.redo()
            }
        } label: {
            Label {
                Text("Redo \(actions.redoTitle)", bundle: .module)
            } icon: {
                Image(systemName: "arrow.uturn.forward")
            }
        }
        .keyboardShortcut("z", modifiers: [.command, .shift])
        .disabled(!actions.canRedo)
    }
}
#endif
